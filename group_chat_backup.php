<?php
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

// Endpoint configuration
$config = require __DIR__ . '/../../config/config.php';

// Initialization - Create tables if they do not exist
function init_group_chat_tables(PDO $pdo): void {
    $pdo->exec("CREATE TABLE IF NOT EXISTS chat_groups (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        avatar VARCHAR(500) NULL,
        created_by INT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;");

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
        type ENUM('text', 'image', 'system') DEFAULT 'text',
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_group (group_id),
        INDEX idx_created (created_at)
    ) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;");
}

function out_json(int $code, array $payload): void {
    http_response_code($code);
    echo json_encode($payload);
    exit;
}

try {
    $user = requireUser($pdo);
    $userId = (int)$user['id'];

    init_group_chat_tables($pdo);

    $action = $_GET['action'] ?? $_POST['action'] ?? '';
    $input = json_decode(file_get_contents('php://input'), true) ?? [];

    if ($action === 'create') {
        $name = trim($input['name'] ?? '');
        $description = trim($input['description'] ?? '');
        if ($name === '') {
            out_json(400, ['status' => 'error', 'message' => 'Group name required']);
        }
        
        $pdo->beginTransaction();
        $st = $pdo->prepare("INSERT INTO chat_groups (name, created_by) VALUES (?, ?)");
        $st->execute([$name, $userId]);
        $groupId = (int)$pdo->lastInsertId();

        $stMem = $pdo->prepare("INSERT INTO chat_group_members (group_id, user_id, role) VALUES (?, ?, 'admin')");
        $stMem->execute([$groupId, $userId]);

        // System message
        $stMsg = $pdo->prepare("INSERT INTO chat_group_messages (group_id, sender_id, message, type) VALUES (?, ?, ?, 'system')");
        $stMsg->execute([$groupId, $userId, "Group created by " . $user['name']]);
        
        $pdo->commit();
        out_json(200, ['status' => 'success', 'group_id' => $groupId, 'message' => 'Group created']);
    }

    elseif ($action === 'join') {
        $groupId = (int)($input['group_id'] ?? 0);
        if ($groupId <= 0) out_json(400, ['status' => 'error', 'message' => 'Invalid group']);

        $st = $pdo->prepare("INSERT IGNORE INTO chat_group_members (group_id, user_id, role) VALUES (?, ?, 'member')");
        $st->execute([$groupId, $userId]);
        
        if ($st->rowCount() > 0) {
            $stMsg = $pdo->prepare("INSERT INTO chat_group_messages (group_id, sender_id, message, type) VALUES (?, ?, ?, 'system')");
            $stMsg->execute([$groupId, $userId, $user['name'] . " joined the group"]);
        }
        out_json(200, ['status' => 'success']);
    }

    elseif ($action === 'leave') {
        $groupId = (int)($input['group_id'] ?? 0);
        $st = $pdo->prepare("DELETE FROM chat_group_members WHERE group_id = ? AND user_id = ?");
        $st->execute([$groupId, $userId]);
        
        if ($st->rowCount() > 0) {
             $stMsg = $pdo->prepare("INSERT INTO chat_group_messages (group_id, sender_id, message, type) VALUES (?, ?, ?, 'system')");
             $stMsg->execute([$groupId, $userId, $user['name'] . " left the group"]);
        }
        out_json(200, ['status' => 'success']);
    }

    elseif ($action === 'list_all') {
        // List all available groups
        $stmt = $pdo->query("SELECT g.id, g.name, g.avatar, 
            (SELECT COUNT(*) FROM chat_group_members WHERE group_id = g.id) as member_count,
            (SELECT COUNT(*) FROM chat_group_members WHERE group_id = g.id AND user_id = $userId) as is_member
            FROM chat_groups g ORDER BY g.created_at DESC LIMIT 50");
        $groups = $stmt->fetchAll(PDO::FETCH_ASSOC);
        out_json(200, ['status' => 'success', 'groups' => $groups]);
    }

    elseif ($action === 'my_groups') {
        $stmt = $pdo->prepare("
            SELECT g.id, g.name, g.avatar,
            (SELECT message FROM chat_group_messages WHERE group_id = g.id ORDER BY id DESC LIMIT 1) as last_message,
            (SELECT created_at FROM chat_group_messages WHERE group_id = g.id ORDER BY id DESC LIMIT 1) as last_message_time
            FROM chat_groups g
            JOIN chat_group_members m ON g.id = m.group_id
            WHERE m.user_id = ?
            ORDER BY last_message_time DESC
        ");
        $stmt->execute([$userId]);
        $groups = $stmt->fetchAll(PDO::FETCH_ASSOC);
        out_json(200, ['status' => 'success', 'groups' => $groups]);
    }

    elseif ($action === 'send') {
        // POST to send message
        $groupId = (int)($input['group_id'] ?? 0);
        $message = trim($input['message'] ?? '');
        $type = $input['type'] ?? 'text';

        // ensure member
        $stC = $pdo->prepare("SELECT 1 FROM chat_group_members WHERE group_id = ? AND user_id = ?");
        $stC->execute([$groupId, $userId]);
        if (!$stC->fetchColumn()) out_json(403, ['status' => 'error', 'message' => 'Not a group member']);

        if ($message === '' && $type === 'text') {
            out_json(400, ['status' => 'error', 'message' => 'Empty message']);
        }

        $st = $pdo->prepare("INSERT INTO chat_group_messages (group_id, sender_id, message, type) VALUES (?, ?, ?, ?)");
        $st->execute([$groupId, $userId, $message, $type]);
        
        $msgId = $pdo->lastInsertId();
        out_json(200, ['status' => 'success', 'message_id' => $msgId, 'created_at' => gmdate('Y-m-d H:i:s')]);
    }

    elseif ($action === 'sync') {
        // Fetch messages for a group
        $groupId = (int)($_GET['group_id'] ?? 0);
        $lastId = (int)($_GET['last_id'] ?? 0);

        // ensure member
        $stC = $pdo->prepare("SELECT 1 FROM chat_group_members WHERE group_id = ? AND user_id = ?");
        $stC->execute([$groupId, $userId]);
        if (!$stC->fetchColumn()) out_json(403, ['status' => 'error', 'message' => 'Not a group member']);

        $st = $pdo->prepare("
            SELECT m.id, m.sender_id, m.message, m.type, m.created_at,
                   u.name as sender_name, u.profile_pic as sender_avatar
            FROM chat_group_messages m
            LEFT JOIN users u ON m.sender_id = u.id
            WHERE m.group_id = ? AND m.id > ?
            ORDER BY m.id DESC LIMIT 50
        ");
        $st->execute([$groupId, $lastId]);
        $messages = array_reverse($st->fetchAll(PDO::FETCH_ASSOC));

        out_json(200, ['status' => 'success', 'messages' => $messages]);
    }

    else {
        out_json(400, ['status' => 'error', 'message' => 'Unknown action']);
    }

} catch (Exception $e) {
    out_json(500, ['status' => 'error', 'message' => $e->getMessage()]);
}
