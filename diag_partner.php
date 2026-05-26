<?php
require_once __DIR__ . '/config.php';
$userId = 9;

$out = [];
try {
    // Check proposals table for this user
    $st = $pdo->prepare("SELECT id, status, show_on_profile FROM proposals WHERE sender_id = ? OR receiver_id = ?");
    $st->execute([$userId, $userId]);
    $out['proposals'] = $st->fetchAll(PDO::FETCH_ASSOC);

    $out['status'] = 'success';
} catch (Exception $e) {
    $out['status'] = 'error';
    $out['message'] = $e->getMessage();
}

file_put_contents(__DIR__ . '/diag_partner.json', json_encode($out, JSON_PRETTY_PRINT));
echo "Done";
