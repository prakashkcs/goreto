<?php
// auth_middleware.php
// Token auth + ban enforcement + (optional) multi-device sessions + (optional) pending-delete lock.

header('Content-Type: application/json; charset=utf-8');

// ---------------------------------------------
// Header / token helpers
// ---------------------------------------------

function getBearerToken(): ?string
{
    $headers = function_exists('getallheaders') ? getallheaders() : [];
    if (!$headers)
        return null;
    if (isset($headers['Authorization']))
        return (string) $headers['Authorization'];
    if (isset($headers['authorization']))
        return (string) $headers['authorization'];
    return null;
}

function normalize_token(?string $authHeader): ?string
{
    if ($authHeader === null)
        return null;
    $token = trim($authHeader);
    if (stripos($token, 'Bearer ') === 0)
        $token = trim(substr($token, 7));
    return $token === '' ? null : $token;
}

// ---------------------------------------------
// DB schema helpers
// ---------------------------------------------

function table_exists(PDO $pdo, string $table): bool
{
    try {
        $st = $pdo->prepare('SHOW TABLES LIKE ?');
        $st->execute([$table]);
        return (bool) $st->fetchColumn();
    } catch (Throwable $e) {
        return false;
    }
}

function user_table_columns(PDO $pdo): array
{
    static $cached = null;
    if (is_array($cached))
        return $cached;

    $cols = [];
    try {
        $st = $pdo->query('SHOW COLUMNS FROM users');
        while ($r = $st->fetch(PDO::FETCH_ASSOC))
            $cols[] = $r['Field'];
    } catch (Throwable $e) {
    }
    $cached = $cols;
    return $cols;
}

function has_col(PDO $pdo, string $col): bool
{
    $cols = user_table_columns($pdo);
    return in_array($col, $cols, true);
}

// ---------------------------------------------
// Block helper (A blocked B OR B blocked A)
// ---------------------------------------------

function is_blocked_between(PDO $pdo, int $a, int $b): bool
{
    if ($a <= 0 || $b <= 0)
        return false;
    if ($a === $b)
        return false;
    if (!table_exists($pdo, 'user_blocks'))
        return false;
    try {
        $st = $pdo->prepare('SELECT 1 FROM user_blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?) LIMIT 1');
        $st->execute([$a, $b, $b, $a]);
        return (bool) $st->fetchColumn();
    } catch (Throwable $e) {
        return false;
    }
}

// ---------------------------------------------
// App-signature enforcement
// ---------------------------------------------

/**
 * Call once per request (before requireUser) when enforce_app_signature is on.
 * Rejects requests missing X-App-Id / X-App-Secret headers that match config.
 * Safe to call when $config is null — silently skips enforcement.
 */
function checkAppSignature(?array $config): void
{
    $enforce = $config['security']['enforce_app_signature'] ?? false;
    if (!$enforce) return;

    $expectedId     = $config['security']['app_id']     ?? '';
    $expectedSecret = $config['security']['app_secret'] ?? '';

    $sentId     = $_SERVER['HTTP_X_APP_ID']     ?? '';
    $sentSecret = $_SERVER['HTTP_X_APP_SECRET'] ?? '';

    if ($expectedId !== '' && $sentId !== $expectedId) {
        http_response_code(403);
        echo json_encode(['status' => 'error', 'message' => 'Forbidden']);
        exit;
    }
    if ($expectedSecret !== '' && !hash_equals($expectedSecret, $sentSecret)) {
        http_response_code(403);
        echo json_encode(['status' => 'error', 'message' => 'Forbidden']);
        exit;
    }
}

// ---------------------------------------------
// Main auth middleware
// ---------------------------------------------

