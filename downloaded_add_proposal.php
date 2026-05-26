<?php
error_reporting(E_ALL);

ini_set('display_errors', 1);
header("Content-Type: application/json");

// 1. Direct Database Connection 
$host = 'localhost';
$db = 'sharexhu_dbeklo';
$user = 'sharexhu_dbeklo';
$pass = 'BMVRgNZPyUTAFP2E36bc';
$charset = 'utf8mb4';

$dsn = "mysql:host=$host;dbname=$db;charset=$charset";
$options = [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_EMULATE_PREPARES => false,
];

try {
    $pdo = new PDO($dsn, $user, $pass, $options);
}
catch (\PDOException $e) {
    echo json_encode(["status" => "error", "message" => "Database Connection Failed: " . $e->getMessage()]);
    exit;
}

if (!isset($_GET['user_id'])) {
    echo json_encode(["status" => "error", "message" => "Missing target user_id"]);
    exit;
}

$userIdToReceiveProposal = (int)$_GET['user_id'];

try {
    // 2. Add +1 to their total proposals using PDO
    $incrementSql = "UPDATE users SET total_proposals = total_proposals + 1 WHERE id = ?";
    $stmt = $pdo->prepare($incrementSql);
    $stmt->execute([$userIdToReceiveProposal]);

    require_once __DIR__ . '/notification_helper.php';
    $senderId = (int)($_GET['sender_id'] ?? $_POST['sender_id'] ?? 0);
    send_app_notification($pdo, $userIdToReceiveProposal, $senderId, 'proposal', 'New Proposal', 'You have received a new match proposal!');

    echo json_encode([
        "status" => "success",
        "message" => "Proposal count increased for user $userIdToReceiveProposal!"
    ]);
}
catch (\PDOException $e) {
    echo json_encode(["status" => "error", "message" => "SQL Error: " . $e->getMessage()]);
    exit;
}
?>
