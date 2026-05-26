<?php
require_once __DIR__ . '/config.php';
$userId = 9; // Hardcoded user ID based on logs

$out = [];
try {
    $stmt = $pdo->prepare("
        SELECT p.id as proposal_id, p.receiver_id, p.status, p.created_at, p.show_on_profile, p.is_read,
               u.name as receiver_name, u.profile_pic as receiver_avatar,
               m.age, m.gender, m.bio
        FROM proposals p
        JOIN users u ON u.id = p.receiver_id
        LEFT JOIN match_profiles m ON m.user_id = p.receiver_id
        LEFT JOIN user_blocks ub ON (ub.blocker_id = ? AND ub.blocked_id = p.receiver_id)
        WHERE p.sender_id = ? AND p.status IN ('pending', 'accepted')
          AND ub.id IS NULL
        ORDER BY p.status ASC, p.created_at DESC
    ");
    $stmt->execute([$userId, $userId]);
    $out['sent_proposals'] = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Let's also fetch current proposals state
    $diagSt = $pdo->prepare("SELECT id, sender_id, receiver_id, status FROM proposals WHERE sender_id = ? OR receiver_id = ?");
    $diagSt->execute([$userId, $userId]);
    $out['all_proposals'] = $diagSt->fetchAll(PDO::FETCH_ASSOC);

    $out['status'] = 'success';
} catch (Exception $e) {
    $out['status'] = 'error';
    $out['message'] = $e->getMessage();
}

file_put_contents(__DIR__ . '/diag_out.json', json_encode($out, JSON_PRETTY_PRINT));
echo "Done";