function requireUser(PDO $pdo): array
{
    $auth = getBearerToken();
    if (!$auth) {
        http_response_code(401);
        echo json_encode(['status' => 'error', 'message' => 'Missing Authorization header']);
        exit;
    }

    $token = normalize_token($auth);
    if (!$token) {
        http_response_code(401);
        echo json_encode(['status' => 'error', 'message' => 'Empty token']);
        exit;
    }

    // Reject obviously malformed tokens — prevents injection and saves a DB round-trip.
    // Allows: 8–256 chars, alphanumeric + underscore/hyphen (covers hex tokens, legacy formats, debug tokens).
    if (!preg_match('/^[a-zA-Z0-9_\-]{8,256}$/', $token)) {
        http_response_code(401);
        echo json_encode(['status' => 'error', 'message' => 'Invalid token format']);
        exit;
    }

    // Build SELECT safely (avoid unknown column crash)
    $select = ['u.id', 'u.name', 'u.email', 'u.profile_pic'];

    // Ban fields
    $banEnabled = has_col($pdo, 'is_banned');
    if ($banEnabled) {
        $select[] = 'u.is_banned';
        $select[] = has_col($pdo, 'ban_reason') ? 'u.ban_reason' : "'' AS ban_reason";
        $select[] = has_col($pdo, 'banned_at') ? 'u.banned_at' : 'NULL AS banned_at';
    } else {
        $select[] = '0 AS is_banned';
        $select[] = "'' AS ban_reason";
        $select[] = 'NULL AS banned_at';
    }

    // Device ban fields
    $deviceBanEnabled = has_col($pdo, 'device_ban');
    if ($deviceBanEnabled) {
        $select[] = 'u.device_ban';
        $select[] = has_col($pdo, 'device_ban_reason') ? 'u.device_ban_reason' : "'' AS device_ban_reason";
        $select[] = has_col($pdo, 'device_banned_at') ? 'u.device_banned_at' : 'NULL AS device_banned_at';
    } else {
        $select[] = '0 AS device_ban';
        $select[] = "'' AS device_ban_reason";
        $select[] = 'NULL AS device_banned_at';
    }

    // Pending-delete fields (30 days recover)
    $delEnabled = has_col($pdo, 'delete_requested_at') && has_col($pdo, 'delete_scheduled_at');
    if ($delEnabled) {
        $select[] = 'u.delete_requested_at';
        $select[] = 'u.delete_scheduled_at';
    } else {
        $select[] = 'NULL AS delete_requested_at';
        $select[] = 'NULL AS delete_scheduled_at';
    }

    $user = null;

    // Prefer multi-session token table if present
    if (table_exists($pdo, 'user_auth_tokens')) {
        $sql = 'SELECT ' . implode(', ', $select) . ' FROM user_auth_tokens t JOIN users u ON u.id = t.user_id WHERE t.token = :t AND t.revoked_at IS NULL LIMIT 1';
        $stmt = $pdo->prepare($sql);
        $stmt->execute([':t' => $token]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC) ?: null;

        // update last_used_at (best effort)
        if ($user) {
            try {
                $pdo->prepare('UPDATE user_auth_tokens SET last_used_at = NOW() WHERE token = :t')->execute([':t' => $token]);
            } catch (Throwable $e) {
            }
        }
    }

    // Legacy fallback (users.api_token)
    if (!$user) {
        $sql = 'SELECT ' . implode(', ', $select) . ' FROM users u WHERE u.api_token = :t LIMIT 1';
        $stmt = $pdo->prepare($sql);
        $stmt->execute([':t' => $token]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    }

    if (!$user) {
        http_response_code(401);
        echo json_encode(['status' => 'account_deleted', 'message' => 'Account not found. Please log in again.']);
        exit;
    }

    // Account ban enforcement
    if ($banEnabled && intval($user['is_banned'] ?? 0) === 1) {
        http_response_code(403);
        echo json_encode([
            'status' => 'banned',
            'message' => 'Your account has been suspended.',
            'ban_reason' => $user['ban_reason'] ?? '',
            'banned_at' => $user['banned_at'] ?? ''
        ]);
        exit;
    }

    // Device ban enforcement
    if ($deviceBanEnabled && intval($user['device_ban'] ?? 0) === 1) {
        http_response_code(403);
        echo json_encode([
            'status' => 'device_banned',
            'message' => 'This device has been banned.',
            'ban_reason' => $user['device_ban_reason'] ?? '',
            'banned_at' => $user['device_banned_at'] ?? ''
        ]);
        exit;
    }

    // Pending delete enforcement (recoverable within 30 days)
    try {
        $dr = $user['delete_requested_at'] ?? null;
        $ds = $user['delete_scheduled_at'] ?? null;
        if ($dr && $ds) {
            $now = new DateTime('now');
            $sched = new DateTime((string) $ds);
            if ($sched > $now) {
                http_response_code(403);
                echo json_encode([
                    'status' => 'pending_delete',
                    'message' => 'Account scheduled for deletion.',
                    'delete_scheduled_at' => (string) $ds
                ]);
                exit;
            }
        }
    } catch (Throwable $e) {
    }

    return $user;
}
