<?php
require_once __DIR__ . '/db_connect.php';
header('Content-Type: application/json');

// 1. Check if full_name column exists in users table
$cols = [];
$st = $pdo->query('SHOW COLUMNS FROM users');
while ($r = $st->fetch(PDO::FETCH_ASSOC))
    $cols[] = $r['Field'];

$hasFullName = in_array('full_name', $cols);
$hasAvatar = in_array('avatar', $cols);

// 2. Try the EXACT poll_incoming query for user 13
$error = null;
$result = null;
try {
    $stmt = $pdo->prepare("
        SELECT c.id AS call_id, c.call_uuid, c.type, c.status, c.created_at,
               u.id AS caller_id, u.name AS caller_name, u.full_name AS caller_full_name, u.avatar AS caller_avatar
        FROM calls c
        JOIN users u ON u.id = c.caller_id
        WHERE c.receiver_id = 13 AND c.status = 'ringing'
          AND (UNIX_TIMESTAMP() - UNIX_TIMESTAMP(c.created_at)) < 60
        ORDER BY c.created_at DESC LIMIT 1
    ");
    $stmt->execute();
    $result = $stmt->fetch(PDO::FETCH_ASSOC);
}
catch (Throwable $e) {
    $error = $e->getMessage();
}

// 3. Also try the initiate_call caller query
$callerError = null;
try {
    $cs = $pdo->prepare("SELECT id, name, full_name, avatar FROM users WHERE id=9");
    $cs->execute();
    $callerResult = $cs->fetch(PDO::FETCH_ASSOC);
}
catch (Throwable $e) {
    $callerError = $e->getMessage();
}

echo json_encode([
    'user_columns' => $cols,
    'has_full_name' => $hasFullName,
    'has_avatar' => $hasAvatar,
    'poll_incoming_result' => $result,
    'poll_incoming_error' => $error,
    'caller_query_result' => $callerResult ?? null,
    'caller_query_error' => $callerError,
], JSON_PRETTY_PRINT);
?>
