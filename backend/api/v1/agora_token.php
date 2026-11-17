<?php
/**
 * Agora AccessToken2 generator
 * POST /api/v1/agora_token.php
 * Body (JSON): { "channel": string, "uid": int, "expire": int (seconds, optional) }
 * Returns: { "status": "success", "token": "007...", "expire": int }
 *
 * Reference implementation:
 *   https://github.com/AgoraIO/Tools/tree/master/DynamicKey/AgoraDynamicKey/php
 * All integers are packed little-endian (V = uint32 LE, v = uint16 LE).
 */

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

header('Content-Type: application/json; charset=utf-8');

// ── Auth ──────────────────────────────────────────────────────────────────────
$viewer = requireUser($pdo);

// ── Parse request body early (also needed below for service_type) ────────────
$input = json_decode(file_get_contents('php://input'), true) ?: [];

// ── Load Agora credentials from video_providers table ────────────────────────
// Calls and live streaming are very often different Agora projects, so this
// must be scoped by service_type -- without it, a table with both a 'call'
// and a 'live' row for 'agora' would return whichever happens to sort first,
// silently generating a token signed with the WRONG project's certificate.
$serviceType = $_GET['service_type'] ?? ($input['service_type'] ?? 'call');
if (!in_array($serviceType, ['call', 'live'], true)) {
    $serviceType = 'call';
}
$row = $pdo->prepare(
    "SELECT app_id, server_secret FROM video_providers WHERE provider_name='agora' AND service_type=? LIMIT 1"
);
$row->execute([$serviceType]);
$row = $row->fetch(PDO::FETCH_ASSOC);

$appId   = trim($row['app_id']       ?? '');
$appCert = trim($row['server_secret'] ?? '');  // "App Certificate" stored in server_secret

if (strlen($appId) !== 32) {
    http_response_code(400);
    echo json_encode([
        'status'  => 'error',
        'message' => 'Agora App ID not configured or invalid (must be 32-char hex). Set it in Admin → Video APIs.',
    ]);
    exit;
}

if (empty($appCert)) {
    // No App Certificate → trial mode: Agora accepts empty token
    echo json_encode(['status' => 'success', 'token' => '', 'mode' => 'trial']);
    exit;
}

// ── Parse request ─────────────────────────────────────────────────────────────
// ($input was already parsed above for service_type)
$channel = trim($input['channel'] ?? $_GET['channel'] ?? '');
$uid     = (int)($input['uid']    ?? $_GET['uid']    ?? 0);
$expire  = (int)($input['expire'] ?? $_GET['expire'] ?? 86400);

if (empty($channel)) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'message' => 'Missing required field: channel']);
    exit;
}

// ── Generate token ────────────────────────────────────────────────────────────
$token = _buildAgoraAccessToken2($appId, $appCert, $channel, $uid, $expire);

if ($token === null) {
    http_response_code(500);
    echo json_encode([
        'status'  => 'error',
        'message' => 'Token generation failed. Verify App ID (32-char hex) and App Certificate are correct.',
    ]);
    exit;
}

echo json_encode([
    'status' => 'success',
    'token'  => $token,
    'expire' => time() + $expire,
]);
exit;

// ─────────────────────────────────────────────────────────────────────────────
//  Agora AccessToken2  —  PHP implementation (all integers little-endian)
//  Reference: https://github.com/AgoraIO/Tools/blob/master/DynamicKey/AgoraDynamicKey/php
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Build an Agora AccessToken2 string.
 *
 * Ported field-for-field from Agora's own reference implementation
 * (AgoraIO/Tools DynamicKey/AgoraDynamicKey/php/src/AccessToken2.php + Util.php)
 * after an earlier hand-rolled version turned out to diverge from it in three
 * ways that each independently break the signature: the App ID must be
 * length-prefixed (packString), not raw hex2bin bytes; the signing key comes
 * from two CHAINED HMACs (cert keyed by issueTs, then that result keyed by
 * salt) rather than one HMAC keyed by the certificate; and expire values are
 * the raw relative duration, not issueTs-plus-duration.
 *
 * @param string $appId      32-char hex App ID
 * @param string $appCert    App Certificate (primary)
 * @param string $channel    Channel name
 * @param int    $uid        User ID (0 = any)
 * @param int    $expireSec  Validity duration in seconds (default 86400 = 24 h)
 */
