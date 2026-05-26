<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

ini_set('display_errors', '1');
error_reporting(E_ALL);

function json_out($code, $arr)
{
    http_response_code($code);
    echo json_encode($arr);
    exit;
}

// Quick check DB connection
require_once __DIR__ . '/db_connect.php';

if (!isset($pdo)) {
    json_out(500, ['status' => 'error', 'message' => 'Database connection failed']);
}

// ── SETUP TABLES ──
try {
    $sql = "CREATE TABLE IF NOT EXISTS match_profiles (
        user_id INT NOT NULL PRIMARY KEY,
        gender VARCHAR(20) DEFAULT 'male',
        age INT NULL,
        location VARCHAR(255) NULL,
        bio TEXT NULL,
        income VARCHAR(100) NULL,
        income_status VARCHAR(50) DEFAULT 'none',
        interests TEXT NULL,
        qualities TEXT NULL,
        looking_for TEXT NULL,
        is_visible TINYINT(1) DEFAULT 1,
        cover_pic VARCHAR(500) NULL,
        profile_pic VARCHAR(500) NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;";
    $pdo->exec($sql);

    // Table for bank statements
    $sql2 = "CREATE TABLE IF NOT EXISTS income_proofs (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        file_url VARCHAR(500) NOT NULL,
        status VARCHAR(50) DEFAULT 'pending',
        uploaded_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;";
    $pdo->exec($sql2);
}
catch (PDOException $e) {
    // Ignore error if `users` table isn't created yet or other FK issues
    // Just in case, we create without FK if it fails
    try {
        $pdo->exec("CREATE TABLE IF NOT EXISTS match_profiles (
            user_id INT NOT NULL PRIMARY KEY,
            gender VARCHAR(20) DEFAULT 'male',
            age INT NULL,
            location VARCHAR(255) NULL,
            bio TEXT NULL,
            income VARCHAR(100) NULL,
            income_status VARCHAR(50) DEFAULT 'none',
            interests TEXT NULL,
            qualities TEXT NULL,
            looking_for TEXT NULL,
            is_visible TINYINT(1) DEFAULT 1,
            cover_pic VARCHAR(500) NULL,
            profile_pic VARCHAR(500) NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;");

        $pdo->exec("CREATE TABLE IF NOT EXISTS income_proofs (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            file_url VARCHAR(500) NOT NULL,
            status VARCHAR(50) DEFAULT 'pending',
            uploaded_at DATETIME DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;");
    }
    catch (PDOException $e2) {
    // give up on table creation silently
    }
}

// ── FORCE ADD COLUMNS IF THEY DON'T EXIST ──
try {
    $colsToAdd = [
        "gender" => "VARCHAR(20) DEFAULT 'male'",
        "age" => "INT NULL",
        "location" => "VARCHAR(255) NULL",
        "bio" => "TEXT NULL",
        "income" => "VARCHAR(100) NULL",
        "income_status" => "VARCHAR(50) DEFAULT 'none'",
        "interests" => "TEXT NULL",
        "qualities" => "TEXT NULL",
        "looking_for" => "TEXT NULL",
        "is_visible" => "TINYINT(1) DEFAULT 1",
        "cover_pic" => "VARCHAR(500) NULL",
        "profile_pic" => "VARCHAR(500) NULL"
    ];
    $stmt = $pdo->query("SHOW COLUMNS FROM match_profiles");
    $existingCols = [];
    while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {
        $existingCols[] = $row['Field'];
    }
    foreach ($colsToAdd as $col => $def) {
        if (!in_array($col, $existingCols)) {
            $pdo->exec("ALTER TABLE match_profiles ADD COLUMN $col $def");
        }
    }
}
catch (PDOException $e) { /* ignore */
}

$action = $_POST['action'] ?? $_GET['action'] ?? '';

// GET MY MATCH PROFILE
if ($action === 'get_my_profile' && $_SERVER['REQUEST_METHOD'] === 'GET') {
    $userId = $_GET['user_id'] ?? 0;
    if (!$userId)
        json_out(400, ['status' => 'error', 'message' => 'user_id required']);

    $stmt = $pdo->prepare("SELECT * FROM match_profiles WHERE user_id = ?");
    $stmt->execute([$userId]);
    $profile = $stmt->fetch(PDO::FETCH_ASSOC);

    if ($profile) {
        $profile['interests'] = $profile['interests'] ? explode(',', $profile['interests']) : [];
        $profile['qualities'] = $profile['qualities'] ? explode(',', $profile['qualities']) : [];
        $profile['looking_for'] = $profile['looking_for'] ? explode(',', $profile['looking_for']) : [];
        $profile['is_visible'] = (int)$profile['is_visible'];
        
        // Fetch public partner if they have shown it on their profile
        $partnerStmt = $pdo->prepare("
            SELECT CASE WHEN p.sender_id = ? THEN p.receiver_id ELSE p.sender_id END as partner_id,
                   u.name as partner_name, u.profile_pic as partner_avatar,
                   m.gender as partner_gender
            FROM proposals p
            JOIN users u ON u.id = CASE WHEN p.sender_id = ? THEN p.receiver_id ELSE p.sender_id END
            LEFT JOIN match_profiles m ON m.user_id = u.id
            WHERE (p.sender_id = ? OR p.receiver_id = ?) AND p.status = 'accepted' AND p.show_on_profile = 1
            LIMIT 1
        ");
        $partnerStmt->execute([$userId, $userId, $userId, $userId]);
        $partner = $partnerStmt->fetch(PDO::FETCH_ASSOC);
        if ($partner) {
            $profile['public_partner'] = $partner;
        }
    }

    json_out(200, ['status' => 'success', 'profile' => $profile]);
}

// SAVE MATCH PROFILE
// --- DEBUG INCOMING ACTION ---
file_put_contents(__DIR__ . '/match_debug.log', date('Y-m-d H:i:s') . "\nACTION: " . $action . "\nMETHOD: " . $_SERVER['REQUEST_METHOD'] . "\nPOST: " . print_r($_POST, true) . "\nGET: " . print_r($_GET, true) . "\n\n", FILE_APPEND);
// -----------------------------

if ($action === 'save' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    $userId = $_POST['user_id'] ?? 0;
    if (!$userId)
        json_out(400, ['status' => 'error', 'message' => 'user_id required']);

    // Parse fields
    $interests = $_POST['interests'] ?? '';
    $qualities = $_POST['qualities'] ?? '';
    $lookingFor = $_POST['looking_for'] ?? '';
    $age = !empty($_POST['age']) ? (int)$_POST['age'] : null;
    $location = $_POST['location'] ?? '';
    $bio = $_POST['bio'] ?? '';
    $gender = $_POST['gender'] ?? 'male';
    $income = $_POST['income'] ?? '';
    $isVisible = isset($_POST['is_visible']) ? (int)$_POST['is_visible'] : 1;

    // Helper: File Upload
    function uploadFile($fileField)
    {
        if (!isset($_FILES[$fileField]) || $_FILES[$fileField]['error'] !== UPLOAD_ERR_OK) {
            return null;
        }
        $dir = __DIR__ . '/uploads/match_profiles/';
        if (!is_dir($dir))
            @mkdir($dir, 0777, true);

        $ext = strtolower(pathinfo($_FILES[$fileField]['name'], PATHINFO_EXTENSION));
        $allowed = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];
        if (!in_array($ext, $allowed))
            return null;

        $filename = uniqid('img_') . '.' . $ext;
        $dest = $dir . $filename;
        if (move_uploaded_file($_FILES[$fileField]['tmp_name'], $dest)) {
            // Return public URL relative to api/v1
            return 'uploads/match_profiles/' . $filename;
        }
        return null;
    }

    $profilePic = uploadFile('profile_pic');
    $coverPic = uploadFile('cover_pic');

    // Build Upsert Query
    $data = [
        'user_id' => $userId,
        'gender' => $gender,
        'age' => $age,
        'location' => $location,
        'bio' => $bio,
        'income' => $income,
        'interests' => $interests,
        'qualities' => $qualities,
        'looking_for' => $lookingFor,
        'is_visible' => $isVisible
    ];

    $fields = array_keys($data);

    // Add images if uploaded
    if ($profilePic) {
        $fields[] = 'profile_pic';
        $data['profile_pic'] = $profilePic;
    }
    if ($coverPic) {
        $fields[] = 'cover_pic';
        $data['cover_pic'] = $coverPic;
    }

    // Check if new income proofs uploaded
    $proof1 = uploadFile('income_proof_1');
    $proof2 = uploadFile('income_proof_2');
    $proof3 = uploadFile('income_proof_3');

    $hasNewProofs = ($proof1 || $proof2 || $proof3);
    $chk = $pdo->prepare("SELECT income, income_status FROM match_profiles WHERE user_id = ?");
    $chk->execute([$userId]);
    $existing = $chk->fetch(PDO::FETCH_ASSOC);

    $oldIncomeNum = $existing ? (float)$existing['income'] : 0.0;
    $oldStatus = $existing ? $existing['income_status'] : 'none';

    $incomeChanged = false;
    if ($income !== '') {
        $incomeNum = (float)$income;
        if ($incomeNum != $oldIncomeNum && $oldStatus === 'verified') {
            $incomeChanged = true;
        }
    }

    if ($hasNewProofs || $incomeChanged) {
        $fields[] = 'income_status';
        $data['income_status'] = 'pending';
        // Clear existing pending proofs since they're uploading/submitting a new iteration
        $clearPending = $pdo->prepare("DELETE FROM income_proofs WHERE user_id = ? AND status = 'pending'");
        $clearPending->execute([$userId]);
    }

    $placeholders = implode(', ', array_fill(0, count($fields), '?'));
    $updateFields = [];
    foreach ($fields as $f) {
        if ($f !== 'user_id') {
            $updateFields[] = "$f = VALUES($f)";
        }
    }

    $sql = "INSERT INTO match_profiles (" . implode(', ', $fields) . ") 
            VALUES ($placeholders) 
            ON DUPLICATE KEY UPDATE " . implode(', ', $updateFields);

    $stmt = $pdo->prepare($sql);
    $values = array_values($data);
    $stmt->execute($values);

    // Save income proofs
    $proofs = array_filter([$proof1, $proof2, $proof3]);
    if (!empty($proofs)) {
        $stmtProof = $pdo->prepare("INSERT INTO income_proofs (user_id, file_url) VALUES (?, ?)");
        foreach ($proofs as $p) {
            $stmtProof->execute([$userId, $p]);
        }
    }

    json_out(200, ['status' => 'success', 'message' => 'Profile saved']);
}

// CANCEL INCOME REVIEW
if ($action === 'cancel_income_review' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    $userId = $_POST['user_id'] ?? 0;
    if (!$userId) {
        json_out(400, ['status' => 'error', 'message' => 'user_id required']);
    }

    try {
        $pdo->beginTransaction();

        // Delete pending proofs
        $stmtDel = $pdo->prepare("DELETE FROM income_proofs WHERE user_id = ? AND status = 'pending'");
        $stmtDel->execute([$userId]);

        // Reset income status on match profile
        $stmtUpdate = $pdo->prepare("UPDATE match_profiles SET income_status = 'none' WHERE user_id = ?");
        $stmtUpdate->execute([$userId]);

        $pdo->commit();
        json_out(200, ['status' => 'success', 'message' => 'Income review cancelled successfully.']);
    }
    catch (Exception $e) {
        $pdo->rollBack();
        json_out(500, ['status' => 'error', 'message' => 'Failed to cancel review: ' . $e->getMessage()]);
    }
}
// UPDATE LOCATION (Nearby Proximity Notifications)
if ($action === 'update_location' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    // Get current user from auth middleware
    require_once __DIR__ . '/auth_middleware.php';
    try {
        $viewer = requireUser($pdo);
        $userId = (int)$viewer['id'];
    } catch (Throwable $e) {
        json_out(401, ['status' => 'error', 'message' => 'Unauthorized']);
    }

    $raw = file_get_contents('php://input');
    $body = json_decode($raw, true) ?? $_POST;
    $lat = isset($body['lat']) ? floatval($body['lat']) : null;
    $lng = isset($body['lng']) ? floatval($body['lng']) : null;

    if ($lat === null || $lng === null) {
        json_out(400, ['status' => 'error', 'message' => 'lat and lng required']);
    }

    // Ensure lat/lng columns exist on match_profiles
    try {
        $cols = [];
        $colStmt = $pdo->query("SHOW COLUMNS FROM match_profiles");
        while ($r = $colStmt->fetch(PDO::FETCH_ASSOC)) $cols[] = $r['Field'];
        if (!in_array('lat', $cols)) $pdo->exec("ALTER TABLE match_profiles ADD COLUMN lat DOUBLE NULL");
        if (!in_array('lng', $cols)) $pdo->exec("ALTER TABLE match_profiles ADD COLUMN lng DOUBLE NULL");
        if (!in_array('last_location_update', $cols)) $pdo->exec("ALTER TABLE match_profiles ADD COLUMN last_location_update DATETIME NULL");
        if (!in_array('last_nearby_notif', $cols)) $pdo->exec("ALTER TABLE match_profiles ADD COLUMN last_nearby_notif DATETIME NULL");
    } catch (Throwable $e) { /* ignore */ }

    // Upsert this user's location
    $pdo->prepare("INSERT INTO match_profiles (user_id, lat, lng, last_location_update)
        VALUES (?, ?, ?, NOW())
        ON DUPLICATE KEY UPDATE lat = VALUES(lat), lng = VALUES(lng), last_location_update = NOW()")
        ->execute([$userId, $lat, $lng]);

    // --- NEARBY PROXIMITY CHECK ---
    // Find other visible users within ~1 km using Haversine, updated in last 15 min
    $radiusKm = 1.0;
    $nearbyStmt = $pdo->prepare("
        SELECT mp.user_id, mp.lat, mp.lng, mp.last_nearby_notif,
               u.name, u.username, u.profile_pic,
               (6371 * acos(
                   cos(radians(?)) * cos(radians(mp.lat)) *
                   cos(radians(mp.lng) - radians(?)) +
                   sin(radians(?)) * sin(radians(mp.lat))
               )) AS distance_km,
               TIMESTAMPDIFF(SECOND, mp.last_nearby_notif, NOW()) AS sec_since_notif
        FROM match_profiles mp
        JOIN users u ON u.id = mp.user_id
        WHERE mp.user_id != ?
          AND mp.is_visible = 1
          AND mp.lat IS NOT NULL
          AND mp.lng IS NOT NULL
          AND mp.last_location_update >= DATE_SUB(NOW(), INTERVAL 30 MINUTE)
          AND NOT EXISTS (
              SELECT 1 FROM proposals p2 
              WHERE ((p2.sender_id = mp.user_id AND p2.receiver_id = ?) 
                  OR (p2.receiver_id = mp.user_id AND p2.sender_id = ?))
              AND p2.status = 'accepted'
          )
          AND NOT EXISTS (
              SELECT 1 FROM user_blocks b
              WHERE (b.blocker_id = ? AND b.blocked_id = mp.user_id)
                 OR (b.blocker_id = mp.user_id AND b.blocked_id = ?)
          )
        HAVING distance_km <= ?
        ORDER BY distance_km ASC
        LIMIT 10
    ");
    $nearbyStmt->execute([$lat, $lng, $lat, $userId, $userId, $userId, $userId, $userId, $radiusKm]);
    $nearbyUsers = $nearbyStmt->fetchAll(PDO::FETCH_ASSOC);

    // Send notifications (with cooldown: don't spam same person within 15 min)
    if (!empty($nearbyUsers)) {
        require_once __DIR__ . '/notification_helper.php';

        // Get current user name for the notification
        $meStmt = $pdo->prepare("SELECT name, username FROM users WHERE id = ?");
        $meStmt->execute([$userId]);
        $me = $meStmt->fetch(PDO::FETCH_ASSOC);
        $myName = $me['name'] ?: $me['username'] ?: 'Someone';

        // Check current user cooldown using a DB query to avoid timezone issues
        $myNotifStmt = $pdo->prepare("SELECT TIMESTAMPDIFF(SECOND, last_nearby_notif, NOW()) as my_sec FROM match_profiles WHERE user_id = ?");
        $myNotifStmt->execute([$userId]);
        $mySecData = $myNotifStmt->fetch();
        $mySecSince = ($mySecData && $mySecData['my_sec'] !== null) ? (int)$mySecData['my_sec'] : 999999;
        
        // If current user themselves was notified recently (e.g. within 60 seconds), we can either skip their outgoing ping or just let it send to the other person.
        // Let's only send to the other person if the other person is off cooldown.

        foreach ($nearbyUsers as $nearby) {
            $nearbyUid = (int)$nearby['user_id'];
            $distMeters = round($nearby['distance_km'] * 1000);

            // Cooldown check: skip if we already notified this pair within 1 min (testing)
            $secSince = $nearby['sec_since_notif'];
            if ($secSince !== null && $secSince < 60) {
                continue;
            }

            // Send notification to the nearby user
            // forceDataOnly = false so FCM includes a visible notification payload
            // that Android can display in the system tray when the app is closed/killed
            $title = '📍 Someone is nearby!';
            $body = "$myName is about {$distMeters}m away from you right now.";
            send_app_notification($pdo, $nearbyUid, $userId, 'nearby', $title, $body, null, false);

            // Also notify the current user about the nearby person
            $theirName = $nearby['name'] ?: $nearby['username'] ?: 'Someone';
            $title2 = '📍 Someone is nearby!';
            $body2 = "$theirName is about {$distMeters}m away from you right now.";
            send_app_notification($pdo, $userId, $nearbyUid, 'nearby', $title2, $body2, null, false);

            // Update cooldown for both
            $pdo->prepare("UPDATE match_profiles SET last_nearby_notif = NOW() WHERE user_id = ?")->execute([$nearbyUid]);
        }
        // Update cooldown for current user
        $pdo->prepare("UPDATE match_profiles SET last_nearby_notif = NOW() WHERE user_id = ?")->execute([$userId]);
    }

    json_out(200, [
        'status' => 'success',
        'message' => 'Location updated',
        'nearby_count' => count($nearbyUsers)
    ]);
}

// SET VISIBILITY
if ($action === 'set_visibility' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    require_once __DIR__ . '/auth_middleware.php';
    try {
        $viewer = requireUser($pdo);
        $userId = (int)$viewer['id'];
    } catch (Throwable $e) {
        json_out(401, ['status' => 'error', 'message' => 'Unauthorized']);
    }

    $raw = file_get_contents('php://input');
    $body = json_decode($raw, true) ?? $_POST;
    $visible = isset($body['is_visible']) ? (int)$body['is_visible'] : 1;

    $pdo->prepare("INSERT INTO match_profiles (user_id, is_visible) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE is_visible = VALUES(is_visible)")
        ->execute([$userId, $visible]);

    json_out(200, ['status' => 'success', 'message' => 'Visibility updated']);
}

// FEED (paginated match profiles for carousel)
if ($action === 'feed' && $_SERVER['REQUEST_METHOD'] === 'GET') {
    require_once __DIR__ . '/auth_middleware.php';
    try {
        $viewer = requireUser($pdo);
        $userId = (int)$viewer['id'];
    } catch (Throwable $e) {
        json_out(401, ['status' => 'error', 'message' => 'Unauthorized']);
    }

    $page = max(1, (int)($_GET['page'] ?? 1));
    $limit = 20;
    $offset = ($page - 1) * $limit;

    $stmt = $pdo->prepare("
        SELECT mp.*, u.name, u.username, u.profile_pic as user_avatar,
               (
                   SELECT JSON_OBJECT(
                       'partner_id', u2.id,
                       'partner_name', u2.name,
                       'partner_avatar', u2.profile_pic,
                       'partner_gender', m2.gender
                   )
                   FROM proposals p
                   JOIN users u2 ON u2.id = CASE WHEN p.sender_id = mp.user_id THEN p.receiver_id ELSE p.sender_id END
                   LEFT JOIN match_profiles m2 ON m2.user_id = u2.id
                   WHERE (p.sender_id = mp.user_id OR p.receiver_id = mp.user_id) AND p.status = 'accepted' AND p.show_on_profile = 1
                   LIMIT 1
               ) as public_partner_json
        FROM match_profiles mp
        JOIN users u ON u.id = mp.user_id
        WHERE mp.user_id != ? AND mp.is_visible = 1
          AND NOT EXISTS (
              SELECT 1 FROM user_blocks b
              WHERE (b.blocker_id = ? AND b.blocked_id = mp.user_id)
                 OR (b.blocker_id = mp.user_id AND b.blocked_id = ?)
          )
        ORDER BY mp.user_id DESC
        LIMIT " . (int)$limit . " OFFSET " . (int)$offset . "
    ");
    $stmt->execute([$userId, $userId, $userId]);
    $profiles = $stmt->fetchAll(PDO::FETCH_ASSOC);

    foreach ($profiles as &$p) {
        $p['interests'] = $p['interests'] ? explode(',', $p['interests']) : [];
        $p['qualities'] = $p['qualities'] ? explode(',', $p['qualities']) : [];
        $p['looking_for'] = $p['looking_for'] ? explode(',', $p['looking_for']) : [];
        if (!empty($p['public_partner_json'])) {
            $p['public_partner'] = json_decode($p['public_partner_json'], true);
        }
        unset($p['public_partner_json']);
    }

    json_out(200, ['status' => 'success', 'profiles' => $profiles]);
}

// NEARBY (fetch nearby profiles by distance)
if ($action === 'nearby' && $_SERVER['REQUEST_METHOD'] === 'GET') {
    $userId = $_GET['user_id'] ?? 0;
    $lat = isset($_GET['lat']) && $_GET['lat'] !== '' ? floatval($_GET['lat']) : null;
    $lng = isset($_GET['lng']) && $_GET['lng'] !== '' ? floatval($_GET['lng']) : null;
    $gender = isset($_GET['gender']) && $_GET['gender'] !== '' ? $_GET['gender'] : null;
    $page = max(1, (int)($_GET['page'] ?? 1));
    $limit = 20;
    $offset = ($page - 1) * $limit;

    if (!$userId) {
        json_out(400, ['status' => 'error', 'message' => 'user_id required']);
    }

    $hasLocation = ($lat !== null && $lng !== null && $lat != 0 && $lng != 0);

    if ($hasLocation) {
        $sql = "
            SELECT mp.*, u.name, u.username, u.profile_pic as user_avatar,
                   (6371 * acos(
                       cos(radians(?)) * cos(radians(mp.lat)) *
                       cos(radians(mp.lng) - radians(?)) +
                       sin(radians(?)) * sin(radians(mp.lat))
                   )) AS distance_km,
                   (
                       SELECT JSON_OBJECT(
                           'partner_id', u2.id,
                           'partner_name', u2.name,
                           'partner_avatar', u2.profile_pic,
                           'partner_gender', m2.gender
                       )
                       FROM proposals p
                       JOIN users u2 ON u2.id = CASE WHEN p.sender_id = mp.user_id THEN p.receiver_id ELSE p.sender_id END
                       LEFT JOIN match_profiles m2 ON m2.user_id = u2.id
                       WHERE (p.sender_id = mp.user_id OR p.receiver_id = mp.user_id) AND p.status = 'accepted' AND p.show_on_profile = 1
                       LIMIT 1
                   ) as public_partner_json
            FROM match_profiles mp
            JOIN users u ON u.id = mp.user_id
            WHERE mp.user_id != ?
              AND mp.is_visible = 1
              AND mp.lat IS NOT NULL AND mp.lng IS NOT NULL";
        $params = [$lat, $lng, $lat, $userId];
    } else {
        $sql = "
            SELECT mp.*, u.name, u.username, u.profile_pic as user_avatar,
                   NULL AS distance_km,
                   (
                       SELECT JSON_OBJECT(
                           'partner_id', u2.id,
                           'partner_name', u2.name,
                           'partner_avatar', u2.profile_pic,
                           'partner_gender', m2.gender
                       )
                       FROM proposals p
                       JOIN users u2 ON u2.id = CASE WHEN p.sender_id = mp.user_id THEN p.receiver_id ELSE p.sender_id END
                       LEFT JOIN match_profiles m2 ON m2.user_id = u2.id
                       WHERE (p.sender_id = mp.user_id OR p.receiver_id = mp.user_id) AND p.status = 'accepted' AND p.show_on_profile = 1
                       LIMIT 1
                   ) as public_partner_json
            FROM match_profiles mp
            JOIN users u ON u.id = mp.user_id
            WHERE mp.user_id != ?
              AND mp.is_visible = 1";
        $params = [$userId];
    }

    if ($gender) {
        $sql .= " AND mp.gender = ?";
        $params[] = $gender;
    }

    $sql .= "
          AND NOT EXISTS (
              SELECT 1 FROM proposals p2 
              WHERE ((p2.sender_id = mp.user_id AND p2.receiver_id = ?) 
                  OR (p2.receiver_id = mp.user_id AND p2.sender_id = ?))
              AND p2.status = 'accepted'
          )
          AND NOT EXISTS (
              SELECT 1 FROM user_blocks b
              WHERE (b.blocker_id = ? AND b.blocked_id = mp.user_id)
                 OR (b.blocker_id = mp.user_id AND b.blocked_id = ?)
          )";
    $params[] = $userId;
    $params[] = $userId;
    $params[] = $userId;
    $params[] = $userId;

    if ($hasLocation) {
        $sql .= " HAVING distance_km <= 50 ORDER BY distance_km ASC";
    } else {
        $sql .= " ORDER BY mp.rating DESC, mp.user_id DESC";
    }

    $sql .= " LIMIT " . (int)$limit . " OFFSET " . (int)$offset;

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $profiles = $stmt->fetchAll(PDO::FETCH_ASSOC);

    foreach ($profiles as &$p) {
        $p['interests'] = $p['interests'] ? explode(',', $p['interests']) : [];
        $p['qualities'] = $p['qualities'] ? explode(',', $p['qualities']) : [];
        $p['looking_for'] = $p['looking_for'] ? explode(',', $p['looking_for']) : [];
        if (!empty($p['public_partner_json'])) {
            $p['public_partner'] = json_decode($p['public_partner_json'], true);
        }
        unset($p['public_partner_json']);
        
        // Use user_avatar as profile_pic fallback if match profile_pic is empty
        if (empty($p['profile_pic']) && !empty($p['user_avatar'])) {
            $p['profile_pic'] = $p['user_avatar'];
        }
    }

    json_out(200, ['status' => 'success', 'profiles' => $profiles]);
}

// REACT (like/reject/follow)
if ($action === 'react' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    // Stub - accepts and returns success
    json_out(200, ['status' => 'success']);
}

// RANDOM CALL
if ($action === 'random_call' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    json_out(200, ['found' => false, 'status' => 'success']);
}

// CANCEL CALL
if ($action === 'cancel_call' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    json_out(200, ['status' => 'success']);
}

json_out(400, ['status' => 'error', 'message' => 'Invalid action']);

