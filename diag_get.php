<?php
require_once __DIR__ . '/config.php';
$userId = 9;

// Fetch sent proposals exactly as get_proposals does
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
$proposals = $stmt->fetchAll(PDO::FETCH_ASSOC);

// Also fetch raw proposals unconditionally to see the raw database state
$raw = $pdo->prepare("SELECT id, sender_id, receiver_id, status FROM proposals WHERE sender_id = ? OR receiver_id = ?");
$raw->execute([$userId, $userId]);
$raw_proposals = $raw->fetchAll(PDO::FETCH_ASSOC);

file_put_contents(__DIR__ . '/diag_out.json', json_encode([
    'sent_proposals' => $proposals,
    'raw_proposals' => $raw_proposals
], JSON_PRETTY_PRINT));
echo "Done";
