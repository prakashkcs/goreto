<?php
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

// Bump this when the schema below changes. Migrations then run once per
// version instead of firing ~15 ALTER TABLE statements on every request
// (which made every 2-second chat poll slow).
const GROUP_SCHEMA_VERSION = 3;

function init_group_chat_tables(PDO $pdo): void
{
    $pdo->exec("CREATE TABLE IF NOT EXISTS chat_groups (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        username VARCHAR(100) NULL UNIQUE,
        avatar VARCHAR(500) NULL,
        bio VARCHAR(500) NULL,
        created_by INT NOT NULL,
        join_fee INT DEFAULT 0,
        monthly_fee INT DEFAULT 0,
        is_private TINYINT(1) DEFAULT 0,
        message_delay INT DEFAULT 0,
        views_count INT DEFAULT 0,
        last_active DATETIME DEFAULT CURRENT_TIMESTAMP,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;");

    $pdo->exec("CREATE TABLE IF NOT EXISTS chat_group_views (
        id INT AUTO_INCREMENT PRIMARY KEY,
        group_id INT NOT NULL,
        user_id INT NOT NULL,
        viewed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY unique_view (group_id, user_id)
    ) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;");

    $alters = [
        "ALTER TABLE chat_groups ADD COLUMN join_fee INT DEFAULT 0",
        "ALTER TABLE chat_groups ADD COLUMN monthly_fee INT DEFAULT 0",
        "ALTER TABLE chat_groups ADD COLUMN is_private TINYINT(1) DEFAULT 0",
        "ALTER TABLE chat_groups ADD COLUMN message_delay INT DEFAULT 0",
        "ALTER TABLE chat_groups ADD COLUMN username VARCHAR(100) NULL",
        "ALTER TABLE chat_groups ADD COLUMN bio VARCHAR(500) NULL",
        "ALTER TABLE chat_groups ADD COLUMN views_count INT DEFAULT 0",
        "ALTER TABLE chat_groups ADD COLUMN last_active DATETIME DEFAULT CURRENT_TIMESTAMP",
        "ALTER TABLE chat_groups ADD UNIQUE INDEX idx_username (username)",
        "ALTER TABLE chat_groups ADD COLUMN permissions TEXT NULL DEFAULT NULL",
        "ALTER TABLE chat_groups ADD COLUMN join_approval TINYINT(1) DEFAULT 0",
        "ALTER TABLE chat_groups ADD COLUMN members_can_invite TINYINT(1) DEFAULT 1",
    ];
    foreach ($alters as $sql) {
        try { $pdo->exec($sql); } catch (Exception $e) {}
    }

    $pdo->exec("CREATE TABLE IF NOT EXISTS chat_group_members (
        group_id INT NOT NULL,
        user_id INT NOT NULL,
        role ENUM('member', 'admin') DEFAULT 'member',
        joined_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (group_id, user_id)
    ) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;");

    $pdo->exec("CREATE TABLE IF NOT EXISTS chat_group_messages (
        id INT AUTO_INCREMENT PRIMARY KEY,
        group_id INT NOT NULL,
        sender_id INT NOT NULL,
        message TEXT NULL,
        type ENUM('text', 'image', 'video', 'audio', 'system') DEFAULT 'text',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_group (group_id),
        INDEX idx_created (created_at)
    ) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;");

    $msgAlters = [
        "ALTER TABLE chat_group_messages MODIFY COLUMN type ENUM('text', 'image', 'video', 'audio', 'system') DEFAULT 'text'",
        "ALTER TABLE chat_group_messages ADD COLUMN voice_duration INT DEFAULT 0",
        "ALTER TABLE chat_group_messages ADD COLUMN is_edited TINYINT(1) DEFAULT 0",
        "ALTER TABLE chat_group_messages ADD COLUMN is_deleted TINYINT(1) DEFAULT 0",
        "ALTER TABLE chat_group_messages ADD COLUMN updated_at DATETIME NULL DEFAULT NULL",
        "ALTER TABLE chat_group_messages ADD INDEX idx_group_updated (group_id, updated_at)",
    ];
    foreach ($msgAlters as $sql) {
        try { $pdo->exec($sql); } catch (Exception $e) {}
    }

    $pdo->exec("CREATE TABLE IF NOT EXISTS chat_group_bans (
        group_id INT NOT NULL,
        user_id INT NOT NULL,
        banned_by INT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (group_id, user_id)
    ) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;");

    $pdo->exec("CREATE TABLE IF NOT EXISTS chat_group_invites (
        id INT AUTO_INCREMENT PRIMARY KEY,
        group_id INT NOT NULL,
        inviter_id INT NOT NULL,
        invitee_id INT NOT NULL,
        status ENUM('pending','accepted','declined','cancelled') DEFAULT 'pending',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        responded_at DATETIME NULL,
        UNIQUE KEY uniq_invite (group_id, invitee_id),
        INDEX idx_invitee (invitee_id, status)
    ) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;");

    $pdo->exec("CREATE TABLE IF NOT EXISTS chat_group_join_requests (
        id INT AUTO_INCREMENT PRIMARY KEY,
        group_id INT NOT NULL,
        user_id INT NOT NULL,
        invited_by INT NULL,
        status ENUM('pending','approved','rejected','cancelled') DEFAULT 'pending',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        handled_by INT NULL,
        handled_at DATETIME NULL,
        UNIQUE KEY uniq_request (group_id, user_id),
        INDEX idx_group_status (group_id, status)
    ) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;");

    $pdo->exec("CREATE TABLE IF NOT EXISTS chat_group_message_hidden (
        message_id INT NOT NULL,
        user_id INT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (message_id, user_id)
    ) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;");

    // Drop memberships whose user account no longer exists. These inflated
    // the member count shown outside the group (e.g. "3 members" for 2 people).
    try {
        $pdo->exec("DELETE cm FROM chat_group_members cm LEFT JOIN users u ON u.id = cm.user_id WHERE u.id IS NULL");
    } catch (Exception $e) {}
}

function ensure_group_schema(PDO $pdo): void
{
    $marker = rtrim(sys_get_temp_dir(), '/\\') . '/goreto_group_chat_schema_v' . GROUP_SCHEMA_VERSION;
    if (is_file($marker)) return;
    init_group_chat_tables($pdo);
    @touch($marker);
}

function out_json(int $code, array $payload): void
{
    http_response_code($code);
    echo json_encode($payload);
    exit;
}

function to_bool($v): bool
{
    if (is_bool($v)) return $v;
    if (is_int($v)) return $v !== 0;
    return filter_var((string) $v, FILTER_VALIDATE_BOOLEAN);
}

// Member count that ignores memberships of deleted accounts.
const MEMBER_COUNT_SQL = "(SELECT COUNT(*) FROM chat_group_members cm JOIN users cu ON cu.id = cm.user_id WHERE cm.group_id = g.id)";

function member_role(PDO $pdo, int $groupId, int $userId): ?string
{
    $st = $pdo->prepare("SELECT role FROM chat_group_members WHERE group_id = ? AND user_id = ?");
    $st->execute([$groupId, $userId]);
    $r = $st->fetchColumn();
    return $r === false ? null : (string) $r;
}

function requireGroupAdmin(PDO $pdo, int $groupId, int $userId): void
{
    if (member_role($pdo, $groupId, $userId) !== 'admin') {
        out_json(403, ['status' => 'error', 'message' => 'Admin privileges required']);
    }
}

function requireGroupMember(PDO $pdo, int $groupId, int $userId): string
{
    $role = member_role($pdo, $groupId, $userId);
    if ($role === null) {
        out_json(403, ['status' => 'error', 'message' => 'Not a group member']);
    }
    return $role;
}

function site_root(array $config): string
{
    $base = rtrim($config['base_url'] ?? 'https://goreto.org/ekloadmin/api/v1/', '/');
    return preg_replace('~/api/v1$~', '', $base) . '/';
}

function user_avatar_url(?string $pic, array $config): ?string
{
    $pic = trim((string) $pic);
    if ($pic === '') return null;
    if (preg_match('~^https?://~i', $pic)) return $pic;
    return site_root($config) . ltrim($pic, '/');
}

function normalize_group_username(string $u): string
{
    return strtolower(trim(ltrim(trim($u), '@')));
}

function valid_group_username(string $u): bool
{
    return (bool) preg_match('/^[a-z0-9](?:[a-z0-9_.]{1,28})[a-z0-9]$/', $u);
}

function slugify_group_name(string $name): string
{
    $s = strtolower(trim($name));
    if (function_exists('iconv')) {
        $t = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $s);
        if ($t !== false) $s = strtolower($t);
    }
    $s = preg_replace('/[\s\-]+/', '_', $s);
    $s = preg_replace('/[^a-z0-9_.]/', '', $s);
    $s = preg_replace('/[_.]{2,}/', '_', $s);
    $s = trim($s, '_.');
    if (strlen($s) > 24) $s = rtrim(substr($s, 0, 24), '_.');
    if (strlen($s) < 3) $s = 'group_' . $s;
    return trim($s, '_.');
}

