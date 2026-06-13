<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    echo json_encode(['status' => 'success']);
    exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';
// Helper: send JSON response with HTTP status code
if (!function_exists('out_json')) {
    function out_json(int $code, array $payload): void {
        http_response_code($code);
        echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        exit;
    }
}

$config = require __DIR__ . '/../../config/config.php';

// --- Utility Functions ---
function norm_url(?string $url, string $baseUrl): ?string
{
    if ($url === null)
        return null;
    $url = trim((string)$url);
    if ($url === '')
        return '';

    // CDN Redirection for relative upload paths
    if (strpos($url, 'uploads/') !== false && !preg_match('~^https?://~i', $url)) {
        return 'https://coinzop.com/ekloadmin/' . ltrim($url, '/');
    }

    if (preg_match('~^https?://~i', $url))
        return $url;
    $baseUrl = rtrim($baseUrl, '/');
    if ($url[0] === '/')
        return $baseUrl . $url;
    return $baseUrl . '/' . $url;
}

try {
    if (!isset($pdo) || !($pdo instanceof PDO)) {
        out_json(500, ['status' => 'error', 'message' => 'DB connection not available']);
    }

    // 🔧 Auto-migration: Ensure stories table exists
    // The bug report mentions "stories table", so we assume it should exist.
    $pdo->exec("CREATE TABLE IF NOT EXISTS `stories` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `user_id` INT NOT NULL,
        `media_url` TEXT NOT NULL,
        `type` ENUM('image', 'video') DEFAULT 'image',
        `music` VARCHAR(255) NULL,
        `tags` TEXT NULL,
        `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX (`user_id`),
        INDEX (`created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

    $pdo->exec("CREATE TABLE IF NOT EXISTS `story_views` (
        `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
        `story_id` INT NOT NULL,
        `viewer_id` INT NOT NULL,
        `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY `uniq_sv` (`story_id`,`viewer_id`),
        INDEX (`story_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");
    $pdo->exec("CREATE TABLE IF NOT EXISTS `story_reactions` (
        `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
        `story_id` INT NOT NULL,
        `user_id` INT NOT NULL,
        `reaction` VARCHAR(16) NOT NULL,
        `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY `uniq_sr` (`story_id`,`user_id`),
        INDEX (`story_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

    // Story audio columns (custom trending audio).
    try { $pdo->exec("ALTER TABLE stories ADD COLUMN music_url VARCHAR(512) NULL"); } catch (Throwable $_) {}
    try { $pdo->exec("ALTER TABLE stories ADD COLUMN sound_id INT NULL"); } catch (Throwable $_) {}

    $baseUrl = rtrim(($config['base_url'] ?? 'https://coinzop.com/ekloadmin/api/v1'), '/');

    /* =========================================================
     ✅ POST: Upload Story
     ========================================================= */
    if ($_SERVER['REQUEST_METHOD'] === 'POST' && (!isset($_GET['action']) || $_GET['action'] === 'upload')) {
        // FIXED: requireUser correctly looks up in users table via api_token
        $viewer = requireUser($pdo);
        $userId = intval($viewer['id']);
        // Pause ALL uploads when a prior NSFW violation flagged this account.
        try {
            $ubSt = $pdo->prepare("SELECT COALESCE(upload_blocked,0) FROM users WHERE id = ?");
            $ubSt->execute([$userId]);
            if ((int)$ubSt->fetchColumn() === 1) {
                out_json(403, ['status' => 'error', 'error_code' => 'upload_blocked', 'message' => 'Your uploads are paused due to a content-policy violation. An admin must review your account before you can post again.']);
            }
        } catch (Throwable $e) {}

        if (!isset($_FILES['file']) || !is_uploaded_file($_FILES['file']['tmp_name'])) {
            out_json(400, ['status' => 'error', 'message' => 'No file uploaded']);
        }

        $uploadDir = __DIR__ . '/uploads/stories/';
        if (!is_dir($uploadDir))
            @mkdir($uploadDir, 0777, true);

        $origName = basename($_FILES['file']['name']);
        $ext = pathinfo($origName, PATHINFO_EXTENSION);
        $fileName = uniqid('s_', true) . ($ext ? '.' . preg_replace('/[^a-zA-Z0-9]/', '', $ext) : '');
        $destPath = $uploadDir . $fileName;

        if (!move_uploaded_file($_FILES['file']['tmp_name'], $destPath)) {
            out_json(500, ['status' => 'error', 'message' => 'Failed to move uploaded file']);
        }
        // ── NSFW scan: remove adult content + flag the uploader ──
        $nsfwImg = ['jpg','jpeg','png','gif','webp'];
        $nsfwVid = ['mp4','mov','avi','webm','m4v'];
        $nsfwExtL = strtolower($ext);
        $nsfwKind = in_array($nsfwExtL, $nsfwVid, true) ? 'video' : (in_array($nsfwExtL, $nsfwImg, true) ? 'image' : '');
        if ($nsfwKind !== '') {
            $nch = curl_init('http://127.0.0.1:8000/scan/local');
            curl_setopt_array($nch, [
                CURLOPT_RETURNTRANSFER => true, CURLOPT_POST => true,
                CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
                CURLOPT_POSTFIELDS => json_encode(['path' => $destPath, 'kind' => $nsfwKind]),
                CURLOPT_TIMEOUT => 35,
            ]);
            $nresp = curl_exec($nch);
            $ncode = curl_getinfo($nch, CURLINFO_HTTP_CODE);
            curl_close($nch);
            $nj = ($nresp !== false && $ncode === 200) ? json_decode($nresp, true) : null;
            if (is_array($nj) && ($nj['status'] ?? '') === 'rejected') {
                try {
                    $pdo->prepare('INSERT INTO nsfw_violations (user_id, content_type, reason, details) VALUES (?,?,?,?)')
                        ->execute([$userId, $nsfwKind, $nj['reason'] ?? 'nsfw', json_encode($nj['detections'] ?? [])]);
                    $pdo->prepare('UPDATE users SET nsfw_strikes = nsfw_strikes + 1 WHERE id = ?')->execute([$userId]);
                    $pdo->prepare('UPDATE users SET upload_blocked = 1 WHERE id = ?')->execute([$userId]);
                } catch (Throwable $e) {}
                @unlink($destPath);
                out_json(403, ['status' => 'error', 'error_code' => 'nsfw_rejected',
                    'message' => 'Your story was removed for violating our content policy. Repeated violations may lead to your account being banned.']);
            }
        }

        // --- BunnyCDN Integration ---
        require_once __DIR__ . '/bunny_helper.php';
        $bunnyPath = 'uploads/stories/' . $fileName;
        $cdnUrl = uploadToBunny($destPath, $bunnyPath);
        if ($cdnUrl) {
            $mediaUrl = $cdnUrl;
        // @unlink($destPath);
        }
        else {
            $mediaUrl = rtrim(($config['base_url'] ?? 'https://coinzop.com/ekloadmin'), '/') . "/api/v1/uploads/stories/" . $fileName;
        }
        // ---------------------------
        $type = (isset($_POST['type']) && $_POST['type'] === 'video') ? 'video' : 'image';
        $music = $_POST['music'] ?? null;
        $musicUrl = $_POST['music_url'] ?? null;
        $soundId = isset($_POST['sound_id']) ? (int)$_POST['sound_id'] : 0;
        $tags = $_POST['tags'] ?? null;

        $stmt = $pdo->prepare("INSERT INTO `stories` (user_id, media_url, type, music, music_url, sound_id, tags) VALUES (?, ?, ?, ?, ?, ?, ?)");
        $stmt->execute([$userId, $mediaUrl, $type, $music, $musicUrl, $soundId ?: null, $tags]);
        $newStoryId = (int)$pdo->lastInsertId();

        // Record the sound use so it climbs the trending/virality ranking.
        if ($soundId > 0) {
            try {
                $pdo->prepare("INSERT IGNORE INTO sound_uses (sound_id, post_id, user_id) VALUES (?, ?, ?)")->execute([$soundId, $newStoryId, $userId]);
                $pdo->prepare("UPDATE sounds SET use_count = use_count + 1 WHERE id = ?")->execute([$soundId]);
            } catch (Throwable $_) {}
        }

        out_json(200, ['status' => 'success', 'message' => 'Story uploaded successfully', 'id' => $pdo->lastInsertId()]);
    }

    /* =========================================================
     ✅ GET: Active Stories
     ========================================================= */
    $action = $_GET['action'] ?? '';

    // -- Record that the current user viewed a story --
    if ($_SERVER['REQUEST_METHOD'] === 'POST' && $action === 'view') {
        $viewer = requireUser($pdo); $vid = (int)$viewer['id'];
        $body = json_decode(file_get_contents('php://input'), true) ?: $_POST;
        $sid = (int)($body['story_id'] ?? $_POST['story_id'] ?? 0);
        if ($sid <= 0) out_json(400, ['status'=>'error','message'=>'story_id required']);
        $o = $pdo->prepare('SELECT user_id FROM stories WHERE id=? LIMIT 1'); $o->execute([$sid]);
        $owner = (int)($o->fetchColumn() ?: 0);
        if ($owner !== $vid) { $pdo->prepare('INSERT IGNORE INTO story_views (story_id, viewer_id) VALUES (?,?)')->execute([$sid,$vid]); }
        out_json(200, ['status'=>'success']);
    }

    // -- React to a story --
    if ($_SERVER['REQUEST_METHOD'] === 'POST' && $action === 'react') {
        $viewer = requireUser($pdo); $vid = (int)$viewer['id'];
        $body = json_decode(file_get_contents('php://input'), true) ?: $_POST;
        $sid = (int)($body['story_id'] ?? $_POST['story_id'] ?? 0);
        $reaction = trim((string)($body['reaction'] ?? $_POST['reaction'] ?? ''));
        if ($sid <= 0 || $reaction === '') out_json(400, ['status'=>'error','message'=>'story_id and reaction required']);
        if (mb_strlen($reaction) > 16) $reaction = mb_substr($reaction, 0, 16);
        $o = $pdo->prepare('SELECT user_id FROM stories WHERE id=? LIMIT 1'); $o->execute([$sid]);
        $owner = (int)($o->fetchColumn() ?: 0);
        if ($owner !== $vid) { $pdo->prepare('INSERT IGNORE INTO story_views (story_id, viewer_id) VALUES (?,?)')->execute([$sid,$vid]); }
        $pdo->prepare('INSERT INTO story_reactions (story_id, user_id, reaction) VALUES (?,?,?) ON DUPLICATE KEY UPDATE reaction=VALUES(reaction), created_at=NOW()')->execute([$sid,$vid,$reaction]);
        out_json(200, ['status'=>'success']);
    }

    // -- Delete a story (owner only) --
    if (($_SERVER['REQUEST_METHOD'] === 'POST' || $_SERVER['REQUEST_METHOD'] === 'DELETE') && $action === 'delete') {
        $viewer = requireUser($pdo); $vid = (int)$viewer['id'];
        $body = json_decode(file_get_contents('php://input'), true) ?: $_POST;
        $sid = (int)($body['story_id'] ?? $_POST['story_id'] ?? $_GET['story_id'] ?? 0);
        if ($sid <= 0) out_json(400, ['status'=>'error','message'=>'story_id required']);
        $o = $pdo->prepare('SELECT user_id FROM stories WHERE id=? LIMIT 1'); $o->execute([$sid]);
        $owner = (int)($o->fetchColumn() ?: 0);
        if ($owner === 0) out_json(404, ['status'=>'error','message'=>'Story not found']);
        if ($owner !== $vid) out_json(403, ['status'=>'error','message'=>'Not your story']);
        $pdo->prepare('DELETE FROM stories WHERE id=?')->execute([$sid]);
        $pdo->prepare('DELETE FROM story_views WHERE story_id=?')->execute([$sid]);
        $pdo->prepare('DELETE FROM story_reactions WHERE story_id=?')->execute([$sid]);
        out_json(200, ['status'=>'success','message'=>'Story deleted']);
    }

    // -- Viewers + reactions list (owner only) --
    if ($_SERVER['REQUEST_METHOD'] === 'GET' && $action === 'viewers') {
        $viewer = requireUser($pdo); $vid = (int)$viewer['id'];
        $sid = (int)($_GET['story_id'] ?? 0);
        if ($sid <= 0) out_json(400, ['status'=>'error','message'=>'story_id required']);
        $o = $pdo->prepare('SELECT user_id FROM stories WHERE id=? LIMIT 1'); $o->execute([$sid]);
        $owner = (int)($o->fetchColumn() ?: 0);
        if ($owner !== $vid) out_json(403, ['status'=>'error','message'=>'Not your story']);
        $stmt = $pdo->prepare('SELECT sv.viewer_id, sv.created_at AS viewed_at, u.name, u.username, u.profile_pic, (SELECT reaction FROM story_reactions sr WHERE sr.story_id=sv.story_id AND sr.user_id=sv.viewer_id LIMIT 1) AS reaction FROM story_views sv JOIN users u ON u.id=sv.viewer_id WHERE sv.story_id=? ORDER BY sv.created_at DESC LIMIT 200');
        $stmt->execute([$sid]);
        $viewers = [];
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
            $pic = (string)($r['profile_pic'] ?? '');
            if ($pic !== '' && !preg_match('~^https?://~i', $pic)) { $pic = 'https://goreto.org/ekloadmin/' . ltrim($pic, '/'); }
            $viewers[] = [
                'user_id' => (string)$r['viewer_id'],
                'name' => $r['name'] ?: ($r['username'] ?: 'User'),
                'username' => (string)($r['username'] ?? ''),
                'avatar' => $pic !== '' ? $pic : null,
                'reaction' => (string)($r['reaction'] ?? ''),
                'viewed_at' => (string)$r['viewed_at'],
            ];
        }
        out_json(200, ['status'=>'success','count'=>count($viewers),'viewers'=>$viewers]);
    }

    if ($action === 'active') {
        // Fetch stories from the last 24 hours
        // Join with users to fix "user name and profile pic are not showing"
        $sql = "SELECT s.*, u.name as user_name, u.profile_pic as user_avatar, u.username as user_handle,
                       (SELECT COUNT(*) FROM `story_views` v WHERE v.story_id = s.id) AS view_count
                FROM `stories` s
                JOIN `users` u ON u.id = s.user_id
                WHERE s.created_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
                ORDER BY s.created_at DESC";

        $stmt = $pdo->query($sql);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $stories = [];
        foreach ($rows as $r) {
            $stories[] = [
                'id' => (string)$r['id'],
                'user_id' => (string)$r['user_id'],
                'user_name' => (string)$r['user_name'],
                'user_avatar' => norm_url($r['user_avatar'], $baseUrl),
                'user_handle' => (string)$r['user_handle'],
                'media_url' => norm_url($r['media_url'], $baseUrl),
                'type' => (string)$r['type'],
                'music' => (string)$r['music'],
                'music_url' => norm_url($r['music_url'] ?? '', $baseUrl),
                'sound_id' => isset($r['sound_id']) ? (int)$r['sound_id'] : 0,
                'tags' => (string)$r['tags'],
                'view_count' => (int)($r['view_count'] ?? 0),
                'created_at' => (string)$r['created_at']
            ];
        }

        out_json(200, ['status' => 'success', 'stories' => $stories]);
    }

    // Default response
    out_json(400, ['status' => 'error', 'message' => 'Invalid action']);

}
catch (Throwable $e) {
    out_json(500, ['status' => 'error', 'message' => $e->getMessage()]);
}
