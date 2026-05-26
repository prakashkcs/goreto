<?php
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

// Normalize any avatar/profile_pic path to a full URL
function norm_url(?string $path): ?string
{
    if (empty($path))
        return null;
    if (strpos($path, 'http') === 0)
        return $path;
    $base = 'https://goreto.org/ekloadmin/';
    $p = ltrim($path, '/');
    return $base . $p;
}

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

    try {
        $pdo->exec("ALTER TABLE chat_groups ADD COLUMN join_fee INT DEFAULT 0");
    } catch (Exception $e) {
    }

    try {
        $pdo->exec("ALTER TABLE chat_groups ADD COLUMN monthly_fee INT DEFAULT 0");
    } catch (Exception $e) {
    }

    try {
        $pdo->exec("ALTER TABLE chat_groups ADD COLUMN is_private TINYINT(1) DEFAULT 0");
    } catch (Exception $e) {
    }

    try {
        $pdo->exec("ALTER TABLE chat_groups ADD COLUMN message_delay INT DEFAULT 0");
    } catch (Exception $e) {
    }

    try {
        $pdo->exec("ALTER TABLE chat_groups ADD COLUMN username VARCHAR(100) NULL");
    } catch (Exception $e) {
    }

    try {
        $pdo->exec("ALTER TABLE chat_groups ADD COLUMN bio VARCHAR(500) NULL");
    } catch (Exception $e) {
    }

    try {
        $pdo->exec("ALTER TABLE chat_groups ADD COLUMN views_count INT DEFAULT 0");
    } catch (Exception $e) {
    }

    try {
        $pdo->exec("ALTER TABLE chat_groups ADD COLUMN last_active DATETIME DEFAULT CURRENT_TIMESTAMP");
    } catch (Exception $e) {
    }

    try {
        $pdo->exec("ALTER TABLE chat_groups ADD UNIQUE INDEX idx_username (username)");
    } catch (Exception $e) {
    }

    try {
        $pdo->exec("ALTER TABLE chat_groups ADD COLUMN permissions TEXT NULL DEFAULT NULL");
    } catch (Exception $e) {
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

    try {
        $pdo->exec("ALTER TABLE chat_group_messages MODIFY COLUMN type ENUM('text', 'image', 'video', 'audio', 'system') DEFAULT 'text'");
    } catch (Exception $e) {
    }

    // Composite index for fast MAX(id) GROUP BY lookups in my_groups last-message query
    try {
        $pdo->exec("ALTER TABLE chat_group_messages ADD INDEX idx_group_msg (group_id, id)");
    } catch (Exception $e) {
    }
    // Index on chat_group_members.user_id for fast membership lookups
    try {
        $pdo->exec("ALTER TABLE chat_group_members ADD INDEX idx_user (user_id)");
    } catch (Exception $e) {
    }

    $pdo->exec("CREATE TABLE IF NOT EXISTS chat_group_bans (
        group_id INT NOT NULL,
        user_id INT NOT NULL,
        banned_by INT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (group_id, user_id)
    ) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;");
}

function out_json(int $code, array $payload): void
{
    http_response_code($code);
    echo json_encode($payload);
    exit;
}

function requireGroupAdmin(PDO $pdo, int $groupId, int $userId): void
{
    $st = $pdo->prepare("SELECT role FROM chat_group_members WHERE group_id = ? AND user_id = ?");
    $st->execute([$groupId, $userId]);
    if ($st->fetchColumn() !== 'admin') {
        out_json(403, ['status' => 'error', 'message' => 'Admin privileges required']);
    }
}