function group_username_taken(PDO $pdo, string $u, int $excludeId = 0): bool
{
    $st = $pdo->prepare("SELECT id FROM chat_groups WHERE username = ? AND id != ? LIMIT 1");
    $st->execute([$u, $excludeId]);
    return (bool) $st->fetchColumn();
}

function suggest_free_username(PDO $pdo, string $base, int $excludeId = 0): string
{
    $base = slugify_group_name($base);
    if (!group_username_taken($pdo, $base, $excludeId)) return $base;
    for ($i = 0; $i < 12; $i++) {
        $cand = substr($base, 0, 24) . '_' . random_int(10, $i < 6 ? 999 : 99999);
        if (!group_username_taken($pdo, $cand, $excludeId)) return $cand;
    }
    return substr($base, 0, 20) . '_' . bin2hex(random_bytes(3));
}

/**
 * Saves an uploaded group avatar as a centre-cropped 512px JPEG so it loads
 * fast everywhere it is shown. Falls back to the original file without GD.
 * Returns the stored path relative to api/v1 (e.g. /uploads/groups/x.jpg).
 */
function save_group_avatar(array $file): ?string
{
    if (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) return null;
    if (!@getimagesize($file['tmp_name'])) return null;

    $dir = __DIR__ . '/uploads/groups';
    if (!is_dir($dir)) @mkdir($dir, 0755, true);

    if (function_exists('imagecreatefromstring')) {
        $src = @imagecreatefromstring((string) file_get_contents($file['tmp_name']));
        if ($src) {
            $w = imagesx($src);
            $h = imagesy($src);
            $side = min($w, $h);
            $size = min(512, $side);
            $dst = imagecreatetruecolor($size, $size);
            imagefill($dst, 0, 0, imagecolorallocate($dst, 26, 26, 26));
            imagecopyresampled($dst, $src, 0, 0, (int) (($w - $side) / 2), (int) (($h - $side) / 2), $size, $size, $side, $side);
            $name = uniqid('grp_') . '.jpg';
            $ok = imagejpeg($dst, $dir . '/' . $name, 85);
            imagedestroy($src);
            imagedestroy($dst);
            if ($ok) return '/uploads/groups/' . $name;
        }
    }

    $ext = strtolower(pathinfo($file['name'] ?? '', PATHINFO_EXTENSION));
    if (!in_array($ext, ['jpg', 'jpeg', 'png', 'webp', 'gif'], true)) $ext = 'jpg';
    $name = uniqid('grp_') . '.' . $ext;
    return move_uploaded_file($file['tmp_name'], $dir . '/' . $name) ? '/uploads/groups/' . $name : null;
}

function default_permissions(): array
{
    return ['can_send_text' => 1, 'can_send_media' => 1, 'can_send_voice' => 1, 'can_send_stickers' => 1];
}

