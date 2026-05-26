<?php
// profile_v19.php - FIXED VERSION
error_reporting(0);
ini_set('display_errors', 0);

ob_start();

require_once 'db_connect.php';

function getProfile($userId)
{
    global $pdo;
    try {
        // Detect available columns to avoid "Unknown column" errors
        $colsStmt = $pdo->query("SHOW COLUMNS FROM users");
        $cols = array_column($colsStmt->fetchAll(PDO::FETCH_ASSOC), 'Field');
        $pick = fn(array $c) => array_values(array_filter($c, fn($f) => in_array($f, $cols, true)))[0] ?? null;

        $selectParts = ['id', 'name', 'username'];
        foreach (['bio', 'location', 'profile_pic', 'cover_pic', 'total_proposals', 'rating', 'kyc_status', 'subscription_status'] as $col) {
            if (in_array($col, $cols, true))
                $selectParts[] = $col;
        }
        $selectSql = implode(', ', $selectParts);

        $stmt = $pdo->prepare("SELECT $selectSql FROM users WHERE id = ?");
        $stmt->execute([$userId]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$user)
            return null;

        // 🔥 Check global block scope
        $headers = function_exists('getallheaders') ? getallheaders() : [];
        $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
        $token = trim($auth);
        if (stripos($token, 'Bearer ') === 0) {
            $token = trim(substr($token, 7));
        }

        $meId = 0;
        if (!empty($token)) {
            $stToken = $pdo->prepare("SELECT id FROM users WHERE api_token = ? LIMIT 1");
            $stToken->execute([$token]);
            $meId = (int) $stToken->fetchColumn();
        }

        if ($meId > 0 && $meId !== (int) $userId) {
            $bSt = $pdo->prepare("SELECT 1 FROM user_blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?) LIMIT 1");
            $bSt->execute([$meId, $userId, $userId, $meId]);
            if ($bSt->fetchColumn())
                return null; // Fully hide profile
        }

        // Map profile_pic/cover_pic to avatar/cover/url for frontend compatibility
        $user['avatar'] = $user['profile_pic'] ?? '';
        $user['profile_pic_url'] = $user['profile_pic'] ?? '';
        $user['cover'] = $user['cover_pic'] ?? '';
        $user['cover_pic_url'] = $user['cover_pic'] ?? '';

        // Dynamically append aggregate stats since they don't natively exist as columns on users
        $user['followers_count'] = (int) $pdo->query("SELECT COUNT(*) FROM follows WHERE following_id = " . intval($userId))->fetchColumn();
        $user['following_count'] = (int) $pdo->query("SELECT COUNT(*) FROM follows WHERE follower_id = " . intval($userId))->fetchColumn();

        try {
            $user['posts_count'] = (int) $pdo->query("SELECT COUNT(*) FROM posts WHERE user_id = " . intval($userId))->fetchColumn();
        } catch (Throwable $e) {
            $user['posts_count'] = 0;
        }

        // 🟢 Dynamically aggregate truly unique inbound proposals that are actively pending/accepted
        try {
            $propSql = "SELECT COUNT(DISTINCT sender_id) FROM proposals WHERE receiver_id = " . intval($userId) . " AND status IN ('pending', 'accepted')";
            $user['total_proposals'] = (int) $pdo->query($propSql)->fetchColumn();
        } catch (Throwable $e) {
            // Failsafe: column projection remains intact
        }

        // Ensure name is not null/empty for frontend
        if (empty(trim($user['name'] ?? ''))) {
            $user['name'] = '';
        }

        $user['public_partner'] = null;

        // Only show public_partner when BOTH sides have an accepted proposal (true mutual connection).
        // Also fetch the profile owner's gender so the Flutter UI can pick the correct pronoun.
        try {
            $propCols = array_column($pdo->query("SHOW COLUMNS FROM proposals")->fetchAll(PDO::FETCH_ASSOC), 'Field');
            $hasShowOnProfile = in_array('show_on_profile', $propCols, true);
            $showFilter = $hasShowOnProfile ? "AND p.show_on_profile = 1" : "";

            // Determine the partner id: the other side of the proposal
            // Require mutual acceptance: a reverse accepted proposal must also exist
            $stmt = $pdo->prepare("
                SELECT
                    p.sender_id,
                    p.receiver_id,
                    p.id AS proposal_id,
                    CASE WHEN p.sender_id = ? THEN p.receiver_id ELSE p.sender_id END AS partner_id,
                    COALESCE(u.full_name, u.name, 'Partner') AS partner_name,
                    u.profile_pic AS partner_avatar,
                    u.gender AS partner_gender,
                    owner.gender AS owner_gender
                FROM proposals p
                JOIN users u ON u.id = (CASE WHEN p.sender_id = ? THEN p.receiver_id ELSE p.sender_id END)
                JOIN users owner ON owner.id = ?
                WHERE (p.sender_id = ? OR p.receiver_id = ?)
                  AND p.status = 'accepted'
                  $showFilter
                  AND EXISTS (
                      SELECT 1 FROM proposals p2
                      WHERE p2.sender_id = (CASE WHEN p.sender_id = ? THEN p.receiver_id ELSE p.sender_id END)
                        AND p2.receiver_id = ?
                        AND p2.status = 'accepted'
                  )
                LIMIT 1
            ");
            $stmt->execute([$userId, $userId, $userId, $userId, $userId, $userId, $userId]);
            $proposal = $stmt->fetch(PDO::FETCH_ASSOC);
        } catch (Throwable $e) {
            $proposal = null;
        }

        if ($proposal) {
            $partnerId = (int) $proposal['partner_id'];
            $user['public_partner'] = [
                'partner_id' => $partnerId,
                'id' => $partnerId,
                'partner_name' => $proposal['partner_name'] ?? 'Partner',
                'name' => $proposal['partner_name'] ?? 'Partner',
                'partner_avatar' => $proposal['partner_avatar'] ?? '',
                'avatar' => $proposal['partner_avatar'] ?? '',
                'partner_gender' => $proposal['partner_gender'] ?? '',
                'owner_gender' => $proposal['owner_gender'] ?? '',
                'proposal_id' => (int) $proposal['proposal_id'],
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

// ── POST handler ───────────────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $noise = ob_get_clean();
    header('Content-Type: application/json');

    // Read JSON or form body
    $raw = file_get_contents('php://input');
    $body = json_decode($raw, true) ?? $_POST;
    $action = $body['action'] ?? $_POST['action'] ?? '';

    // Authenticate via Bearer token
    $headers = function_exists('getallheaders') ? getallheaders() : [];
    $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    $token = trim($auth);
    if (stripos($token, 'Bearer ') === 0) {
        $token = trim(substr($token, 7));
    }

    if (empty($token)) {
        echo json_encode(['status' => 'error', 'message' => 'Unauthorized']);
        exit;
    }

    $st = $pdo->prepare("SELECT id FROM users WHERE api_token = ? LIMIT 1");
    $st->execute([$token]);
    $userId = (int) $st->fetchColumn();

    if (!$userId) {
        // Fallback: check multi-device session tokens
        $st2 = $pdo->prepare("SELECT user_id FROM user_auth_tokens WHERE token = ? AND revoked_at IS NULL LIMIT 1");
        $st2->execute([$token]);
        $userId = (int) $st2->fetchColumn();
    }

    if (!$userId) {
        echo json_encode(['status' => 'error', 'message' => 'Unauthorized']);
        exit;
    }

    if ($action === 'update_profile') {
        // Detect actual cover column name in DB
        $dbCols = array_column($pdo->query("SHOW COLUMNS FROM users")->fetchAll(PDO::FETCH_ASSOC), 'Field');
        $coverCol = null;
        foreach (['cover_pic', 'cover', 'cover_image', 'cover_url', 'cover_photo'] as $c) {
            if (in_array($c, $dbCols, true)) { $coverCol = $c; break; }
        }
        $allowed = array_filter(['name', 'bio', 'location', 'gender', 'age', 'is_match_visible', 'latitude', 'longitude', 'profile_pic', $coverCol]);
        $sets = [];
        $vals = [];
        foreach ($allowed as $f) {
            if (array_key_exists($f, $body)) {
                $sets[] = "$f = ?";
                $vals[] = $body[$f];
            }
        }
        if (empty($sets)) {
            echo json_encode(['status' => 'error', 'message' => 'Nothing to update']);
            exit;
        }
        $vals[] = $userId;
        try {
            $pdo->prepare("UPDATE users SET " . implode(', ', $sets) . " WHERE id = ?")->execute($vals);
            echo json_encode(['status' => 'success', 'message' => 'Profile updated']);
        } catch (Exception $e) {
            echo json_encode(['status' => 'error', 'message' => 'Database error: ' . $e->getMessage()]);
        }
        exit;
    }

    echo json_encode(['status' => 'error', 'message' => 'Unknown action']);
    exit;
}

$noise = ob_get_clean();
header('Content-Type: application/json');

$userId = isset($_GET['user_id']) ? (int) $_GET['user_id'] : 0;
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