<?php
// profile_v19.php - FIXED VERSION
error_reporting(E_ALL);
ini_set('display_errors', 1);

ob_start();

require_once 'db_connect.php';

function getProfile($userId) {
    global $pdo;
    try {
        $stmt = $pdo->prepare("
            SELECT 
                u.id, u.name, u.username, u.bio, u.location, u.profile_pic, u.cover_pic, 
                u.total_proposals, u.kyc_status, u.subscription_status,
                mp.gender, mp.age, mp.rating, mp.interests, mp.qualities, mp.looking_for,
                mp.income, mp.income_status
            FROM users u
            LEFT JOIN match_profiles mp ON u.id = mp.user_id
            WHERE u.id = ?
        ");
        $stmt->execute([$userId]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$user) return null;
        
        // Map profile_pic/cover_pic to avatar/cover for frontend compatibility
        $user['avatar'] = $user['profile_pic'] ?? '';
        $user['cover'] = $user['cover_pic'] ?? '';
        $user['profile_pic_url'] = $user['profile_pic'] ?? '';
        $user['cover_pic_url'] = $user['cover_pic'] ?? '';
        
        // Ensure name is not null/empty for frontend
        if (empty(trim($user['name'] ?? ''))) { 
            $user['name'] = 'User'; 
        }

        // ── SELF-HEALING FOLLOWS TABLE ──
        try {
            $pdo->exec("CREATE TABLE IF NOT EXISTS follows (
                id INT AUTO_INCREMENT PRIMARY KEY,
                follower_id INT NOT NULL,
                following_id INT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY unique_follow (follower_id, following_id),
                INDEX (follower_id),
                INDEX (following_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
        } catch (PDOException $e) { /* ignore */ }

        // Fetch actual counts - use "follows" (plural) to match follow.php logic
        $user['followers_count'] = 0;
        $user['following_count'] = 0;
        $user['posts_count'] = 0;

        try {
            $follSt = $pdo->prepare("SELECT COUNT(*) FROM follows WHERE following_id = ?");
            $follSt->execute([$userId]);
            $user['followers_count'] = (int)$follSt->fetchColumn();
            
            $follSt = $pdo->prepare("SELECT COUNT(*) FROM follows WHERE follower_id = ?");
            $follSt->execute([$userId]);
            $user['following_count'] = (int)$follSt->fetchColumn();
            
            try {
                $user['posts_count'] = (int)$pdo->query("SELECT COUNT(*) FROM posts WHERE user_id = " . intval($userId))->fetchColumn();
            } catch (Throwable $e) {
                // Fallback to prepared statement if direct query fails (e.g., table not found initially)
                $postSt = $pdo->prepare("SELECT COUNT(*) FROM posts WHERE user_id = ?");
                $postSt->execute([$userId]);
                $user['posts_count'] = (int)$postSt->fetchColumn();
            }
        } catch (PDOException $e) { /* ignore table errors */ }

        // 🟢 Dynamically aggregate truly unique inbound proposals that are actively pending/accepted
        try {
            $propSql = "SELECT COUNT(DISTINCT sender_id) FROM proposals WHERE receiver_id = " . intval($userId) . " AND status IN ('pending', 'accepted')";
            $user['total_proposals'] = (int)$pdo->query($propSql)->fetchColumn();
        } catch (Throwable $e) { /* ignore errors, keep original value or default */ }

        // Clean up data types
        $user['age'] = (int)($user['age'] ?? 25);
        $user['gender'] = !empty($user['gender']) ? strtolower($user['gender']) : 'male';
        $user['rating'] = (float)($user['rating'] ?? 0);
        $user['income'] = (float)($user['income'] ?? 0);
        
        // Parse JSON lists (interests, qualities, looking_for)
        foreach (['interests', 'qualities', 'looking_for'] as $key) {
            if (!empty($user[$key])) {
                $decoded = json_decode($user[$key], true);
                if (is_array($decoded)) {
                    $user[$key] = $decoded;
                } else {
                    $user[$key] = explode(',', $user[$key]);
                }
            } else {
                $user[$key] = [];
            }
        }
        
        $user['public_partner'] = null;
        
        // Fetch public partner (accepted proposal with show_on_profile = 1)
        $propSt = $pdo->prepare("
            SELECT p.id as proposal_id, 
                   CASE WHEN p.sender_id = ? THEN p.receiver_id ELSE p.sender_id END as partner_id
            FROM proposals p
            WHERE (p.sender_id = ? OR p.receiver_id = ?) 
              AND p.status = 'accepted'
              AND p.show_on_profile = 1 
            LIMIT 1
        ");
        $propSt->execute([$userId, $userId, $userId]);
        $proposal = $propSt->fetch(PDO::FETCH_ASSOC);
        
        if ($proposal) {
            $pId = (int)$proposal['partner_id'];
            $uSt = $pdo->prepare("SELECT name, profile_pic FROM users WHERE id = ?");
            $uSt->execute([$pId]);
            $partner = $uSt->fetch(PDO::FETCH_ASSOC);
            
            $user['public_partner'] = [
                'id' => $pId,
                'partner_name' => $partner['name'] ?? 'Partner',
                'partner_avatar' => $partner['profile_pic'] ?? '',
                'proposal_id' => (int)$proposal['proposal_id']
            ];
        }
        
        // --- ADD IS_FOLLOWING STATUS ---
        $headers = function_exists('getallheaders') ? getallheaders() : [];
        $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
        $token = trim($auth);
        if (stripos($token, 'Bearer ') === 0) {
            $token = trim(substr($token, 7));
        }
        
        $user['is_following'] = false;
        if (!empty($token)) {
            $stToken = $pdo->prepare("SELECT id FROM users WHERE api_token = ? LIMIT 1");
            $stToken->execute([$token]);
            $meId = $stToken->fetchColumn();
            if ($meId) {
                $stF = $pdo->prepare("SELECT 1 FROM follows WHERE follower_id = ? AND following_id = ? LIMIT 1");
                $stF->execute([$meId, $userId]);
                if ($stF->fetchColumn()) {
                    $user['is_following'] = true;
                }
            }
        }
        
        return $user;
    } catch (Exception $e) {
        return ['error' => $e->getMessage()];
    }
}

$noise = ob_get_clean();
header('Content-Type: application/json');

$userId = isset($_GET['user_id']) ? (int)$_GET['user_id'] : 0;
if ($userId > 0) {
    $profile = getProfile($userId);
    if ($profile && !isset($profile['error'])) {
        echo json_encode(['status' => 'success', 'user' => $profile]);
    } elseif (isset($profile['error'])) {
        echo json_encode(['status' => 'error', 'message' => 'Database error: ' . $profile['error']]);
    } else {
        echo json_encode(['status' => 'error', 'message' => 'User not found']);
    }
} else {
    echo json_encode(['status' => 'error', 'message' => 'Invalid user ID']);
}
?>