function fetch_group(PDO $pdo, int $groupId, int $userId): ?array
{
    $st = $pdo->prepare("SELECT g.*, " . MEMBER_COUNT_SQL . " AS member_count,
        (SELECT role FROM chat_group_members WHERE group_id = g.id AND user_id = ?) AS my_role,
        (SELECT COUNT(*) FROM chat_group_join_requests r WHERE r.group_id = g.id AND r.user_id = ? AND r.status = 'pending') AS request_pending,
        (SELECT COUNT(*) FROM chat_group_join_requests r WHERE r.group_id = g.id AND r.status = 'pending') AS pending_requests_all
        FROM chat_groups g WHERE g.id = ?");
    $st->execute([$userId, $userId, $groupId]);
    $g = $st->fetch(PDO::FETCH_ASSOC);
    if (!$g) return null;
    $g['is_member'] = $g['my_role'] !== null ? 1 : 0;
    $g['pending_requests'] = $g['my_role'] === 'admin' ? (int) $g['pending_requests_all'] : 0;
    unset($g['pending_requests_all']);
    $g['permissions'] = !empty($g['permissions']) ? (json_decode($g['permissions'], true) ?: default_permissions()) : default_permissions();
    return $g;
}

function post_system_message(PDO $pdo, int $groupId, int $userId, string $text): void
{
    $pdo->prepare("INSERT INTO chat_group_messages (group_id, sender_id, message, type) VALUES (?, ?, ?, 'system')")
        ->execute([$groupId, $userId, $text]);
}

function user_display_name(PDO $pdo, int $uid): string
{
    $st = $pdo->prepare("SELECT name, username FROM users WHERE id = ?");
    $st->execute([$uid]);
    $r = $st->fetch(PDO::FETCH_ASSOC);
    if (!$r) return 'Someone';
    return $r['name'] ?: ($r['username'] ?: 'Someone');
}

/** Adds a member and closes any open invite / request for them. */
function add_group_member(PDO $pdo, int $groupId, int $uid, string $systemText): bool
{
    $st = $pdo->prepare("INSERT IGNORE INTO chat_group_members (group_id, user_id, role) VALUES (?, ?, 'member')");
    $st->execute([$groupId, $uid]);
    $added = $st->rowCount() > 0;
    if ($added) post_system_message($pdo, $groupId, $uid, $systemText);
    $pdo->prepare("UPDATE chat_group_invites SET status = 'accepted', responded_at = NOW() WHERE group_id = ? AND invitee_id = ? AND status = 'pending'")
        ->execute([$groupId, $uid]);
    $pdo->prepare("UPDATE chat_group_join_requests SET status = 'approved', handled_at = NOW() WHERE group_id = ? AND user_id = ? AND status = 'pending'")
        ->execute([$groupId, $uid]);
    return $added;
}

/** Debits the join fee. Returns an error message or null on success. */
function charge_join_fee(PDO $pdo, int $groupId, int $uid, int $fee): ?string
{
    if ($fee <= 0) return null;
    $pdo->beginTransaction();
    try {
        $stBal = $pdo->prepare("SELECT balance_coins FROM user_wallets WHERE user_id = ? FOR UPDATE");
        $stBal->execute([$uid]);
        $bal = (int) $stBal->fetchColumn();
        if ($bal < $fee) {
            $pdo->rollBack();
            return "Insufficient coins (Need $fee)";
        }
        $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins - ? WHERE user_id = ?")->execute([$fee, $uid]);
        $pdo->prepare("INSERT INTO wallet_transactions (user_id,type,direction,coins,status,note) VALUES (?,'group_join','debit',?,'completed',?)")
            ->execute([$uid, $fee, "Joined premium group #$groupId"]);
        $pdo->commit();
        return null;
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $e;
    }
}

function notify_user(PDO $pdo, int $to, int $from, string $type, string $title, string $body, int $groupId): void
{
    try {
        require_once __DIR__ . '/notification_helper.php';
        send_app_notification($pdo, $to, $from, $type, $title, $body, $groupId);
    } catch (Throwable $e) {
        error_log('group notify failed: ' . $e->getMessage());
    }
}

function notify_group_admins(PDO $pdo, int $groupId, int $from, string $type, string $title, string $body): void
{
    $st = $pdo->prepare("SELECT user_id FROM chat_group_members WHERE group_id = ? AND role = 'admin' AND user_id != ?");
    $st->execute([$groupId, $from]);
    foreach ($st->fetchAll(PDO::FETCH_COLUMN) as $adminId) {
        notify_user($pdo, (int) $adminId, $from, $type, $title, $body, $groupId);
    }
}

function blocked_either_way(PDO $pdo, int $a, int $b): bool
{
    return function_exists('is_blocked_between') ? is_blocked_between($pdo, $a, $b) : false;
}

/** Creates (or re-opens) a join request and pings the admins. */
function open_join_request(PDO $pdo, array $group, int $uid, ?int $invitedBy, string $userName): void
{
    $pdo->prepare("INSERT INTO chat_group_join_requests (group_id, user_id, invited_by, status, created_at)
        VALUES (?, ?, ?, 'pending', NOW())
        ON DUPLICATE KEY UPDATE status = 'pending', invited_by = VALUES(invited_by), created_at = NOW(), handled_by = NULL, handled_at = NULL")
        ->execute([(int) $group['id'], $uid, $invitedBy]);
    notify_group_admins($pdo, (int) $group['id'], $uid, 'group_join_request',
        'New join request', "$userName wants to join " . $group['name']);
}

function annotate_invitee_status(PDO $pdo, int $groupId, array $ids): array
{
    $status = [];
    if (!$ids) return $status;
    $in = implode(',', array_map('intval', $ids));
    foreach ($pdo->query("SELECT user_id FROM chat_group_members WHERE group_id = " . (int) $groupId . " AND user_id IN ($in)") as $r) {
        $status[(int) $r['user_id']] = 'member';
    }
    foreach ($pdo->query("SELECT invitee_id FROM chat_group_invites WHERE group_id = " . (int) $groupId . " AND status = 'pending' AND invitee_id IN ($in)") as $r) {
        $status[(int) $r['invitee_id']] = $status[(int) $r['invitee_id']] ?? 'invited';
    }
    foreach ($pdo->query("SELECT user_id FROM chat_group_join_requests WHERE group_id = " . (int) $groupId . " AND status = 'pending' AND user_id IN ($in)") as $r) {
        $status[(int) $r['user_id']] = $status[(int) $r['user_id']] ?? 'requested';
    }
    foreach ($pdo->query("SELECT user_id FROM chat_group_bans WHERE group_id = " . (int) $groupId . " AND user_id IN ($in)") as $r) {
        $status[(int) $r['user_id']] = 'banned';
    }
    return $status;
}

function upload_error_message(int $code): string
{
    $max = ini_get('upload_max_filesize');
    switch ($code) {
        case UPLOAD_ERR_INI_SIZE:
        case UPLOAD_ERR_FORM_SIZE:
            return "File is too large. Maximum size is $max.";
        case UPLOAD_ERR_PARTIAL:
            return 'Upload was interrupted. Please try again.';
        case UPLOAD_ERR_NO_FILE:
            return 'No file was received.';
        default:
            return 'Upload failed on the server (code ' . $code . ').';
    }
}

try {
    $cfgFile = __DIR__ . '/../config/config.php';
    $config = file_exists($cfgFile) ? (require $cfgFile) : [];
    if (empty($config['base_url'])) {
        $proto = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
        $config['base_url'] = $proto . '://' . ($_SERVER['HTTP_HOST'] ?? 'goreto.org') . '/ekloadmin/api/v1/';
    }

    // A body larger than post_max_size arrives with $_POST/$_FILES empty, which
    // previously surfaced as a confusing "Not a group member" error on video upload.
    $contentLength = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
    if ($_SERVER['REQUEST_METHOD'] === 'POST' && empty($_POST) && empty($_FILES) && $contentLength > 0
        && stripos($_SERVER['CONTENT_TYPE'] ?? '', 'multipart/form-data') !== false) {
        out_json(413, ['status' => 'error', 'message' => 'File is too large. Maximum upload size is ' . ini_get('post_max_size') . '.']);
    }

    $user = requireUser($pdo);
    $userId = (int) $user['id'];
    $userName = $user['name'] ?: 'Someone';

    ensure_group_schema($pdo);

    $action = $_GET['action'] ?? $_POST['action'] ?? '';
    $input = json_decode(file_get_contents('php://input'), true) ?? [];
    if (!is_array($input)) $input = [];
    $input = array_merge($_GET, $input, $_POST);

    if ($action === 'create') {
        $name = trim($input['name'] ?? '');
        if ($name === '') {
            out_json(400, ['status' => 'error', 'message' => 'Group name required']);
        }
        if (mb_strlen($name) > 60) {
            out_json(400, ['status' => 'error', 'message' => 'Group name is too long (max 60 characters)']);
        }

        $countStmt = $pdo->prepare("SELECT COUNT(*) FROM chat_groups WHERE created_by = ?");
        $countStmt->execute([$userId]);
        if ((int) $countStmt->fetchColumn() >= 10) {
            out_json(400, ['status' => 'error', 'message' => 'Maximum 10 groups allowed per user']);
        }

        $username = normalize_group_username($input['username'] ?? '');
        if ($username === '') {
            $username = suggest_free_username($pdo, $name);
        }
        if (!valid_group_username($username)) {
            out_json(400, ['status' => 'error', 'message' => 'Username must be 3-30 characters: letters, numbers, _ or .']);
        }
        if (group_username_taken($pdo, $username)) {
            out_json(400, ['status' => 'error', 'message' => 'Username already taken', 'suggestion' => suggest_free_username($pdo, $username)]);
        }

        $bio = trim($input['bio'] ?? '');
        $joinFee = max(0, (int) ($input['join_fee'] ?? 0));
        $monthlyFee = max(0, (int) ($input['monthly_fee'] ?? 0));
        $isPrivate = to_bool($input['is_private'] ?? 0) ? 1 : 0;
        $joinApproval = to_bool($input['join_approval'] ?? 0) ? 1 : 0;

        $avatarPath = isset($_FILES['avatar']) ? save_group_avatar($_FILES['avatar']) : null;

        $pdo->beginTransaction();
        $st = $pdo->prepare("INSERT INTO chat_groups (name, username, bio, created_by, join_fee, monthly_fee, is_private, join_approval, avatar) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
        $st->execute([$name, $username, $bio ?: null, $userId, $joinFee, $monthlyFee, $isPrivate, $joinApproval, $avatarPath]);
        $groupId = (int) $pdo->lastInsertId();
        $pdo->prepare("INSERT INTO chat_group_members (group_id, user_id, role) VALUES (?, ?, 'admin')")->execute([$groupId, $userId]);
        post_system_message($pdo, $groupId, $userId, "Group created by " . $userName);
        $pdo->commit();

        out_json(200, ['status' => 'success', 'group_id' => $groupId, 'message' => 'Group created', 'group' => fetch_group($pdo, $groupId, $userId)]);
    } elseif ($action === 'check_username') {
        $groupId = (int) ($input['group_id'] ?? 0);
        $raw = (string) ($input['username'] ?? '');
        $username = normalize_group_username($raw);
        if ($username === '' && !empty($input['name'])) {
            $s = suggest_free_username($pdo, (string) $input['name'], $groupId);
            out_json(200, ['status' => 'success', 'username' => $s, 'valid' => true, 'available' => true, 'suggestion' => $s]);
        }
        if (!valid_group_username($username)) {
            out_json(200, ['status' => 'success', 'username' => $username, 'valid' => false, 'available' => false,
                'message' => '3-30 characters: letters, numbers, _ or . (cannot start or end with _ or .)']);
        }
        $taken = group_username_taken($pdo, $username, $groupId);
        out_json(200, ['status' => 'success', 'username' => $username, 'valid' => true, 'available' => !$taken,
            'message' => $taken ? 'This username is taken' : 'Username is available',
            'suggestion' => $taken ? suggest_free_username($pdo, $username, $groupId) : $username]);
    } elseif ($action === 'join') {
        $groupId = (int) ($input['group_id'] ?? 0);
        if ($groupId <= 0) out_json(400, ['status' => 'error', 'message' => 'Invalid group']);

        $stBan = $pdo->prepare("SELECT 1 FROM chat_group_bans WHERE group_id = ? AND user_id = ?");
        $stBan->execute([$groupId, $userId]);
        if ($stBan->fetchColumn()) out_json(403, ['status' => 'error', 'message' => 'You are banned from this group']);

        $group = fetch_group($pdo, $groupId, $userId);
        if (!$group) out_json(404, ['status' => 'error', 'message' => 'Group not found']);
        if ($group['my_role'] !== null) out_json(200, ['status' => 'success', 'state' => 'joined']);

        // A pending invite counts as acceptance.
        $stInv = $pdo->prepare("SELECT id, inviter_id FROM chat_group_invites WHERE group_id = ? AND invitee_id = ? AND status = 'pending'");
        $stInv->execute([$groupId, $userId]);
        $invite = $stInv->fetch(PDO::FETCH_ASSOC);
        $invitedByAdmin = $invite && member_role($pdo, $groupId, (int) $invite['inviter_id']) === 'admin';

        $needsApproval = !$invitedByAdmin && ((int) $group['is_private'] === 1 || (int) $group['join_approval'] === 1);
        if ($needsApproval && !($invite && (int) $group['join_approval'] === 0)) {
            open_join_request($pdo, $group, $userId, $invite ? (int) $invite['inviter_id'] : null, $userName);
            out_json(200, ['status' => 'success', 'state' => 'requested', 'message' => 'Request sent to the group admins']);
        }

        if (!$invitedByAdmin) {
            $err = charge_join_fee($pdo, $groupId, $userId, (int) $group['join_fee']);
            if ($err) out_json(400, ['status' => 'error', 'message' => $err]);
        }
        add_group_member($pdo, $groupId, $userId, $userName . " joined the group");
        out_json(200, ['status' => 'success', 'state' => 'joined']);
    } elseif ($action === 'cancel_request') {
        $groupId = (int) ($input['group_id'] ?? 0);
        $pdo->prepare("UPDATE chat_group_join_requests SET status = 'cancelled' WHERE group_id = ? AND user_id = ? AND status = 'pending'")
            ->execute([$groupId, $userId]);
        out_json(200, ['status' => 'success']);
    } elseif ($action === 'leave') {
        $groupId = (int) ($input['group_id'] ?? 0);
        $wasAdmin = member_role($pdo, $groupId, $userId) === 'admin';
        $st = $pdo->prepare("DELETE FROM chat_group_members WHERE group_id = ? AND user_id = ?");
        $st->execute([$groupId, $userId]);

        if ($st->rowCount() > 0) {
            post_system_message($pdo, $groupId, $userId, $userName . " left the group");
            // Never leave a group without an admin: promote the longest-standing member.
            if ($wasAdmin) {
                $stA = $pdo->prepare("SELECT COUNT(*) FROM chat_group_members WHERE group_id = ? AND role = 'admin'");
                $stA->execute([$groupId]);
                if ((int) $stA->fetchColumn() === 0) {
                    $pdo->prepare("UPDATE chat_group_members SET role = 'admin' WHERE group_id = ? ORDER BY joined_at ASC LIMIT 1")
                        ->execute([$groupId]);
                }
            }
        }
        out_json(200, ['status' => 'success']);
    } elseif ($action === 'list_all' || $action === 'search_groups') {
        $search = trim($input['search'] ?? '');
        $where = "g.id NOT IN (SELECT group_id FROM chat_group_bans WHERE user_id = ?) AND g.is_private = 0";
        $params = [$userId, $userId, $userId];
        if ($search !== '') {
            $like = '%' . addcslashes($search, '%_') . '%';
            $where .= " AND (g.name LIKE ? OR g.username LIKE ? OR g.bio LIKE ?)";
            array_push($params, $like, $like, $like);
        } elseif ($action === 'search_groups') {
            out_json(400, ['status' => 'error', 'message' => 'Search term required']);
        }
        $stmt = $pdo->prepare("SELECT g.id, g.name, g.avatar, g.username, g.bio, g.join_fee, g.monthly_fee, g.is_private, g.join_approval,
            COALESCE(g.created_by,0) AS created_by, g.views_count, g.last_active,
            " . MEMBER_COUNT_SQL . " AS member_count,
            (SELECT COUNT(*) FROM chat_group_members WHERE group_id = g.id AND user_id = ?) AS is_member,
            (SELECT COUNT(*) FROM chat_group_join_requests r WHERE r.group_id = g.id AND r.user_id = ? AND r.status = 'pending') AS request_pending
            FROM chat_groups g
            WHERE $where
            ORDER BY g.last_active DESC, g.views_count DESC, g.created_at DESC LIMIT 100");
        // Param order: is_member, request_pending, ban filter, [likes]
        $stmt->execute($params);
        out_json(200, ['status' => 'success', 'groups' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
    } elseif ($action === 'my_groups') {
        $stmt = $pdo->prepare("
            SELECT g.id, g.name, g.avatar, g.username, g.bio, g.join_fee, g.monthly_fee, g.is_private, g.join_approval, g.members_can_invite,
            g.message_delay, g.permissions, COALESCE(g.created_by,0) AS created_by, g.views_count,
            m.role AS my_role,
            " . MEMBER_COUNT_SQL . " AS member_count,
            1 AS is_member,
            CASE WHEN m.role = 'admin' THEN (SELECT COUNT(*) FROM chat_group_join_requests r WHERE r.group_id = g.id AND r.status = 'pending') ELSE 0 END AS pending_requests,
            (SELECT CASE WHEN is_deleted = 1 THEN 'This message was unsent' ELSE message END FROM chat_group_messages WHERE group_id = g.id ORDER BY id DESC LIMIT 1) AS last_message,
            (SELECT CASE WHEN is_deleted = 1 THEN 'text' ELSE type END FROM chat_group_messages WHERE group_id = g.id ORDER BY id DESC LIMIT 1) AS last_message_type,
            (SELECT sender_id  FROM chat_group_messages WHERE group_id = g.id ORDER BY id DESC LIMIT 1) AS last_message_sender_id,
            (SELECT u.name FROM chat_group_messages cgm JOIN users u ON u.id = cgm.sender_id WHERE cgm.group_id = g.id ORDER BY cgm.id DESC LIMIT 1) AS last_message_sender,
            (SELECT created_at FROM chat_group_messages WHERE group_id = g.id ORDER BY id DESC LIMIT 1) AS last_message_time
            FROM chat_groups g
            JOIN chat_group_members m ON g.id = m.group_id
            WHERE m.user_id = ?
            ORDER BY last_message_time DESC
        ");
        $stmt->execute([$userId]);
        $groups = $stmt->fetchAll(PDO::FETCH_ASSOC);
        foreach ($groups as &$g) {
            $g['permissions'] = $g['permissions'] ? (json_decode($g['permissions'], true) ?: default_permissions()) : default_permissions();
        }
        unset($g);

        $stInv = $pdo->prepare("SELECT COUNT(*) FROM chat_group_invites WHERE invitee_id = ? AND status = 'pending'");
        $stInv->execute([$userId]);
        out_json(200, ['status' => 'success', 'groups' => $groups, 'pending_invites' => (int) $stInv->fetchColumn()]);
    } elseif ($action === 'send') {
        $groupId = (int) ($input['group_id'] ?? 0);
        $message = trim($input['message'] ?? '');
        $type = $input['type'] ?? 'text';
        if (!in_array($type, ['text', 'image', 'video', 'audio'], true)) $type = 'text';

        requireGroupMember($pdo, $groupId, $userId);
        if ($message === '' && $type === 'text') {
            out_json(400, ['status' => 'error', 'message' => 'Empty message']);
        }

        $pdo->prepare("INSERT INTO chat_group_messages (group_id, sender_id, message, type) VALUES (?, ?, ?, ?)")
            ->execute([$groupId, $userId, $message, $type]);
        $msgId = $pdo->lastInsertId();
        $pdo->prepare("UPDATE chat_groups SET last_active = NOW() WHERE id = ?")->execute([$groupId]);
        out_json(200, ['status' => 'success', 'message_id' => $msgId, 'created_at' => gmdate('Y-m-d H:i:s')]);
    } elseif ($action === 'sync') {
        $groupId = (int) ($input['group_id'] ?? 0);
        $lastId = (int) ($input['last_id'] ?? 0);
        $since = trim((string) ($input['since'] ?? ''));

        requireGroupMember($pdo, $groupId, $userId);
        $serverTime = (string) $pdo->query("SELECT NOW()")->fetchColumn();

        $select = "SELECT m.id, m.sender_id, CASE WHEN m.is_deleted = 1 THEN '' ELSE m.message END AS message, m.type,
                   m.voice_duration, m.created_at, m.is_edited, m.is_deleted,
                   u.name AS sender_name, u.username AS sender_username, u.profile_pic AS sender_avatar
            FROM chat_group_messages m
            LEFT JOIN users u ON m.sender_id = u.id
            WHERE m.group_id = ? AND m.id > ?
              AND NOT EXISTS (SELECT 1 FROM chat_group_message_hidden h WHERE h.message_id = m.id AND h.user_id = ?)";
        if ($lastId === 0) {
            $st = $pdo->prepare("$select ORDER BY m.id DESC LIMIT 60");
            $st->execute([$groupId, $lastId, $userId]);
            $messages = array_reverse($st->fetchAll(PDO::FETCH_ASSOC));
        } else {
            $st = $pdo->prepare("$select ORDER BY m.id ASC LIMIT 200");
            $st->execute([$groupId, $lastId, $userId]);
            $messages = $st->fetchAll(PDO::FETCH_ASSOC);
        }

        // Edits / unsends of messages the client already has.
        $changes = [];
        if ($lastId > 0 && $since !== '') {
            $stC = $pdo->prepare("SELECT id, CASE WHEN is_deleted = 1 THEN '' ELSE message END AS message, is_edited, is_deleted
                FROM chat_group_messages
                WHERE group_id = ? AND id <= ? AND updated_at IS NOT NULL AND updated_at >= DATE_SUB(?, INTERVAL 3 SECOND)");
            $stC->execute([$groupId, $lastId, $since]);
            $changes = $stC->fetchAll(PDO::FETCH_ASSOC);
        }

        out_json(200, ['status' => 'success', 'messages' => $messages, 'changes' => $changes, 'server_time' => $serverTime]);
    } elseif ($action === 'edit_message') {
        $messageId = (int) ($input['message_id'] ?? 0);
        $text = trim((string) ($input['message'] ?? ''));
        if ($text === '') out_json(400, ['status' => 'error', 'message' => 'Message cannot be empty']);

        $st = $pdo->prepare("SELECT group_id, sender_id, type, is_deleted FROM chat_group_messages WHERE id = ?");
        $st->execute([$messageId]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row) out_json(404, ['status' => 'error', 'message' => 'Message not found']);
        if ((int) $row['sender_id'] !== $userId) out_json(403, ['status' => 'error', 'message' => 'You can only edit your own messages']);
        if ($row['type'] !== 'text') out_json(400, ['status' => 'error', 'message' => 'Only text messages can be edited']);
        if ((int) $row['is_deleted'] === 1) out_json(400, ['status' => 'error', 'message' => 'Message was unsent']);
        requireGroupMember($pdo, (int) $row['group_id'], $userId);

        $pdo->prepare("UPDATE chat_group_messages SET message = ?, is_edited = 1, updated_at = NOW() WHERE id = ?")->execute([$text, $messageId]);
        out_json(200, ['status' => 'success']);
    } elseif ($action === 'delete_message') {
        $messageId = (int) ($input['message_id'] ?? 0);
        $scope = ($input['scope'] ?? 'me') === 'everyone' ? 'everyone' : 'me';

        $st = $pdo->prepare("SELECT group_id, sender_id, type, message FROM chat_group_messages WHERE id = ?");
        $st->execute([$messageId]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row) out_json(404, ['status' => 'error', 'message' => 'Message not found']);
        $role = requireGroupMember($pdo, (int) $row['group_id'], $userId);

        if ($scope === 'me') {
            $pdo->prepare("INSERT IGNORE INTO chat_group_message_hidden (message_id, user_id) VALUES (?, ?)")->execute([$messageId, $userId]);
            out_json(200, ['status' => 'success']);
        }

        $isSender = (int) $row['sender_id'] === $userId;
        if (!$isSender && $role !== 'admin') out_json(403, ['status' => 'error', 'message' => 'Only the sender or an admin can unsend for everyone']);
        if ($row['type'] === 'system' && $role !== 'admin') out_json(403, ['status' => 'error', 'message' => 'Not allowed']);

        $pdo->prepare("UPDATE chat_group_messages SET is_deleted = 1, message = '', updated_at = NOW() WHERE id = ?")->execute([$messageId]);
        $path = (string) $row['message'];
        if (in_array($row['type'], ['image', 'video', 'audio'], true) && strpos($path, '/uploads/chat/') === 0) {
            @unlink(__DIR__ . '/uploads/chat/' . basename($path));
        }
        out_json(200, ['status' => 'success']);
    } elseif ($action === 'update_settings') {
        $groupId = (int) ($input['group_id'] ?? 0);
        requireGroupAdmin($pdo, $groupId, $userId);

        $updates = [];
        $params = [];

        if (array_key_exists('name', $input) && trim((string) $input['name']) !== '') {
            $name = trim((string) $input['name']);
            if (mb_strlen($name) > 60) out_json(400, ['status' => 'error', 'message' => 'Group name is too long (max 60 characters)']);
            $updates[] = "name = ?";
            $params[] = $name;
        }
        if (array_key_exists('username', $input) && trim((string) $input['username']) !== '') {
            $username = normalize_group_username((string) $input['username']);
            if (!valid_group_username($username)) {
                out_json(400, ['status' => 'error', 'message' => 'Username must be 3-30 characters: letters, numbers, _ or .']);
            }
            if (group_username_taken($pdo, $username, $groupId)) {
                out_json(400, ['status' => 'error', 'message' => 'Username already taken', 'suggestion' => suggest_free_username($pdo, $username, $groupId)]);
            }
            $updates[] = "username = ?";
            $params[] = $username;
        }
        if (array_key_exists('bio', $input)) {
            $bio = trim((string) ($input['bio'] ?? ''));
            if (mb_strlen($bio) > 300) out_json(400, ['status' => 'error', 'message' => 'Description is too long (max 300 characters)']);
            $updates[] = "bio = ?";
            $params[] = $bio === '' ? null : $bio;
        }
        foreach (['join_fee', 'monthly_fee'] as $k) {
            if (array_key_exists($k, $input)) {
                $updates[] = "$k = ?";
                $params[] = max(0, (int) $input[$k]);
            }
        }
        foreach (['is_private', 'join_approval', 'members_can_invite'] as $k) {
            if (array_key_exists($k, $input)) {
                $updates[] = "$k = ?";
                $params[] = to_bool($input[$k]) ? 1 : 0;
            }
        }
        if (array_key_exists('message_delay', $input)) {
            $updates[] = "message_delay = ?";
            $params[] = max(0, (int) $input['message_delay']);
        }
        if (array_key_exists('permissions', $input)) {
            $perms = $input['permissions'];
            if (is_string($perms)) $perms = json_decode($perms, true) ?: [];
            $clean = [];
            foreach (array_keys(default_permissions()) as $k) {
                $clean[$k] = isset($perms[$k]) ? (to_bool($perms[$k]) ? 1 : 0) : 1;
            }
            $updates[] = "permissions = ?";
            $params[] = json_encode($clean);
        }

        if (isset($_FILES['avatar'])) {
            if ($_FILES['avatar']['error'] !== UPLOAD_ERR_OK) {
                out_json(400, ['status' => 'error', 'message' => upload_error_message((int) $_FILES['avatar']['error'])]);
            }
            $saved = save_group_avatar($_FILES['avatar']);
            if (!$saved) out_json(400, ['status' => 'error', 'message' => 'Could not process that image']);
            $updates[] = "avatar = ?";
            $params[] = $saved;
        }

        if (count($updates) > 0) {
            $params[] = $groupId;
            $pdo->prepare("UPDATE chat_groups SET " . implode(', ', $updates) . " WHERE id = ?")->execute($params);
        }
        out_json(200, ['status' => 'success', 'group' => fetch_group($pdo, $groupId, $userId)]);
    } elseif ($action === 'kick' || $action === 'ban') {
        $groupId = (int) ($input['group_id'] ?? 0);
        $targetId = (int) ($input['target_id'] ?? 0);
        requireGroupAdmin($pdo, $groupId, $userId);

        $stOwner = $pdo->prepare("SELECT created_by FROM chat_groups WHERE id = ?");
        $stOwner->execute([$groupId]);
        $ownerId = (int) $stOwner->fetchColumn();
        if ($targetId === $ownerId) out_json(403, ['status' => 'error', 'message' => 'The group owner cannot be removed']);
        if ($targetId === $userId) out_json(400, ['status' => 'error', 'message' => 'Use "Leave group" instead']);
        if (member_role($pdo, $groupId, $targetId) === 'admin' && $userId !== $ownerId) {
            out_json(403, ['status' => 'error', 'message' => 'Only the owner can remove another admin']);
        }

        $st = $pdo->prepare("DELETE FROM chat_group_members WHERE group_id = ? AND user_id = ?");
        $st->execute([$groupId, $targetId]);
        if ($action === 'ban') {
            $pdo->prepare("INSERT IGNORE INTO chat_group_bans (group_id, user_id, banned_by) VALUES (?, ?, ?)")->execute([$groupId, $targetId, $userId]);
        }
        if ($st->rowCount() > 0) {
            post_system_message($pdo, $groupId, $userId, user_display_name($pdo, $targetId) . ($action === 'ban' ? ' was banned' : ' was removed'));
        }
        out_json(200, ['status' => 'success']);
    } elseif ($action === 'unban') {
        $groupId = (int) ($input['group_id'] ?? 0);
        $targetId = (int) ($input['target_id'] ?? 0);
        requireGroupAdmin($pdo, $groupId, $userId);
        $pdo->prepare("DELETE FROM chat_group_bans WHERE group_id = ? AND user_id = ?")->execute([$groupId, $targetId]);
        out_json(200, ['status' => 'success']);
    } elseif ($action === 'set_role') {
        $groupId = (int) ($input['group_id'] ?? 0);
        $targetId = (int) ($input['target_id'] ?? 0);
        $role = ($input['role'] ?? '') === 'admin' ? 'admin' : 'member';
        requireGroupAdmin($pdo, $groupId, $userId);

        $stOwner = $pdo->prepare("SELECT created_by FROM chat_groups WHERE id = ?");
        $stOwner->execute([$groupId]);
        if ($role === 'member' && $targetId === (int) $stOwner->fetchColumn()) {
            out_json(403, ['status' => 'error', 'message' => 'The group owner is always an admin']);
        }
        $pdo->prepare("UPDATE chat_group_members SET role = ? WHERE group_id = ? AND user_id = ?")->execute([$role, $groupId, $targetId]);
        if ($role === 'admin') {
            post_system_message($pdo, $groupId, $userId, user_display_name($pdo, $targetId) . ' is now an admin');
        }
        out_json(200, ['status' => 'success']);
    } elseif ($action === 'invite') {
        $groupId = (int) ($input['group_id'] ?? 0);
        $role = requireGroupMember($pdo, $groupId, $userId);
        $group = fetch_group($pdo, $groupId, $userId);
        if (!$group) out_json(404, ['status' => 'error', 'message' => 'Group not found']);
        $isAdmin = $role === 'admin';
        if (!$isAdmin && (int) $group['members_can_invite'] !== 1) {
            out_json(403, ['status' => 'error', 'message' => 'Only admins can invite people to this group']);
        }

        $targets = [];
        if (!empty($input['user_ids'])) {
            $ids = is_array($input['user_ids']) ? $input['user_ids'] : explode(',', (string) $input['user_ids']);
            foreach ($ids as $id) if ((int) $id > 0) $targets[] = (int) $id;
        } elseif ((int) ($input['user_id'] ?? 0) > 0) {
            $targets[] = (int) $input['user_id'];
        } elseif (trim($input['username'] ?? '') !== '') {
            $st = $pdo->prepare("SELECT id FROM users WHERE username = ? LIMIT 1");
            $st->execute([ltrim(trim($input['username']), '@')]);
            $tid = (int) $st->fetchColumn();
            if (!$tid) out_json(404, ['status' => 'error', 'message' => 'User not found']);
            $targets[] = $tid;
        }
        $targets = array_values(array_unique(array_slice($targets, 0, 50)));
        if (!$targets) out_json(400, ['status' => 'error', 'message' => 'No users selected']);

        $existing = annotate_invitee_status($pdo, $groupId, $targets);
        $results = [];
        $sent = 0;
        $added = 0;
        foreach ($targets as $tid) {
            if ($tid === $userId) continue;
            $state = $existing[$tid] ?? null;
            if ($state === 'member' || $state === 'banned' || $state === 'invited') {
                $results[(string) $tid] = $state;
                continue;
            }
            $stU = $pdo->prepare("SELECT id FROM users WHERE id = ?");
            $stU->execute([$tid]);
            if (!$stU->fetchColumn() || blocked_either_way($pdo, $userId, $tid)) {
                $results[(string) $tid] = 'unavailable';
                continue;
            }
            if ($state === 'requested' && $isAdmin) {
                // They already asked to join — an admin inviting them is an approval.
                add_group_member($pdo, $groupId, $tid, user_display_name($pdo, $tid) . ' joined the group');
                notify_user($pdo, $tid, $userId, 'group_request_approved', 'Request approved', "You're now a member of " . $group['name'], $groupId);
                $results[(string) $tid] = 'member';
                $added++;
                continue;
            }
            $pdo->prepare("INSERT INTO chat_group_invites (group_id, inviter_id, invitee_id, status, created_at)
                VALUES (?, ?, ?, 'pending', NOW())
                ON DUPLICATE KEY UPDATE inviter_id = VALUES(inviter_id), status = 'pending', created_at = NOW(), responded_at = NULL")
                ->execute([$groupId, $userId, $tid]);
            notify_user($pdo, $tid, $userId, 'group_invite', 'Group invitation', "$userName invited you to join " . $group['name'], $groupId);
            $results[(string) $tid] = 'invited';
            $sent++;
        }

        $msg = $sent > 0 ? ($sent === 1 ? 'Invitation sent' : "Invitations sent to $sent people") : ($added > 0 ? 'Added to the group' : 'Nothing to send');
        out_json(200, ['status' => 'success', 'message' => $msg, 'results' => $results, 'sent' => $sent, 'added' => $added]);
    } elseif ($action === 'search_invitees') {
        $groupId = (int) ($input['group_id'] ?? 0);
        requireGroupMember($pdo, $groupId, $userId);
        $q = trim((string) ($input['q'] ?? ''));

        $blockSql = '';
        if (function_exists('table_exists') && table_exists($pdo, 'user_blocks')) {
            $blockSql = " AND NOT EXISTS (SELECT 1 FROM user_blocks b WHERE (b.blocker_id = :me_b1 AND b.blocked_id = u.id) OR (b.blocker_id = u.id AND b.blocked_id = :me_b2))";
        }

        if ($q === '') {
            // Suggestions: people you follow or who follow you, friends first.
            $sql = "SELECT * FROM (SELECT u.id, u.name, u.username, u.profile_pic,
                    EXISTS(SELECT 1 FROM follows f1 WHERE f1.follower_id = :me1 AND f1.following_id = u.id) AS i_follow,
                    EXISTS(SELECT 1 FROM follows f2 WHERE f2.follower_id = u.id AND f2.following_id = :me2) AS follows_me
                FROM users u
                WHERE u.id != :me3 AND COALESCE(u.is_banned, 0) = 0
                  AND (u.id IN (SELECT following_id FROM follows WHERE follower_id = :me4)
                       OR u.id IN (SELECT follower_id FROM follows WHERE following_id = :me5))
                  $blockSql) t
                ORDER BY (t.i_follow + t.follows_me) DESC, t.name ASC
                LIMIT 60";
            $st = $pdo->prepare($sql);
            $bind = [':me1' => $userId, ':me2' => $userId, ':me3' => $userId, ':me4' => $userId, ':me5' => $userId];
        } else {
            $like = '%' . addcslashes(ltrim($q, '@'), '%_') . '%';
            $prefix = addcslashes(ltrim($q, '@'), '%_') . '%';
            $sql = "SELECT * FROM (SELECT u.id, u.name, u.username, u.profile_pic,
                    EXISTS(SELECT 1 FROM follows f1 WHERE f1.follower_id = :me1 AND f1.following_id = u.id) AS i_follow,
                    EXISTS(SELECT 1 FROM follows f2 WHERE f2.follower_id = u.id AND f2.following_id = :me2) AS follows_me
                FROM users u
                WHERE u.id != :me3 AND COALESCE(u.is_banned, 0) = 0
                  AND (u.name LIKE :like1 OR u.username LIKE :like2)
                  AND (COALESCE(u.privacy_allow_find_id, 1) = 1
                       OR u.id IN (SELECT following_id FROM follows WHERE follower_id = :me4)
                       OR u.id IN (SELECT follower_id FROM follows WHERE following_id = :me5))
                  $blockSql) t
                ORDER BY (t.i_follow + t.follows_me) DESC, (t.username LIKE :pre1) DESC, (t.name LIKE :pre2) DESC, t.name ASC
                LIMIT 40";
            $st = $pdo->prepare($sql);
            $bind = [':me1' => $userId, ':me2' => $userId, ':me3' => $userId, ':me4' => $userId, ':me5' => $userId,
                ':like1' => $like, ':like2' => $like, ':pre1' => $prefix, ':pre2' => $prefix];
        }
        if ($blockSql !== '') {
            $bind[':me_b1'] = $userId;
            $bind[':me_b2'] = $userId;
        }
        $st->execute($bind);
        $rows = $st->fetchAll(PDO::FETCH_ASSOC);

        $status = annotate_invitee_status($pdo, $groupId, array_map(fn($r) => (int) $r['id'], $rows));
        $users = array_map(function ($r) use ($status, $config) {
            $id = (int) $r['id'];
            return [
                'id' => $id,
                'name' => $r['name'] ?? '',
                'username' => $r['username'] ?? '',
                'avatar' => user_avatar_url($r['profile_pic'] ?? '', $config),
                'is_friend' => !empty($r['i_follow']) && !empty($r['follows_me']),
                'i_follow' => !empty($r['i_follow']),
                'status' => $status[$id] ?? 'none',
            ];
        }, $rows);
        out_json(200, ['status' => 'success', 'users' => $users]);
    } elseif ($action === 'my_invites') {
        $st = $pdo->prepare("SELECT i.id AS invite_id, i.created_at AS invited_at, i.inviter_id,
                u.name AS inviter_name, u.profile_pic AS inviter_avatar,
                g.id, g.name, g.username, g.avatar, g.bio, g.is_private, g.join_fee, g.join_approval,
                " . MEMBER_COUNT_SQL . " AS member_count
            FROM chat_group_invites i
            JOIN chat_groups g ON g.id = i.group_id
            LEFT JOIN users u ON u.id = i.inviter_id
            WHERE i.invitee_id = ? AND i.status = 'pending'
            ORDER BY i.created_at DESC");
        $st->execute([$userId]);
        $rows = $st->fetchAll(PDO::FETCH_ASSOC);
        foreach ($rows as &$r) {
            $r['inviter_avatar'] = user_avatar_url($r['inviter_avatar'] ?? '', $config);
        }
        unset($r);
        out_json(200, ['status' => 'success', 'invites' => $rows]);
    } elseif ($action === 'respond_invite') {
        $inviteId = (int) ($input['invite_id'] ?? 0);
        $accept = to_bool($input['accept'] ?? false);

        $st = $pdo->prepare("SELECT * FROM chat_group_invites WHERE id = ? AND invitee_id = ? AND status = 'pending'");
        $st->execute([$inviteId, $userId]);
        $invite = $st->fetch(PDO::FETCH_ASSOC);
        if (!$invite) out_json(404, ['status' => 'error', 'message' => 'This invitation is no longer available']);
        $groupId = (int) $invite['group_id'];

        if (!$accept) {
            $pdo->prepare("UPDATE chat_group_invites SET status = 'declined', responded_at = NOW() WHERE id = ?")->execute([$inviteId]);
            out_json(200, ['status' => 'success', 'state' => 'declined']);
        }

        $group = fetch_group($pdo, $groupId, $userId);
        if (!$group) out_json(404, ['status' => 'error', 'message' => 'Group no longer exists']);
        $stBan = $pdo->prepare("SELECT 1 FROM chat_group_bans WHERE group_id = ? AND user_id = ?");
        $stBan->execute([$groupId, $userId]);
        if ($stBan->fetchColumn()) out_json(403, ['status' => 'error', 'message' => 'You are banned from this group']);

        if ($group['my_role'] !== null) {
            $pdo->prepare("UPDATE chat_group_invites SET status = 'accepted', responded_at = NOW() WHERE id = ?")->execute([$inviteId]);
            out_json(200, ['status' => 'success', 'state' => 'joined', 'group' => $group]);
        }

        $inviterId = (int) $invite['inviter_id'];
        $inviterIsAdmin = member_role($pdo, $groupId, $inviterId) === 'admin';

        if (!$inviterIsAdmin && (int) $group['join_approval'] === 1) {
            $pdo->prepare("UPDATE chat_group_invites SET status = 'accepted', responded_at = NOW() WHERE id = ?")->execute([$inviteId]);
            open_join_request($pdo, $group, $userId, $inviterId, $userName);
            out_json(200, ['status' => 'success', 'state' => 'requested', 'message' => 'Waiting for admin approval']);
        }

        if (!$inviterIsAdmin) {
            $err = charge_join_fee($pdo, $groupId, $userId, (int) $group['join_fee']);
            if ($err) out_json(400, ['status' => 'error', 'message' => $err]);
        }
        add_group_member($pdo, $groupId, $userId, $userName . ' joined the group');
        notify_user($pdo, $inviterId, $userId, 'group_invite_accepted', 'Invitation accepted', "$userName joined " . $group['name'], $groupId);
        out_json(200, ['status' => 'success', 'state' => 'joined', 'group' => fetch_group($pdo, $groupId, $userId)]);
    } elseif ($action === 'cancel_invite') {
        $inviteId = (int) ($input['invite_id'] ?? 0);
        $st = $pdo->prepare("SELECT group_id, inviter_id FROM chat_group_invites WHERE id = ? AND status = 'pending'");
        $st->execute([$inviteId]);
        $inv = $st->fetch(PDO::FETCH_ASSOC);
        if (!$inv) out_json(404, ['status' => 'error', 'message' => 'Invitation not found']);
        if ((int) $inv['inviter_id'] !== $userId) requireGroupAdmin($pdo, (int) $inv['group_id'], $userId);
        $pdo->prepare("UPDATE chat_group_invites SET status = 'cancelled', responded_at = NOW() WHERE id = ?")->execute([$inviteId]);
        out_json(200, ['status' => 'success']);
    } elseif ($action === 'get_requests') {
        $groupId = (int) ($input['group_id'] ?? 0);
        requireGroupAdmin($pdo, $groupId, $userId);

        $st = $pdo->prepare("SELECT r.id, r.user_id, r.created_at, r.invited_by,
                u.name, u.username, u.profile_pic, ib.name AS invited_by_name
            FROM chat_group_join_requests r
            JOIN users u ON u.id = r.user_id
            LEFT JOIN users ib ON ib.id = r.invited_by
            WHERE r.group_id = ? AND r.status = 'pending'
            ORDER BY r.created_at ASC");
        $st->execute([$groupId]);
        $requests = array_map(fn($r) => [
            'id' => (int) $r['id'],
            'user_id' => (int) $r['user_id'],
            'name' => $r['name'] ?? '',
            'username' => $r['username'] ?? '',
            'avatar' => user_avatar_url($r['profile_pic'] ?? '', $config),
            'invited_by_name' => $r['invited_by_name'],
            'created_at' => $r['created_at'],
        ], $st->fetchAll(PDO::FETCH_ASSOC));

        $st = $pdo->prepare("SELECT i.id, i.invitee_id AS user_id, i.created_at, u.name, u.username, u.profile_pic, iv.name AS inviter_name
            FROM chat_group_invites i
            JOIN users u ON u.id = i.invitee_id
            LEFT JOIN users iv ON iv.id = i.inviter_id
            WHERE i.group_id = ? AND i.status = 'pending'
            ORDER BY i.created_at DESC");
        $st->execute([$groupId]);
        $invites = array_map(fn($r) => [
            'id' => (int) $r['id'],
            'user_id' => (int) $r['user_id'],
            'name' => $r['name'] ?? '',
            'username' => $r['username'] ?? '',
            'avatar' => user_avatar_url($r['profile_pic'] ?? '', $config),
            'invited_by_name' => $r['inviter_name'],
            'created_at' => $r['created_at'],
        ], $st->fetchAll(PDO::FETCH_ASSOC));

        out_json(200, ['status' => 'success', 'requests' => $requests, 'invites' => $invites]);
    } elseif ($action === 'handle_request') {
        $requestId = (int) ($input['request_id'] ?? 0);
        $approve = to_bool($input['approve'] ?? false);

        $st = $pdo->prepare("SELECT * FROM chat_group_join_requests WHERE id = ? AND status = 'pending'");
        $st->execute([$requestId]);
        $req = $st->fetch(PDO::FETCH_ASSOC);
        if (!$req) out_json(404, ['status' => 'error', 'message' => 'Request not found or already handled']);
        $groupId = (int) $req['group_id'];
        $targetId = (int) $req['user_id'];
        requireGroupAdmin($pdo, $groupId, $userId);
        $group = fetch_group($pdo, $groupId, $userId);

        if (!$approve) {
            $pdo->prepare("UPDATE chat_group_join_requests SET status = 'rejected', handled_by = ?, handled_at = NOW() WHERE id = ?")
                ->execute([$userId, $requestId]);
            out_json(200, ['status' => 'success', 'state' => 'rejected']);
        }

        $err = charge_join_fee($pdo, $groupId, $targetId, (int) ($group['join_fee'] ?? 0));
        if ($err) out_json(400, ['status' => 'error', 'message' => 'Could not approve: the user has insufficient coins for the join fee']);

        add_group_member($pdo, $groupId, $targetId, user_display_name($pdo, $targetId) . ' joined the group');
        $pdo->prepare("UPDATE chat_group_join_requests SET handled_by = ? WHERE id = ?")->execute([$userId, $requestId]);
        notify_user($pdo, $targetId, $userId, 'group_request_approved', 'Request approved', "You're now a member of " . ($group['name'] ?? 'the group'), $groupId);
        out_json(200, ['status' => 'success', 'state' => 'approved']);
    } elseif ($action === 'get_members') {
        $groupId = (int) ($input['group_id'] ?? 0);
        $myRole = requireGroupMember($pdo, $groupId, $userId);

        $st = $pdo->prepare("
            SELECT m.user_id AS id, u.name, u.username, u.profile_pic AS avatar, m.role, m.joined_at
            FROM chat_group_members m
            JOIN users u ON m.user_id = u.id
            WHERE m.group_id = ?
            ORDER BY m.role = 'admin' DESC, m.joined_at ASC
        ");
        $st->execute([$groupId]);
        $stOwner = $pdo->prepare("SELECT created_by FROM chat_groups WHERE id = ?");
        $stOwner->execute([$groupId]);
        out_json(200, ['status' => 'success', 'my_role' => $myRole, 'owner_id' => (int) $stOwner->fetchColumn(), 'members' => $st->fetchAll(PDO::FETCH_ASSOC)]);
    } elseif ($action === 'send_media') {
        $groupId = (int) ($_POST['group_id'] ?? 0);
        $voiceDuration = (int) ($_POST['voice_duration'] ?? 0);
        requireGroupMember($pdo, $groupId, $userId);

        if (!isset($_FILES['media'])) {
            out_json(400, ['status' => 'error', 'message' => 'No file was received.']);
        }
        if ($_FILES['media']['error'] !== UPLOAD_ERR_OK) {
            out_json(400, ['status' => 'error', 'message' => upload_error_message((int) $_FILES['media']['error'])]);
        }

        $imgExt = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'];
        $vidExt = ['mp4', 'mov', 'avi', 'webm', 'm4v', '3gp', 'mkv'];
        $audExt = ['m4a', 'aac', 'mp3', 'ogg', 'wav', 'opus'];
        $ext = strtolower(pathinfo($_FILES['media']['name'], PATHINFO_EXTENSION));
        $requested = $_POST['type'] ?? '';
        if (in_array($ext, $vidExt, true)) {
            $type = 'video';
        } elseif (in_array($ext, $imgExt, true)) {
            $type = 'image';
        } elseif (in_array($ext, $audExt, true)) {
            $type = 'audio';
        } elseif (in_array($requested, ['image', 'video', 'audio'], true)) {
            $type = $requested;
            $ext = $type === 'video' ? 'mp4' : ($type === 'audio' ? 'm4a' : 'jpg');
        } else {
            out_json(400, ['status' => 'error', 'message' => 'Unsupported file type']);
        }

        $uploadsDir = __DIR__ . '/uploads/chat';
        if (!is_dir($uploadsDir)) @mkdir($uploadsDir, 0755, true);
        $filename = uniqid('media_') . '.' . $ext;

        if (!move_uploaded_file($_FILES['media']['tmp_name'], $uploadsDir . '/' . $filename)) {
            out_json(500, ['status' => 'error', 'message' => 'Could not save the file on the server']);
        }

        // NSFW scan: same check used on post/story/1:1-chat uploads.
        if ($type === 'image' || $type === 'video') {
            $nch = curl_init('http://127.0.0.1:8000/scan/local');
            curl_setopt_array($nch, [
                CURLOPT_RETURNTRANSFER => true, CURLOPT_POST => true,
                CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
                CURLOPT_POSTFIELDS => json_encode(['path' => $uploadsDir . '/' . $filename, 'kind' => $type]),
                CURLOPT_TIMEOUT => 35,
            ]);
            $nresp = curl_exec($nch);
            $ncode = curl_getinfo($nch, CURLINFO_HTTP_CODE);
            curl_close($nch);
            $nj = ($nresp !== false && $ncode === 200) ? json_decode($nresp, true) : null;
            if (is_array($nj) && ($nj['status'] ?? '') === 'rejected') {
                try {
                    $pdo->prepare('INSERT INTO nsfw_violations (user_id, content_type, reason, details) VALUES (?,?,?,?)')
                        ->execute([$userId, $type, $nj['reason'] ?? 'nsfw', json_encode($nj['detections'] ?? [])]);
                    $pdo->prepare('UPDATE users SET nsfw_strikes = nsfw_strikes + 1 WHERE id = ?')->execute([$userId]);
                    $pdo->prepare('UPDATE users SET upload_blocked = 1 WHERE id = ?')->execute([$userId]);
                } catch (Throwable $e) {}
                @unlink($uploadsDir . '/' . $filename);
                out_json(403, ['status' => 'error', 'error_code' => 'nsfw_rejected',
                    'message' => 'Your upload was removed for violating our content policy. Repeated violations may lead to your account being banned.']);
            }
        }

        $mediaUrl = '/uploads/chat/' . $filename;
        $pdo->prepare("INSERT INTO chat_group_messages (group_id, sender_id, message, type, voice_duration) VALUES (?, ?, ?, ?, ?)")
            ->execute([$groupId, $userId, $mediaUrl, $type, $voiceDuration]);
        $msgId = $pdo->lastInsertId();
        $pdo->prepare("UPDATE chat_groups SET last_active = NOW() WHERE id = ?")->execute([$groupId]);

        out_json(200, ['status' => 'success', 'message_id' => $msgId, 'media_url' => $mediaUrl, 'type' => $type]);
    } elseif ($action === 'delete_group') {
        $groupId = (int) ($input['group_id'] ?? 0);
        if ($groupId <= 0) out_json(400, ['status' => 'error', 'message' => 'Invalid group']);

        $st = $pdo->prepare("SELECT created_by FROM chat_groups WHERE id = ?");
        $st->execute([$groupId]);
        if ((int) $st->fetchColumn() !== $userId) {
            out_json(403, ['status' => 'error', 'message' => 'Only the group owner can delete the group']);
        }

        $pdo->beginTransaction();
        $pdo->prepare("DELETE h FROM chat_group_message_hidden h JOIN chat_group_messages m ON m.id = h.message_id WHERE m.group_id = ?")->execute([$groupId]);
        foreach (['chat_group_messages', 'chat_group_members', 'chat_group_bans', 'chat_group_invites', 'chat_group_join_requests', 'chat_group_views'] as $t) {
            $pdo->prepare("DELETE FROM $t WHERE group_id = ?")->execute([$groupId]);
        }
        $pdo->prepare("DELETE FROM chat_groups WHERE id = ?")->execute([$groupId]);
        $pdo->commit();

        out_json(200, ['status' => 'success', 'message' => 'Group deleted']);
    } elseif ($action === 'clear_my_chat') {
        $groupId = (int) ($input['group_id'] ?? 0);
        if ($groupId <= 0) out_json(400, ['status' => 'error', 'message' => 'Invalid group']);
        requireGroupMember($pdo, $groupId, $userId);

        // Hide the whole history for this user only; other members keep theirs.
        $pdo->prepare("INSERT IGNORE INTO chat_group_message_hidden (message_id, user_id) SELECT id, ? FROM chat_group_messages WHERE group_id = ?")
            ->execute([$userId, $groupId]);
        out_json(200, ['status' => 'success', 'message' => 'Chat cleared']);
    } elseif ($action === 'get_group_by_username') {
        $username = normalize_group_username($input['username'] ?? '');
        if ($username === '') out_json(400, ['status' => 'error', 'message' => 'Username required']);
        $st = $pdo->prepare("SELECT id FROM chat_groups WHERE username = ?");
        $st->execute([$username]);
        $gid = (int) $st->fetchColumn();
        $group = $gid ? fetch_group($pdo, $gid, $userId) : null;
        if (!$group) out_json(404, ['status' => 'error', 'message' => 'Group not found']);
        out_json(200, ['status' => 'success', 'group' => $group]);
    } elseif ($action === 'get_group') {
        $groupId = (int) ($input['group_id'] ?? 0);
        if ($groupId <= 0) out_json(400, ['status' => 'error', 'message' => 'Invalid group']);
        $group = fetch_group($pdo, $groupId, $userId);
        if (!$group) out_json(404, ['status' => 'error', 'message' => 'Group not found']);
        out_json(200, ['status' => 'success', 'group' => $group]);
    } elseif ($action === 'track_view') {
        $groupId = (int) ($input['group_id'] ?? 0);
        if ($groupId <= 0) out_json(400, ['status' => 'error', 'message' => 'Invalid group']);
        $pdo->prepare("INSERT IGNORE INTO chat_group_views (group_id, user_id) VALUES (?, ?)")->execute([$groupId, $userId]);
        $pdo->prepare("UPDATE chat_groups SET views_count = views_count + 1, last_active = NOW() WHERE id = ?")->execute([$groupId]);
        out_json(200, ['status' => 'success']);
    } elseif ($action === 'get_viewers') {
        $groupId = (int) ($input['group_id'] ?? 0);
        if ($groupId <= 0) out_json(400, ['status' => 'error', 'message' => 'Invalid group']);
        $st = $pdo->prepare("
            SELECT u.id, u.name, u.profile_pic AS avatar
            FROM chat_group_views v
            JOIN users u ON v.user_id = u.id
            WHERE v.group_id = ?
            ORDER BY v.viewed_at DESC LIMIT 5
        ");
        $st->execute([$groupId]);
        $viewers = $st->fetchAll(PDO::FETCH_ASSOC);
        foreach ($viewers as &$v) {
            $v['avatar'] = user_avatar_url($v['avatar'] ?? '', $config);
        }
        unset($v);
        out_json(200, ['status' => 'success', 'viewers' => $viewers]);
    } elseif ($action === 'get_unread_count') {
        $groupId = (int) ($input['group_id'] ?? 0);
        if ($groupId <= 0) out_json(400, ['status' => 'error', 'message' => 'Invalid group']);
        $st = $pdo->prepare("SELECT COUNT(*) FROM chat_group_messages WHERE group_id = ? AND sender_id != ?");
        $st->execute([$groupId, $userId]);
        out_json(200, ['status' => 'success', 'unread_count' => (int) $st->fetchColumn()]);
    } elseif ($action === 'delete_all_groups') {
        // NOTE: kept for compatibility, but any logged-in user can call this.
        // It should be moved to the admin panel or removed.
        $pdo->exec("DELETE FROM chat_group_messages");
        $pdo->exec("DELETE FROM chat_group_views");
        $pdo->exec("DELETE FROM chat_group_members");
        $pdo->exec("DELETE FROM chat_group_bans");
        $pdo->exec("DELETE FROM chat_groups");
        out_json(200, ['status' => 'success', 'message' => 'All groups deleted']);
    } else {
        out_json(400, ['status' => 'error', 'message' => 'Unknown action']);
    }
} catch (\Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) $pdo->rollBack();
    out_json(500, ['status' => 'error', 'message' => $e->getMessage()]);
}