function _buildAgoraAccessToken2(
    string $appId,
    string $appCert,
    string $channel,
    int    $uid,
    int    $expireSec
): ?string {
    if (strlen($appId) !== 32) return null;

    $issueTs = time();
    $salt    = random_int(1, 0x7FFFFFFF);

    // ── Signing key: two chained HMACs. The packed timestamp is the KEY and
    // the certificate is the DATA, then the packed salt is the KEY over that
    // result. Verified by recomputing the signature of a token minted by the
    // Agora console and matching it byte for byte; the reverse arrangement
    // produces a well-formed token that Agora answers errInvalidToken to.
    // NOTE: hash_hmac()'s argument order is ($algo, $data, $key).
    $step1      = hash_hmac('sha256', $appCert, pack('V', $issueTs), true);
    $signingKey = hash_hmac('sha256', $step1,   pack('V', $salt),    true);

    // ── RTC service payload ───────────────────────────────────────────────────
    // Privileges: 1=JoinChannel, 2=PublishAudio, 3=PublishVideo, 4=PublishDataStream
    // Values are relative durations in seconds (not absolute timestamps).
    $privs = [1 => $expireSec, 2 => $expireSec, 3 => $expireSec, 4 => $expireSec];

    // Field order is fixed by Agora's ServiceRtc::pack(), which is
    //   parent::pack()  ->  packUint16(type) . packMapUint32(privileges)
    //   then             ->  packString(channelName) . packString(uid)
    // so the privileges map sits between the type and the channel. Emitting it
    // last instead makes the service unparseable and Agora answers
    // errInvalidToken even though the App ID and certificate are correct.
    $svcBuf  = pack('v', 1);                        // service type = 1 (RTC), uint16 LE
    $svcBuf .= _agoraPackPrivs($privs);             // privileges map
    $svcBuf .= _agoraPackStr($channel);             // channel name
    // Agora encodes uid 0 ("any user") as an empty string, not "0".
    $svcBuf .= _agoraPackStr($uid === 0 ? '' : (string) $uid);

    // ── Message to sign: packString(appId) + issueTs + expire + salt + services ──
    $signedMsg  = _agoraPackStr($appId);
    $signedMsg .= pack('V', $issueTs);
    $signedMsg .= pack('V', $expireSec);
    $signedMsg .= pack('V', $salt);
    $signedMsg .= pack('v', 1);   // service count = 1, uint16 LE
    $signedMsg .= $svcBuf;

    $sig = hash_hmac('sha256', $signedMsg, $signingKey, true);  // 32 raw bytes

    // ── Assemble final token buffer: packString(signature) + signed message ──
    $buf = _agoraPackStr($sig) . $signedMsg;

    return '007' . base64_encode(gzcompress($buf));
}

/** Pack a UTF-8 string as uint16-LE length prefix + raw bytes. */
function _agoraPackStr(string $s): string
{
    return pack('v', strlen($s)) . $s;
}

/** Pack the privileges map: uint16-LE count, then sorted (key uint16-LE, value uint32-LE) pairs. */
function _agoraPackPrivs(array $privs): string
{
    ksort($privs);  // must be sorted ascending by privilege key
    $buf = pack('v', count($privs));
    foreach ($privs as $k => $v) {
        $buf .= pack('v', (int) $k);   // privilege key,   uint16 LE
        $buf .= pack('V', (int) $v);   // privilege value, uint32 LE (seconds from issue)
    }
    return $buf;
}
