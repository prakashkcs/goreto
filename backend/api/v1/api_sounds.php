<?php
/**
 * api_sounds.php
 * Manages the sounds library extracted from uploaded videos via FFmpeg.
 *
 * GET  ?action=list              → paginated list of sounds
 * GET  ?action=trending          → top sounds by use_count
 * GET  ?action=search&q=...      → search by title
 * POST action=extract            → extract audio from an already-uploaded video post
 * POST action=use                → record that a user is making a video with this sound
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    echo json_encode(['status' => 'ok']);
    exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';
// $config is already provided by db_connect.php
if (!isset($config) || !is_array($config)) {
    $config = [];
}

function out(int $code, array $data): void
{
    http_response_code($code);
    echo json_encode($data);
    exit;
}

$baseUrl = rtrim($config['base_url'] ?? 'https://goreto.org/ekloadmin', '/');

// ── Ensure sounds table exists ────────────────────────────────────────────────
// post_id is nullable so seeded/viral sounds (not tied to a user post) work fine
$pdo->exec("CREATE TABLE IF NOT EXISTS `sounds` (
    `id`          INT AUTO_INCREMENT PRIMARY KEY,
    `post_id`     INT NULL,
    `user_id`     INT NOT NULL DEFAULT 0,
    `title`       VARCHAR(255) NOT NULL DEFAULT 'Original Sound',
    `audio_url`   VARCHAR(512) NOT NULL,
    `duration`    FLOAT NOT NULL DEFAULT 0,
    `use_count`   INT NOT NULL DEFAULT 0,
    `cover_url`   VARCHAR(512) NULL,
    `category`    VARCHAR(64) NULL DEFAULT 'original',
    `is_viral`    TINYINT(1) NOT NULL DEFAULT 0,
    `created_at`  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_sounds_post_id`  (`post_id`),
    INDEX `idx_sounds_user_id`  (`user_id`),
    INDEX `idx_sounds_use_count` (`use_count` DESC),
    INDEX `idx_sounds_viral`    (`is_viral`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Migrate existing table: make post_id nullable, add category/is_viral if missing
try {
    $pdo->exec("ALTER TABLE sounds MODIFY COLUMN post_id INT NULL");
} catch (Throwable $_) {
}
try {
    $pdo->exec("ALTER TABLE sounds MODIFY COLUMN user_id INT NOT NULL DEFAULT 0");
} catch (Throwable $_) {
}
try {
    $pdo->exec("ALTER TABLE sounds ADD COLUMN category VARCHAR(64) NULL DEFAULT 'original'");
} catch (Throwable $_) {
}
try {
    $pdo->exec("ALTER TABLE sounds ADD COLUMN is_viral TINYINT(1) NOT NULL DEFAULT 0");
} catch (Throwable $_) {
}

// ── Seed viral/trending sounds library (runs once, idempotent) ───────────────
// Uses Kevin MacLeod (incompetech.com) CC-BY 4.0 verified URLs + Pixabay CC0
// Threshold: re-seed if fewer than 30 viral sounds exist
// ── Default sounds removed ──────────────────────────────────────────────────
// The trending library is built ONLY from user-uploaded audio now. Remove any
// previously-seeded royalty-free sounds (cheap, idempotent — no-op once gone).
try {
    $seeded = (int) $pdo->query("SELECT COUNT(*) FROM sounds WHERE is_viral = 1 AND user_id = 0")->fetchColumn();
    if ($seeded > 0) {
        $pdo->exec("DELETE FROM sounds WHERE is_viral = 1 AND user_id = 0");
    }
} catch (Throwable $_) {
}

// Track which posts used which sound
$pdo->exec("CREATE TABLE IF NOT EXISTS `sound_uses` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `sound_id`   INT NOT NULL,
    `post_id`    INT NOT NULL,
    `user_id`    INT NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `unique_sound_use` (`sound_id`, `post_id`),
    INDEX `idx_sound_uses_sound_id` (`sound_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

// Add sound_id column to posts if missing
try {
    $pdo->exec("ALTER TABLE posts ADD COLUMN sound_id INT NULL");
} catch (Throwable $_) {
}

$method = $_SERVER['REQUEST_METHOD'];
$payload = json_decode(file_get_contents('php://input'), true) ?? [];
$action = $_GET['action'] ?? $_POST['action'] ?? $payload['action'] ?? 'list';

// ── GET: list / trending / search ─────────────────────────────────────────────
if ($method === 'GET') {
    $limit = max(1, min(100, intval($_GET['limit'] ?? 30)));
    $offset = max(0, intval($_GET['offset'] ?? 0));

    $category = trim($_GET['category'] ?? '');

    if ($action === 'search') {
        $q = '%' . trim($_GET['q'] ?? '') . '%';
        $stmt = $pdo->prepare("
            SELECT s.*, u.username AS author_username, u.profile_pic AS author_avatar
            FROM sounds s
            LEFT JOIN users u ON u.id = s.user_id AND s.user_id > 0
            WHERE s.title LIKE ?
            ORDER BY s.use_count DESC, s.id DESC
            LIMIT $limit OFFSET $offset
        ");
        $stmt->execute([$q]);
    } elseif ($action === 'trending' || $action === 'viral') {
        $stmt = $pdo->query("
            SELECT s.*, u.username AS author_username, u.profile_pic AS author_avatar,
                   ((SELECT COUNT(*) FROM sound_uses su WHERE su.sound_id = s.id AND su.created_at >= (NOW() - INTERVAL 7 DAY)) * 5
                    + (SELECT COUNT(*) FROM sound_uses su2 WHERE su2.sound_id = s.id AND su2.created_at >= (NOW() - INTERVAL 30 DAY)) * 2
                    + s.use_count)
                   / POW(GREATEST(TIMESTAMPDIFF(HOUR, s.created_at, NOW()), 1) + 2, 0.25) AS trend_score
            FROM sounds s
            LEFT JOIN users u ON u.id = s.user_id AND s.user_id > 0
            ORDER BY trend_score DESC, s.use_count DESC, s.id DESC
            LIMIT $limit OFFSET $offset
        ");
    } elseif ($category !== '') {
        $stmt = $pdo->prepare("
            SELECT s.*, u.username AS author_username, u.profile_pic AS author_avatar
            FROM sounds s
            LEFT JOIN users u ON u.id = s.user_id AND s.user_id > 0
            WHERE s.category = ?
            ORDER BY s.use_count DESC, s.id DESC
            LIMIT $limit OFFSET $offset
        ");
        $stmt->execute([$category]);
    } else {
        // default: trending (velocity-weighted) first, then newest
        $stmt = $pdo->query("
            SELECT s.*, u.username AS author_username, u.profile_pic AS author_avatar,
                   ((SELECT COUNT(*) FROM sound_uses su WHERE su.sound_id = s.id AND su.created_at >= (NOW() - INTERVAL 7 DAY)) * 5
                    + (SELECT COUNT(*) FROM sound_uses su2 WHERE su2.sound_id = s.id AND su2.created_at >= (NOW() - INTERVAL 30 DAY)) * 2
                    + s.use_count)
                   / POW(GREATEST(TIMESTAMPDIFF(HOUR, s.created_at, NOW()), 1) + 2, 0.25) AS trend_score
            FROM sounds s
            LEFT JOIN users u ON u.id = s.user_id AND s.user_id > 0
            ORDER BY trend_score DESC, s.use_count DESC, s.id DESC
            LIMIT $limit OFFSET $offset
        ");
    }

    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    $sounds = array_map(fn($r) => format_sound($r, $baseUrl), $rows);
    out(200, ['status' => 'success', 'sounds' => $sounds]);
}

// ── POST ──────────────────────────────────────────────────────────────────────
if ($method === 'POST') {

    // ── extract: pull audio from a video post using FFmpeg ───────────────────
    // ── seed: admin-only endpoint to add a viral sound by URL ───────────────
    if ($action === 'seed') {
        $viewer = requireUser($pdo);
        // Only allow admin (user_id=1 or is_admin flag)
        $adminCheck = $pdo->prepare("SELECT is_admin FROM users WHERE id=? LIMIT 1");
        $adminCheck->execute([(int) $viewer['id']]);
        $adminRow = $adminCheck->fetch(PDO::FETCH_ASSOC);
        if (!$adminRow || empty($adminRow['is_admin'])) {
            out(403, ['status' => 'error', 'message' => 'Admin only']);
        }
        $title = trim((string) ($_POST['title'] ?? $payload['title'] ?? ''));
        $audioUrl = trim((string) ($_POST['audio_url'] ?? $payload['audio_url'] ?? ''));
        $duration = (float) ($_POST['duration'] ?? $payload['duration'] ?? 0);
        $category = trim((string) ($_POST['category'] ?? $payload['category'] ?? 'viral'));
        $coverUrl = trim((string) ($_POST['cover_url'] ?? $payload['cover_url'] ?? ''));
        if (!$title || !$audioUrl)
            out(400, ['status' => 'error', 'message' => 'title and audio_url required']);
        $ins = $pdo->prepare("INSERT INTO sounds (post_id, user_id, title, audio_url, duration, category, cover_url, is_viral) VALUES (NULL, 0, ?, ?, ?, ?, ?, 1)");
        $ins->execute([$title, $audioUrl, $duration, $category, $coverUrl ?: null]);
        out(200, ['status' => 'success', 'sound_id' => (int) $pdo->lastInsertId()]);
    }

    if ($action === 'extract') {
        $viewer = requireUser($pdo);
        $userId = (int) $viewer['id'];

        $postId = intval($_POST['post_id'] ?? $payload['post_id'] ?? 0);
        $title = trim((string) ($_POST['title'] ?? $payload['title'] ?? ''));

        if ($postId <= 0)
            out(400, ['status' => 'error', 'message' => 'post_id required']);

        // Fetch the post's video file path
        $ps = $pdo->prepare("SELECT file_url, user_id, caption FROM posts WHERE id = ? LIMIT 1");
        $ps->execute([$postId]);
        $post = $ps->fetch(PDO::FETCH_ASSOC);
        if (!$post)
            out(404, ['status' => 'error', 'message' => 'Post not found']);

        // Resolve local file path from URL
        $fileUrl = (string) ($post['file_url'] ?? '');
        $localPath = url_to_local_path($fileUrl, $baseUrl);

        if (!$localPath || !file_exists($localPath)) {
            out(422, ['status' => 'error', 'message' => 'Video file not found on server']);
        }

        // Check FFmpeg is available
        exec('which ffmpeg 2>/dev/null', $ffOut, $ffRet);
        if ($ffRet !== 0) {
            out(500, ['status' => 'error', 'message' => 'FFmpeg not installed on server']);
        }

        // Already extracted for this post?
        $existing = $pdo->prepare("SELECT id FROM sounds WHERE post_id = ? LIMIT 1");
        $existing->execute([$postId]);
        if ($row = $existing->fetch(PDO::FETCH_ASSOC)) {
            // Return existing
            $s = $pdo->prepare("SELECT s.*, u.username AS author_username, u.profile_pic AS author_avatar FROM sounds s LEFT JOIN users u ON u.id = s.user_id WHERE s.id = ?");
            $s->execute([$row['id']]);
            out(200, ['status' => 'success', 'sound' => format_sound($s->fetch(PDO::FETCH_ASSOC), $baseUrl)]);
        }

        // Create sounds upload dir
        $soundsDir = __DIR__ . '/uploads/sounds/';
        if (!is_dir($soundsDir))
            @mkdir($soundsDir, 0755, true);

        $soundFile = 'snd_' . uniqid('', true) . '.m4a';
        $soundPath = $soundsDir . $soundFile;

        // Extract audio: strip video, encode as AAC m4a, 128k
        $cmd = sprintf(
            'ffmpeg -y -i %s -vn -acodec aac -b:a 128k -movflags +faststart %s 2>&1',
            escapeshellarg($localPath),
            escapeshellarg($soundPath)
        );
        exec($cmd, $ffmpegOut, $ffmpegRet);

        if ($ffmpegRet !== 0 || !file_exists($soundPath) || filesize($soundPath) < 100) {
            out(500, ['status' => 'error', 'message' => 'FFmpeg extraction failed', 'detail' => implode("\n", array_slice($ffmpegOut, -5))]);
        }

        // Get duration via ffprobe
        $duration = 0.0;
        $dCmd = sprintf('ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 %s 2>/dev/null', escapeshellarg($soundPath));
        exec($dCmd, $dOut);
        if (!empty($dOut[0]))
            $duration = round(floatval($dOut[0]), 2);

        $audioUrl = $baseUrl . '/uploads/sounds/' . $soundFile;

        if ($title === '') {
            $title = trim((string) ($post['caption'] ?? ''));
            if ($title === '')
                $title = 'Original Sound';
            // Truncate to 80 chars
            if (mb_strlen($title) > 80)
                $title = mb_substr($title, 0, 77) . '...';
        }

        $ins = $pdo->prepare("INSERT INTO sounds (post_id, user_id, title, audio_url, duration, category) VALUES (?, ?, ?, ?, ?, 'original')");
        $ins->execute([$postId, $userId, $title, $audioUrl, $duration]);
        $soundId = (int) $pdo->lastInsertId();

        // Link back to post
        try {
            $pdo->prepare("UPDATE posts SET sound_id = ? WHERE id = ?")->execute([$soundId, $postId]);
        } catch (Throwable $_) {
        }

        $s = $pdo->prepare("SELECT s.*, u.username AS author_username, u.profile_pic AS author_avatar FROM sounds s LEFT JOIN users u ON u.id = s.user_id WHERE s.id = ?");
        $s->execute([$soundId]);
        out(200, ['status' => 'success', 'sound' => format_sound($s->fetch(PDO::FETCH_ASSOC), $baseUrl)]);
    }

    // ── use: record that a new post is using this sound ──────────────────────
    if ($action === 'use') {
        $viewer = requireUser($pdo);
        $userId = (int) $viewer['id'];
        $soundId = intval($_POST['sound_id'] ?? $payload['sound_id'] ?? 0);
        $postId = intval($_POST['post_id'] ?? $payload['post_id'] ?? 0);

        if ($soundId <= 0 || $postId <= 0)
            out(400, ['status' => 'error', 'message' => 'sound_id and post_id required']);

        // Verify sound exists
        $chk = $pdo->prepare("SELECT id FROM sounds WHERE id = ? LIMIT 1");
        $chk->execute([$soundId]);
        if (!$chk->fetch())
            out(404, ['status' => 'error', 'message' => 'Sound not found']);

        $pdo->prepare("INSERT IGNORE INTO sound_uses (sound_id, post_id, user_id) VALUES (?, ?, ?)")
            ->execute([$soundId, $postId, $userId]);

        // Increment use_count
        $pdo->prepare("UPDATE sounds SET use_count = use_count + 1 WHERE id = ?")->execute([$soundId]);

        // Link sound to post
        try {
            $pdo->prepare("UPDATE posts SET sound_id = ? WHERE id = ?")->execute([$soundId, $postId]);
        } catch (Throwable $_) {
        }

        out(200, ['status' => 'success', 'message' => 'Sound use recorded']);
    }

    // ── upload: user uploads their own audio as a sound, trimmed to <=60s ───
    if ($action === 'upload') {
        $viewer = requireUser($pdo);
        $userId = (int) $viewer['id'];
        $f = $_FILES['audio'] ?? $_FILES['audio_file'] ?? null;
        if (!$f || !is_uploaded_file($f['tmp_name'])) {
            out(400, ['status' => 'error', 'message' => 'No audio file uploaded (field: audio)']);
        }
        $title = trim((string) ($_POST['title'] ?? ''));
        if ($title === '') $title = 'Original Sound';
        if (mb_strlen($title) > 80) $title = mb_substr($title, 0, 77) . '...';
        $category = trim((string) ($_POST['category'] ?? 'original')) ?: 'original';

        $soundsDir = __DIR__ . '/uploads/sounds/';
        if (!is_dir($soundsDir)) @mkdir($soundsDir, 0755, true);

        $ext = strtolower(pathinfo($f['name'], PATHINFO_EXTENSION));
        if (!in_array($ext, ['mp3','m4a','aac','wav','ogg','opus','flac','mp4'], true)) $ext = 'm4a';
        $rawFile = $soundsDir . 'raw_' . uniqid('', true) . '.' . $ext;
        if (!move_uploaded_file($f['tmp_name'], $rawFile)) {
            out(500, ['status' => 'error', 'message' => 'Failed to store upload']);
        }

        // Re-encode to a clean AAC m4a clip capped at 60s (server has ffmpeg).
        $maxSec = 60;
        $finalFile = $soundsDir . 'snd_' . uniqid('', true) . '.m4a';
        $cmd = sprintf(
            'ffmpeg -y -i %s -t %d -vn -acodec aac -b:a 128k -movflags +faststart %s 2>&1',
            escapeshellarg($rawFile), $maxSec, escapeshellarg($finalFile)
        );
        @exec($cmd, $ffOut, $ffRet);
        @unlink($rawFile);
        if ($ffRet !== 0 || !file_exists($finalFile) || filesize($finalFile) < 100) {
            @unlink($finalFile);
            out(500, ['status' => 'error', 'message' => 'Audio processing failed']);
        }

        $duration = 0.0;
        @exec(sprintf('ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 %s 2>/dev/null', escapeshellarg($finalFile)), $dOut);
        if (!empty($dOut[0])) $duration = min($maxSec, round(floatval($dOut[0]), 2));

        $audioUrl = $baseUrl . '/api/v1/uploads/sounds/' . basename($finalFile);

        // ── Dedupe: identical audio = one trending sound (reuse, don't dup) ──
        try { $pdo->exec("ALTER TABLE sounds ADD COLUMN audio_hash VARCHAR(32) NULL"); } catch (Throwable $e) {}
        try { $pdo->exec("CREATE INDEX idx_sounds_hash ON sounds (audio_hash)"); } catch (Throwable $e) {}
        $hash = @md5_file($finalFile) ?: null;
        if ($hash) {
            $dupSt = $pdo->prepare("SELECT id FROM sounds WHERE audio_hash = ? ORDER BY id ASC LIMIT 1");
            $dupSt->execute([$hash]);
            $dupId = (int) $dupSt->fetchColumn();
            if ($dupId > 0) {
                @unlink($finalFile); // identical clip already exists — reuse it
                $s = $pdo->prepare("SELECT s.*, u.username AS author_username, u.profile_pic AS author_avatar FROM sounds s LEFT JOIN users u ON u.id = s.user_id WHERE s.id = ?");
                $s->execute([$dupId]);
                out(200, ['status' => 'success', 'deduped' => true, 'sound' => format_sound($s->fetch(PDO::FETCH_ASSOC), $baseUrl)]);
            }
        }
        $ins = $pdo->prepare("INSERT INTO sounds (post_id, user_id, title, audio_url, duration, category, is_viral, use_count, audio_hash) VALUES (NULL, ?, ?, ?, ?, ?, 0, 0, ?)");
        $ins->execute([$userId, $title, $audioUrl, $duration, $category, $hash]);
        $soundId = (int) $pdo->lastInsertId();
        $s = $pdo->prepare("SELECT s.*, u.username AS author_username, u.profile_pic AS author_avatar FROM sounds s LEFT JOIN users u ON u.id = s.user_id WHERE s.id = ?");
        $s->execute([$soundId]);
        out(200, ['status' => 'success', 'sound' => format_sound($s->fetch(PDO::FETCH_ASSOC), $baseUrl)]);
    }

    out(400, ['status' => 'error', 'message' => 'Unknown action']);
}

out(405, ['status' => 'error', 'message' => 'Method not allowed']);

// ── Helpers ───────────────────────────────────────────────────────────────────

function format_sound(array $r, string $baseUrl): array
{
    $avatar = $r['author_avatar'] ?? '';
    if ($avatar && !preg_match('~^https?://~i', $avatar)) {
        $avatar = $baseUrl . '/' . ltrim($avatar, '/');
    }
    return [
        'id' => (int) $r['id'],
        'post_id' => $r['post_id'] ? (int) $r['post_id'] : null,
        'user_id' => (int) $r['user_id'],
        'title' => (string) $r['title'],
        'audio_url' => (string) $r['audio_url'],
        'duration' => (float) $r['duration'],
        'use_count' => (int) $r['use_count'],
        'cover_url' => (string) ($r['cover_url'] ?? ''),
        'author_username' => (string) ($r['author_username'] ?? ''),
        'author_avatar' => $avatar,
        'category' => (string) ($r['category'] ?? 'original'),
        'is_viral' => (bool) ($r['is_viral'] ?? false),
        'created_at' => (string) $r['created_at'],
    ];
}

function url_to_local_path(string $url, string $baseUrl): ?string
{
    // Strip base URL prefix to get relative path
    $rel = str_replace($baseUrl, '', $url);
    $rel = ltrim($rel, '/');
    // Map to filesystem
    $root = __DIR__; // /var/www/html/ekloadmin
    $path = $root . '/' . $rel;
    if (file_exists($path))
        return $path;

    // Try api/v1/uploads variant
    $path2 = str_replace('/uploads/', '/api/v1/uploads/', $path);
    if (file_exists($path2))
        return $path2;

    return null;
}
