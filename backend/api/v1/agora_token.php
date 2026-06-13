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

// ── Load Agora credentials from video_providers table ────────────────────────
$row = $pdo->query(
    "SELECT app_id, server_secret FROM video_providers WHERE provider_name='agora' LIMIT 1"
)->fetch(PDO::FETCH_ASSOC);

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
$input   = json_decode(file_get_contents('php://input'), true) ?: [];
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
    $expire  = $issueTs + $expireSec;  // absolute expiry timestamp
    $salt    = rand(1, 0x7FFFFFFF);

    // ── Signing key: HMAC-SHA256(appCert, LE(issueTs) || LE(salt)) ────────────
    $signingKey = hash_hmac('sha256', pack('VV', $issueTs, $salt), $appCert, true);

    // ── RTC service payload ───────────────────────────────────────────────────
    // Privileges: 1=JoinChannel, 2=PublishAudio, 3=PublishVideo, 4=PublishDataStream
    // Values are the absolute expiry timestamp for each privilege.
    $privs = [1 => $expire, 2 => $expire, 3 => $expire, 4 => $expire];

    $svcBuf  = pack('v', 1);                        // service type = 1 (RTC), uint16 LE
    $svcBuf .= _agoraPackStr($channel);             // channel name
    $svcBuf .= _agoraPackStr((string) $uid);        // uid as string
    $svcBuf .= _agoraPackPrivs($privs);             // privileges map

    // ── Message to sign: full header (no sig) + services ─────────────────────
    $msgHeader  = pack('v', 1);          // version = 1, uint16 LE
    $msgHeader .= hex2bin($appId);       // 16 raw bytes
    $msgHeader .= pack('V', $issueTs);   // uint32 LE
    $msgHeader .= pack('V', $expire);    // uint32 LE
    $msgHeader .= pack('V', $salt);      // uint32 LE

    $msgToSign = $msgHeader . $svcBuf;

    $sig = hash_hmac('sha256', $msgToSign, $signingKey, true);  // 32 raw bytes

    // ── Assemble final token buffer ───────────────────────────────────────────
    // Format: header | sig_len(uint16 LE) | sig(32B) | svc_count(uint16 LE) | svc_data
    $buf  = $msgHeader;
    $buf .= pack('v', strlen($sig)) . $sig;  // length-prefixed signature
    $buf .= pack('v', 1);                    // service count = 1, uint16 LE
    $buf .= $svcBuf;

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
        $buf .= pack('V', (int) $v);   // privilege value, uint32 LE (absolute expiry)
    }
    return $buf;
}