try {
    $cfgFile = __DIR__ . '/../config/config.php';
    $config = file_exists($cfgFile) ? (require $cfgFile) : [];
    if (empty($config['base_url'])) {
        $proto = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
        $config['base_url'] = $proto . '://' . ($_SERVER['HTTP_HOST'] ?? 'goreto.org') . '/ekloadmin/api/v1/';
    }
    $user = requireUser($pdo);
    $userId = (int) $user['id'];

    $initFlag = __DIR__ . '/.group_chat_init';
    if (!file_exists($initFlag)) {
        init_group_chat_tables($pdo);
        @file_put_contents($initFlag, time());
    }

    $action = $_GET['action'] ?? $_POST['action'] ?? '';
    $input = json_decode(file_get_contents('php://input'), true) ?? [];
    $input = array_merge($input, $_POST);

    if ($action === 'create') {
        $name = trim($input['name'] ?? '');
        if ($name === '') {
            out_json(400, ['status' => 'error', 'message' => 'Group name required']);
        }

        $countStmt = $pdo->prepare("SELECT COUNT(*) FROM chat_groups WHERE created_by = ?");
        $countStmt->execute([$userId]);
        $groupCount = (int) $countStmt->fetchColumn();
        if ($groupCount >= 10) {
            out_json(400, ['status' => 'error', 'message' => 'Maximum 10 groups allowed per user']);
        }

        $username = trim($input['username'] ?? '');
        if ($username !== '') {
            $check = $pdo->prepare("SELECT id FROM chat_groups WHERE username = ?");
            $check->execute([$username]);
            if ($check->fetch()) {
                out_json(400, ['status' => 'error', 'message' => 'Username already taken']);
            }
        }

        $bio = trim($input['bio'] ?? '');
        $joinFee = (int) ($input['join_fee'] ?? 0);
        $monthlyFee = (int) ($input['monthly_fee'] ?? 0);
        $isPrivate = (int) ($input['is_private'] ?? 0);

        $avatarPath = null;
        if (isset($_FILES['avatar']) && $_FILES['avatar']['error'] === UPLOAD_ERR_OK) {
            $uploadDir = __DIR__ . '/uploads/group_avatars';
            if (!is_dir($uploadDir)) {
                mkdir($uploadDir, 0755, true);
            }
            $ext = pathinfo($_FILES['avatar']['name'], PATHINFO_EXTENSION);
            $filename = uniqid('group_') . '.' . $ext;
            if (move_uploaded_file($_FILES['avatar']['tmp_name'], $uploadDir . '/' . $filename)) {
                $avatarPath = 'https://goreto.org/ekloadmin/api/v1/uploads/group_avatars/' . $filename;
            }
        }

        $pdo->beginTransaction();
        $st = $pdo->prepare("INSERT INTO chat_groups (name, username, bio, created_by, join_fee, monthly_fee, is_private, avatar) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
        $st->execute([$name, $username ?: null, $bio ?: null, $userId, $joinFee, $monthlyFee, $isPrivate, $avatarPath]);
        $groupId = (int) $pdo->lastInsertId();

        $stMem = $pdo->prepare("INSERT INTO chat_group_members (group_id, user_id, role) VALUES (?, ?, 'admin')");
        $stMem->execute([$groupId, $userId]);

        $stMsg = $pdo->prepare("INSERT INTO chat_group_messages (group_id, sender_id, message, type) VALUES (?, ?, ?, 'system')");
        $stMsg->execute([$groupId, $userId, "Group created by " . $user['name']]);

        $pdo->commit();

        $stGroup = $pdo->prepare("SELECT g.*, 
            (SELECT COUNT(*) FROM chat_group_members WHERE group_id = g.id) as member_count,
            (SELECT role FROM chat_group_members WHERE group_id = g.id AND user_id = ?) as my_role
            FROM chat_groups g WHERE g.id = ?");
        $stGroup->execute([$userId, $groupId]);
        $group = $stGroup->fetch(PDO::FETCH_ASSOC);

        $response = [
            'status' => 'success',
            'group_id' => $groupId,
            'message' => 'Group created',
            'group' => [
                'id' => $group['id'],
                'name' => $group['name'],
                'username' => $group['username'],
                'avatar' => $group['avatar'],
                'bio' => $group['bio'],
                'join_fee' => $group['join_fee'],
                'monthly_fee' => $group['monthly_fee'],
                'created_by' => $group['created_by'],
                'member_count' => $group['member_count'],
                'is_member' => 1,
                'my_role' => $group['my_role'],
                'is_private' => $group['is_private'],
            ]
        ];
        out_json(200, $response);
    } elseif ($action === 'join') {
        $groupId = (int) ($input['group_id'] ?? 0);
        if ($groupId <= 0)
            out_json(400, ['status' => 'error', 'message' => 'Invalid group']);

        $stBan = $pdo->prepare("SELECT 1 FROM chat_group_bans WHERE group_id = ? AND user_id = ?");
        $stBan->execute([$groupId, $userId]);
        if ($stBan->fetchColumn())
            out_json(403, ['status' => 'error', 'message' => 'You are banned from this group']);

        $stGrp = $pdo->prepare("SELECT join_fee FROM chat_groups WHERE id = ?");
        $stGrp->execute([$groupId]);
        $fee = (int) $stGrp->fetchColumn();

        if ($fee > 0) {
            $stC = $pdo->prepare("SELECT 1 FROM chat_group_members WHERE group_id = ? AND user_id = ?");
            $stC->execute([$groupId, $userId]);
            if (!$stC->fetchColumn()) {
                $pdo->beginTransaction();
                $stBal = $pdo->prepare("SELECT balance_coins FROM user_wallets WHERE user_id=? FOR UPDATE");
                $stBal->execute([$userId]);
                $bal = (int) $stBal->fetchColumn();

                if ($bal < $fee) {
                    $pdo->rollBack();
                    out_json(400, ['status' => 'error', 'message' => "Insufficient coins (Need $fee)"]);
                }
                $pdo->prepare("UPDATE user_wallets SET balance_coins = balance_coins - ? WHERE user_id = ?")->execute([$fee, $userId]);
                $pdo->prepare("INSERT INTO wallet_transactions (user_id,type,direction,coins,status,note) VALUES (?,'group_join','debit',?,'completed',?)")->execute([$userId, $fee, "Joined premium group #$groupId"]);
                $pdo->commit();
            }
        }

        $st = $pdo->prepare("INSERT IGNORE INTO chat_group_members (group_id, user_id, role) VALUES (?, ?, 'member')");
        $st->execute([$groupId, $userId]);

        if ($st->rowCount() > 0) {
            $stMsg = $pdo->prepare("INSERT INTO chat_group_messages (group_id, sender_id, message, type) VALUES (?, ?, ?, 'system')");
            $stMsg->execute([$groupId, $userId, $user['name'] . " joined the group"]);
        }
        out_json(200, ['status' => 'success']);
    } elseif ($action === 'leave') {
        $groupId = (int) ($input['group_id'] ?? 0);
        $st = $pdo->prepare("DELETE FROM chat_group_members WHERE group_id = ? AND user_id = ?");
        $st->execute([$groupId, $userId]);

        if ($st->rowCount() > 0) {
            $stMsg = $pdo->prepare("INSERT INTO chat_group_messages (group_id, sender_id, message, type) VALUES (?, ?, ?, 'system')");
            $stMsg->execute([$groupId, $userId, $user['name'] . " left the group"]);
        }
        out_json(200, ['status' => 'success']);
    } elseif ($action === 'list_all') {
        $search = trim($_GET['search'] ?? $input['search'] ?? '');
        $baseListSql = "SELECT g.id, g.name, g.avatar, g.username, g.bio, g.join_fee, g.monthly_fee, g.is_private,
                COALESCE(g.created_by,0) as created_by, g.views_count, g.last_active,
                COALESCE(mc.cnt,0) as member_count,
                COALESCE(mem.is_member,0) as is_member
            FROM chat_groups g
            LEFT JOIN (SELECT group_id, COUNT(*) as cnt FROM chat_group_members GROUP BY group_id) mc ON mc.group_id = g.id
            LEFT JOIN (SELECT group_id, 1 as is_member FROM chat_group_members WHERE user_id = ?) mem ON mem.group_id = g.id
            LEFT JOIN chat_group_bans cgb ON cgb.group_id = g.id AND cgb.user_id = ?
            WHERE cgb.group_id IS NULL
            AND g.is_private = 0";
        if ($search !== '') {
            $like = '%' . addcslashes($search, '%_') . '%';
            $stmt = $pdo->prepare($baseListSql . "
                AND (g.name LIKE ? OR g.username LIKE ? OR g.bio LIKE ?)
                ORDER BY g.views_count DESC, g.last_active DESC, g.created_at DESC LIMIT 50");
            $stmt->execute([$userId, $userId, $like, $like, $like]);
        } else {
            $stmt = $pdo->prepare($baseListSql . "
                ORDER BY g.views_count DESC, g.last_active DESC, g.created_at DESC LIMIT 50");
            $stmt->execute([$userId, $userId]);
        }
        $groups = $stmt->fetchAll(PDO::FETCH_ASSOC);
        foreach ($groups as &$g) {
            $g['avatar'] = norm_url($g['avatar'] ?? null);
        }
        unset($g);
        out_json(200, ['status' => 'success', 'groups' => $groups]);
    } elseif ($action === 'search_groups') {
        $search = trim($input['search'] ?? '');
        if ($search === '') {
            out_json(400, ['status' => 'error', 'message' => 'Search term required']);
        }
        $like = '%' . addcslashes($search, '%_') . '%';
        $stmt = $pdo->prepare("SELECT g.id, g.name, g.avatar, g.username, g.bio, g.join_fee, g.monthly_fee, g.is_private,
            COALESCE(g.created_by,0) as created_by, g.views_count, g.last_active,
            COALESCE(mc.cnt,0) as member_count,
            COALESCE(mem.is_member,0) as is_member
            FROM chat_groups g
            LEFT JOIN (SELECT group_id, COUNT(*) as cnt FROM chat_group_members GROUP BY group_id) mc ON mc.group_id = g.id
            LEFT JOIN (SELECT group_id, 1 as is_member FROM chat_group_members WHERE user_id = ?) mem ON mem.group_id = g.id
            LEFT JOIN chat_group_bans cgb ON cgb.group_id = g.id AND cgb.user_id = ?
            WHERE cgb.group_id IS NULL
            AND g.is_private = 0
            AND (g.name LIKE ? OR g.username LIKE ? OR g.bio LIKE ?)
            ORDER BY g.views_count DESC, g.last_active DESC LIMIT 30");
        $stmt->execute([$userId, $userId, $like, $like, $like]);
        $groups = $stmt->fetchAll(PDO::FETCH_ASSOC);
        foreach ($groups as &$g) {
            $g['avatar'] = norm_url($g['avatar'] ?? null);
        }
        unset($g);
        out_json(200, ['status' => 'success', 'groups' => $groups]);
    } elseif ($action === 'my_groups') {
        $stmt = $pdo->prepare("
            SELECT g.id, g.name, g.avatar, g.username, g.bio, g.join_fee, g.monthly_fee, g.is_private, g.message_delay, g.permissions,
                   COALESCE(g.created_by,0) as created_by, g.views_count,
                   m.role as my_role,
                   mc.cnt as member_count,
                   1 as is_member,
                   lm.message as last_message,
                   lm.created_at as last_message_time
            FROM chat_groups g
            JOIN chat_group_members m ON g.id = m.group_id AND m.user_id = ?
            LEFT JOIN (
                SELECT group_id, COUNT(*) as cnt FROM chat_group_members GROUP BY group_id
            ) mc ON mc.group_id = g.id
            LEFT JOIN (
                SELECT m1.group_id, m1.message, m1.created_at
                FROM chat_group_messages m1
                INNER JOIN (
                    SELECT group_id, MAX(id) as max_id FROM chat_group_messages GROUP BY group_id
                ) m2 ON m1.group_id = m2.group_id AND m1.id = m2.max_id
            ) lm ON lm.group_id = g.id
            ORDER BY lm.created_at DESC
        ");
        $stmt->execute([$userId]);
        $groups = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $defaultPerms = ['can_send_text' => 1, 'can_send_media' => 1, 'can_send_voice' => 1, 'can_send_stickers' => 1];
        foreach ($groups as &$g) {
            $g['permissions'] = $g['permissions'] ? json_decode($g['permissions'], true) : $defaultPerms;
            $g['avatar'] = norm_url($g['avatar'] ?? null);
        }
        unset($g);
        out_json(200, ['status' => 'success', 'groups' => $groups]);
    } elseif ($action === 'send') {
        $groupId = (int) ($input['group_id'] ?? 0);
        $message = trim($input['message'] ?? '');
        $type = $input['type'] ?? 'text';

        $stC = $pdo->prepare("SELECT 1 FROM chat_group_members WHERE group_id = ? AND user_id = ?");
        $stC->execute([$groupId, $userId]);
        if (!$stC->fetchColumn())
            out_json(403, ['status' => 'error', 'message' => 'Not a group member']);

        if ($message === '' && $type === 'text') {
            out_json(400, ['status' => 'error', 'message' => 'Empty message']);
        }

        $st = $pdo->prepare("INSERT INTO chat_group_messages (group_id, sender_id, message, type) VALUES (?, ?, ?, ?)");
        $st->execute([$groupId, $userId, $message, $type]);

        $msgId = $pdo->lastInsertId();
        out_json(200, ['status' => 'success', 'message_id' => $msgId, 'created_at' => gmdate('Y-m-d H:i:s')]);
    } elseif ($action === 'sync') {
        $groupId = (int) ($_GET['group_id'] ?? 0);
        $lastId = (int) ($_GET['last_id'] ?? 0);

        $stC = $pdo->prepare("SELECT 1 FROM chat_group_members WHERE group_id = ? AND user_id = ?");
        $stC->execute([$groupId, $userId]);
        if (!$stC->fetchColumn())
            out_json(403, ['status' => 'error', 'message' => 'Not a group member']);

        $st = $pdo->prepare("
            SELECT m.id, m.sender_id, m.message, m.type, m.created_at,
                   u.name as sender_name,
                   u.profile_pic as sender_avatar
            FROM chat_group_messages m
            LEFT JOIN users u ON m.sender_id = u.id
            WHERE m.group_id = ? AND m.id > ?
            ORDER BY m.id DESC LIMIT 50
        ");
        $st->execute([$groupId, $lastId]);
        $messages = array_reverse($st->fetchAll(PDO::FETCH_ASSOC));
        foreach ($messages as &$msg) {
            $msg['sender_avatar'] = norm_url($msg['sender_avatar'] ?? null);
        }
        unset($msg);
        out_json(200, ['status' => 'success', 'messages' => $messages]);
    } elseif ($action === 'update_settings') {
        $groupId = (int) ($input['group_id'] ?? $_POST['group_id'] ?? 0);
        requireGroupAdmin($pdo, $groupId, $userId);

        $updates = [];
        $params = [];

        if (array_key_exists('name', $input) && trim($input['name']) !== '') {
            $updates[] = "name = ?";
            $params[] = trim($input['name']);
        }
        if (array_key_exists('username', $input) && trim($input['username']) !== '') {
            $check = $pdo->prepare("SELECT id FROM chat_groups WHERE username = ? AND id != ?");
            $check->execute([trim($input['username']), $groupId]);
            if (!$check->fetch()) {
                $updates[] = "username = ?";
                $params[] = trim($input['username']);
            }
        }
        if (array_key_exists('bio', $input)) {
            $updates[] = "bio = ?";
            $params[] = trim($input['bio'] ?? '');
        }
        if (array_key_exists('join_fee', $input)) {
            $updates[] = "join_fee = ?";
            $params[] = (int) $input['join_fee'];
        }
        if (array_key_exists('monthly_fee', $input)) {
            $updates[] = "monthly_fee = ?";
            $params[] = (int) $input['monthly_fee'];
        }
        if (array_key_exists('is_private', $input)) {
            $updates[] = "is_private = ?";
            $params[] = (int) $input['is_private'];
        }
        if (array_key_exists('message_delay', $input)) {
            $updates[] = "message_delay = ?";
            $params[] = max(0, (int) $input['message_delay']);
        }
        if (array_key_exists('permissions', $input)) {
            $perms = $input['permissions'];
            $updates[] = "permissions = ?";
            $params[] = is_string($perms) ? $perms : json_encode($perms);
        }

        if (isset($_FILES['avatar']) && $_FILES['avatar']['error'] === UPLOAD_ERR_OK) {
            $uploadsDir = __DIR__ . '/uploads/group_avatars';
            @mkdir($uploadsDir, 0755, true);
            $ext = strtolower(pathinfo($_FILES['avatar']['name'], PATHINFO_EXTENSION));
            $filename = uniqid('grp_') . '.' . $ext;
            if (move_uploaded_file($_FILES['avatar']['tmp_name'], $uploadsDir . '/' . $filename)) {
                $updates[] = "avatar = ?";
                $params[] = 'https://goreto.org/ekloadmin/api/v1/uploads/group_avatars/' . $filename;
            }
        }

        if (count($updates) > 0) {
            $sql = "UPDATE chat_groups SET " . implode(', ', $updates) . " WHERE id = ?";
            $params[] = $groupId;
            $pdo->prepare($sql)->execute($params);
        }
        out_json(200, ['status' => 'success']);
    } elseif ($action === 'kick') {
        $groupId = (int) ($input['group_id'] ?? 0);
        $targetId = (int) ($input['target_id'] ?? 0);
        requireGroupAdmin($pdo, $groupId, $userId);

        $pdo->prepare("DELETE FROM chat_group_members WHERE group_id = ? AND user_id = ?")->execute([$groupId, $targetId]);
        out_json(200, ['status' => 'success']);
    } elseif ($action === 'ban') {
        $groupId = (int) ($input['group_id'] ?? 0);
        $targetId = (int) ($input['target_id'] ?? 0);
        requireGroupAdmin($pdo, $groupId, $userId);

        $pdo->prepare("DELETE FROM chat_group_members WHERE group_id = ? AND user_id = ?")->execute([$groupId, $targetId]);
        $pdo->prepare("INSERT IGNORE INTO chat_group_bans (group_id, user_id, banned_by) VALUES (?, ?, ?)")->execute([$groupId, $targetId, $userId]);
        out_json(200, ['status' => 'success']);
    } elseif ($action === 'set_role') {
        $groupId = (int) ($input['group_id'] ?? 0);
        $targetId = (int) ($input['target_id'] ?? 0);
        $role = $input['role'] === 'admin' ? 'admin' : 'member';
        requireGroupAdmin($pdo, $groupId, $userId);

        $pdo->prepare("UPDATE chat_group_members SET role = ? WHERE group_id = ? AND user_id = ?")->execute([$role, $groupId, $targetId]);
        out_json(200, ['status' => 'success']);
    } elseif ($action === 'invite') {
        $groupId = (int) ($input['group_id'] ?? 0);
        $username = trim($input['username'] ?? '');
        requireGroupAdmin($pdo, $groupId, $userId);

        $st = $pdo->prepare("SELECT id, name FROM users WHERE username = ? OR email = ?");
        $st->execute([$username, $username]);
        $target = $st->fetch(PDO::FETCH_ASSOC);
        if (!$target)
            out_json(404, ['status' => 'error', 'message' => 'User not found']);

        $targetId = (int) $target['id'];

        $stBan = $pdo->prepare("SELECT 1 FROM chat_group_bans WHERE group_id = ? AND user_id = ?");
        $stBan->execute([$groupId, $targetId]);
        if ($stBan->fetchColumn())
            out_json(400, ['status' => 'error', 'message' => 'User is banned from this group']);

        $pdo->prepare("INSERT IGNORE INTO chat_group_members (group_id, user_id, role) VALUES (?, ?, 'member')")->execute([$groupId, $targetId]);

        $pdo->prepare("INSERT INTO chat_group_messages (group_id, sender_id, message, type) VALUES (?, ?, ?, 'system')")
            ->execute([$groupId, $userId, $target['name'] . " was added by admin"]);

        out_json(200, ['status' => 'success', 'message' => 'User added']);
    } elseif ($action === 'get_members') {
        $groupId = (int) ($_GET['group_id'] ?? 0);
        $stC = $pdo->prepare("SELECT role FROM chat_group_members WHERE group_id = ? AND user_id = ?");
        $stC->execute([$groupId, $userId]);
        $myRole = $stC->fetchColumn();
        if (!$myRole)
            out_json(403, ['status' => 'error', 'message' => 'Not a member']);

        $st = $pdo->prepare("
            SELECT m.user_id as id, u.name, u.username, u.profile_pic as avatar, m.role, m.joined_at
            FROM chat_group_members m
            JOIN users u ON m.user_id = u.id
            WHERE m.group_id = ?
            ORDER BY m.role = 'admin' DESC, m.joined_at ASC
        ");
        $st->execute([$groupId]);
        $members = $st->fetchAll(PDO::FETCH_ASSOC);
        foreach ($members as &$m) {
            $m['avatar'] = norm_url($m['avatar'] ?? null);
        }
        unset($m);
        out_json(200, ['status' => 'success', 'my_role' => $myRole, 'members' => $members]);
    } elseif ($action === 'send_media') {
        $groupId = (int) ($_POST['group_id'] ?? 0);
        $type = $_POST['type'] ?? 'image';

        $stC = $pdo->prepare("SELECT 1 FROM chat_group_members WHERE group_id = ? AND user_id = ?");
        $stC->execute([$groupId, $userId]);
        if (!$stC->fetchColumn())
            out_json(403, ['status' => 'error', 'message' => 'Not a group member']);

        if (!isset($_FILES['media']) || $_FILES['media']['error'] !== UPLOAD_ERR_OK) {
            out_json(400, ['status' => 'error', 'message' => 'Upload failed']);
        }

        $uploadsDir = __DIR__ . '/uploads/chat';
        @mkdir($uploadsDir, 0755, true);
        $ext = strtolower(pathinfo($_FILES['media']['name'], PATHINFO_EXTENSION));
        $filename = uniqid('media_') . '.' . $ext;

        if (move_uploaded_file($_FILES['media']['tmp_name'], $uploadsDir . '/' . $filename)) {
            $mediaUrl = '/uploads/chat/' . $filename;

            $pdo->prepare("INSERT INTO chat_group_messages (group_id, sender_id, message, type) VALUES (?, ?, ?, ?)")
                ->execute([$groupId, $userId, $mediaUrl, $type]);

            out_json(200, ['status' => 'success', 'message_id' => $pdo->lastInsertId(), 'media_url' => $mediaUrl]);
        } else {
            out_json(500, ['status' => 'error', 'message' => 'Move file failed']);
        }
    } elseif ($action === 'delete_group') {
        $groupId = (int) ($input['group_id'] ?? 0);
        if ($groupId <= 0)
            out_json(400, ['status' => 'error', 'message' => 'Invalid group']);

        $st = $pdo->prepare("SELECT created_by FROM chat_groups WHERE id = ?");
        $st->execute([$groupId]);
        $createdBy = $st->fetchColumn();

        if ($createdBy != $userId) {
            out_json(403, ['status' => 'error', 'message' => 'Only group creator can delete']);
        }

        $pdo->beginTransaction();
        $pdo->prepare("DELETE FROM chat_group_messages WHERE group_id = ?")->execute([$groupId]);
        $pdo->prepare("DELETE FROM chat_group_members WHERE group_id = ?")->execute([$groupId]);
        $pdo->prepare("DELETE FROM chat_group_bans WHERE group_id = ?")->execute([$groupId]);
        $pdo->prepare("DELETE FROM chat_groups WHERE id = ?")->execute([$groupId]);
        $pdo->commit();

        out_json(200, ['status' => 'success', 'message' => 'Group deleted']);
    } elseif ($action === 'clear_my_chat') {
        $groupId = (int) ($input['group_id'] ?? 0);
        if ($groupId <= 0)
            out_json(400, ['status' => 'error', 'message' => 'Invalid group']);

        $stC = $pdo->prepare("SELECT 1 FROM chat_group_members WHERE group_id = ? AND user_id = ?");
        $stC->execute([$groupId, $userId]);
        if (!$stC->fetchColumn())
            out_json(403, ['status' => 'error', 'message' => 'Not a group member']);

        $pdo->prepare("DELETE FROM chat_group_messages WHERE group_id = ? AND sender_id = ?")->execute([$groupId, $userId]);

        out_json(200, ['status' => 'success', 'message' => 'Chat cleared']);
    } elseif ($action === 'get_group_by_username') {
        $username = trim($input['username'] ?? '');
        if ($username === '')
            out_json(400, ['status' => 'error', 'message' => 'Username required']);

        $st = $pdo->prepare("SELECT g.*, 
            (SELECT role FROM chat_group_members WHERE group_id = g.id AND user_id = ?) as my_role,
            (SELECT COUNT(*) FROM chat_group_members WHERE group_id = g.id) as member_count
            FROM chat_groups g WHERE g.username = ?");
        $st->execute([$userId, $username]);
        $group = $st->fetch(PDO::FETCH_ASSOC);

        if (!$group) {
            out_json(404, ['status' => 'error', 'message' => 'Group not found']);
        }

        $group['avatar'] = norm_url($group['avatar'] ?? null);
        out_json(200, ['status' => 'success', 'group' => $group]);
    } elseif ($action === 'get_group') {
        $groupId = (int) ($input['group_id'] ?? 0);
        if ($groupId <= 0)
            out_json(400, ['status' => 'error', 'message' => 'Invalid group']);

        $st = $pdo->prepare("SELECT g.*, 
            (SELECT role FROM chat_group_members WHERE group_id = g.id AND user_id = ?) as my_role,
            (SELECT COUNT(*) FROM chat_group_members WHERE group_id = g.id) as member_count,
            (SELECT COUNT(*) FROM chat_group_members WHERE group_id = g.id AND user_id = ?) as is_member
            FROM chat_groups g WHERE g.id = ?");
        $st->execute([$userId, $userId, $groupId]);
        $group = $st->fetch(PDO::FETCH_ASSOC);

        if (!$group) {
            out_json(404, ['status' => 'error', 'message' => 'Group not found']);
        }

        $defaultPerms = ['can_send_text' => 1, 'can_send_media' => 1, 'can_send_voice' => 1, 'can_send_stickers' => 1];
        $group['permissions'] = $group['permissions'] ? json_decode($group['permissions'], true) : $defaultPerms;
        $group['avatar'] = norm_url($group['avatar'] ?? null);

        out_json(200, ['status' => 'success', 'group' => $group]);
    } elseif ($action === 'track_view') {
        $groupId = (int) ($input['group_id'] ?? 0);
        if ($groupId <= 0)
            out_json(400, ['status' => 'error', 'message' => 'Invalid group']);

        $pdo->prepare("INSERT IGNORE INTO chat_group_views (group_id, user_id) VALUES (?, ?)")->execute([$groupId, $userId]);
        $pdo->prepare("UPDATE chat_groups SET views_count = views_count + 1, last_active = NOW() WHERE id = ?")->execute([$groupId]);

        out_json(200, ['status' => 'success']);
    } elseif ($action === 'get_viewers') {
        $groupId = (int) ($input['group_id'] ?? 0);
        if ($groupId <= 0)
            out_json(400, ['status' => 'error', 'message' => 'Invalid group']);

        $st = $pdo->prepare("
            SELECT u.id, u.name, u.profile_pic as avatar
            FROM chat_group_views v
            JOIN users u ON v.user_id = u.id
            WHERE v.group_id = ?
            ORDER BY v.viewed_at DESC LIMIT 5
        ");
        $st->execute([$groupId]);
        $viewers = $st->fetchAll(PDO::FETCH_ASSOC);

        foreach ($viewers as &$v) {
            $v['avatar'] = norm_url($v['avatar'] ?? null);
        }

        out_json(200, ['status' => 'success', 'viewers' => $viewers]);
    } elseif ($action === 'get_unread_count') {
        $groupId = (int) ($input['group_id'] ?? 0);
        if ($groupId <= 0)
            out_json(400, ['status' => 'error', 'message' => 'Invalid group']);

        $st = $pdo->prepare("SELECT COUNT(*) FROM chat_group_messages WHERE group_id = ? AND sender_id != ?");
        $st->execute([$groupId, $userId]);
        $count = (int) $st->fetchColumn();

        out_json(200, ['status' => 'success', 'unread_count' => $count]);
    } elseif ($action === 'delete_all_groups') {
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
    out_json(500, ['status' => 'error', 'message' => $e->getMessage()]);
}
