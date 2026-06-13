<?php
require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/notification_helper.php';

$radiusKm   = 3.0;    // real "nearby" radius (was 50km)
$pairCdSec  = 7200;   // don't re-alert the SAME person for 2h (kills spam)
$maxAgeMins = 30;     // only consider locations updated in the last 30 min

// Per-pair alert log so a user isn't spammed about the same nearby person.
$pdo->exec("CREATE TABLE IF NOT EXISTS nearby_alert_log (
    user_id INT NOT NULL, other_id INT NOT NULL, last_sent DATETIME NOT NULL,
    PRIMARY KEY (user_id, other_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$stmt = $pdo->query("
    SELECT a.user_id uid_a, b.user_id uid_b,
           ua.name name_a, COALESCE(ua.privacy_share_distance,0) share_a,
           ub.name name_b, COALESCE(ub.privacy_share_distance,0) share_b,
           COALESCE(ua.privacy_nearby_alert,1) alert_a,
           COALESCE(ub.privacy_nearby_alert,1) alert_b,
           (6371*acos(GREATEST(-1,LEAST(1,cos(radians(a.lat))*cos(radians(b.lat))*cos(radians(b.lng)-radians(a.lng))+sin(radians(a.lat))*sin(radians(b.lat)))))) dist_km
    FROM match_profiles a
    JOIN match_profiles b ON b.user_id > a.user_id
    JOIN users ua ON ua.id=a.user_id
    JOIN users ub ON ub.id=b.user_id
    WHERE a.is_visible=1 AND b.is_visible=1
      AND ua.is_banned=0 AND ub.is_banned=0
      AND COALESCE(ua.privacy_nearby_visible,1)=1
      AND COALESCE(ub.privacy_nearby_visible,1)=1
      AND a.lat IS NOT NULL AND b.lat IS NOT NULL
      AND a.last_location_update >= DATE_SUB(UTC_TIMESTAMP(), INTERVAL $maxAgeMins MINUTE)
      AND b.last_location_update >= DATE_SUB(UTC_TIMESTAMP(), INTERVAL $maxAgeMins MINUTE)
      AND NOT EXISTS(SELECT 1 FROM proposals p WHERE ((p.sender_id=a.user_id AND p.receiver_id=b.user_id) OR (p.sender_id=b.user_id AND p.receiver_id=a.user_id)) AND p.status='accepted')
      AND NOT EXISTS(SELECT 1 FROM user_blocks bl WHERE (bl.blocker_id=a.user_id AND bl.blocked_id=b.user_id) OR (bl.blocker_id=b.user_id AND bl.blocked_id=a.user_id))
      AND ua.gender IS NOT NULL AND ua.gender != ''
      AND ub.gender IS NOT NULL AND ub.gender != ''
      AND LOWER(ua.gender) != LOWER(ub.gender)
    HAVING dist_km <= $radiusKm
    ORDER BY dist_km ASC
    LIMIT 200
");
$pairs = $stmt->fetchAll(PDO::FETCH_ASSOC);

$chk = $pdo->prepare("SELECT TIMESTAMPDIFF(SECOND, last_sent, UTC_TIMESTAMP()) FROM nearby_alert_log WHERE user_id=? AND other_id=?");
$log = $pdo->prepare("INSERT INTO nearby_alert_log (user_id, other_id, last_sent) VALUES (?,?,UTC_TIMESTAMP()) ON DUPLICATE KEY UPDATE last_sent=UTC_TIMESTAMP()");

$sent = 0;
$notified = [];  // per-run: each user gets at most ONE nearby alert per run

function recently_alerted($chk, $a, $b, $cd) {
    $chk->execute([$a, $b]);
    $secs = $chk->fetchColumn();
    return ($secs !== false && (int)$secs < $cd);
}

foreach ($pairs as $p) {
    $dm = round($p['dist_km'] * 1000);
    if ($p['alert_a'] && !isset($notified[$p['uid_a']]) && !recently_alerted($chk, $p['uid_a'], $p['uid_b'], $pairCdSec)) {
        $body = $p['share_b'] ? "{$p['name_b']} is about {$dm}m away." : "{$p['name_b']} is nearby!";
        send_app_notification($pdo,(int)$p['uid_a'],(int)$p['uid_b'],'nearby','Someone is nearby!',$body,null,false);
        $log->execute([$p['uid_a'], $p['uid_b']]);
        $notified[$p['uid_a']] = true; $sent++;
    }
    if ($p['alert_b'] && !isset($notified[$p['uid_b']]) && !recently_alerted($chk, $p['uid_b'], $p['uid_a'], $pairCdSec)) {
        $body = $p['share_a'] ? "{$p['name_a']} is about {$dm}m away." : "{$p['name_a']} is nearby!";
        send_app_notification($pdo,(int)$p['uid_b'],(int)$p['uid_a'],'nearby','Someone is nearby!',$body,null,false);
        $log->execute([$p['uid_b'], $p['uid_a']]);
        $notified[$p['uid_b']] = true; $sent++;
    }
}
echo date('Y-m-d H:i:s')." pairs=".count($pairs)." sent=$sent\n";
