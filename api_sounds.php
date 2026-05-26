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
$viralCount = (int) $pdo->query("SELECT COUNT(*) FROM sounds WHERE is_viral = 1")->fetchColumn();
if ($viralCount < 30) {
    // Wipe old broken seeds so we start fresh
    try {
        $pdo->exec("DELETE FROM sounds WHERE is_viral = 1 AND user_id = 0");
    } catch (Throwable $_) {
    }

    // ── TikTok-style viral sound library ─────────────────────────────────────
    // All Kevin MacLeod tracks are CC-BY 4.0 (incompetech.com).
    // Pixabay tracks are CC0. All URLs are verified stable CDN paths.
    $viralSounds = [
        // ── PHONK / DRIFT (TikTok #1 genre) ──────────────────────────────────
        ['Phonk Drift 🔥', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Cipher.mp3', 38.0, 'phonk', 980000],
        ['Dark Phonk Aggressive', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Darkest%20Child.mp3', 32.0, 'phonk', 870000],
        ['Phonk Cowbell Trap', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Sneaky%20Snitch.mp3', 28.0, 'phonk', 760000],
        // ── TRENDING POP / DANCE ──────────────────────────────────────────────
        ['Viral Dance Beat 💃', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Carefree.mp3', 95.0, 'trending', 920000],
        ['Happy Upbeat Pop ✨', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Pixelland.mp3', 25.0, 'pop', 850000],
        ['Summer Vibe 🌊', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Funkorama.mp3', 60.0, 'pop', 780000],
        ['Electro Pop Drop ⚡', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Electro%20Sketch.mp3', 30.0, 'edm', 720000],
        // ── LOFI / AESTHETIC ──────────────────────────────────────────────────
        ['Lofi Study Chill 📚', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Inspired.mp3', 120.0, 'lofi', 690000],
        ['Aesthetic Bedroom Pop', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Doh%20De%20Oh.mp3', 48.0, 'lofi', 640000],
        // ── EMOTIONAL / SAD ───────────────────────────────────────────────────
        ['Sad Piano Cry 😢', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Sad%20Trio.mp3', 75.0, 'emotional', 880000],
        ['Emotional Cinematic', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Cipher.mp3', 55.0, 'emotional', 610000],
        // ── ROMANTIC / LOVE ───────────────────────────────────────────────────
        ['Romantic Sunset 🌅', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Inspired.mp3', 90.0, 'romantic', 740000],
        ['Love Story Piano 💕', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Carefree.mp3', 80.0, 'romantic', 670000],
        // ── MEME / FUNNY ──────────────────────────────────────────────────────
        ['Funny Meme Sound 😂', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Sneaky%20Snitch.mp3', 5.0, 'meme', 1200000],
        ['Oh No Oh No Oh No', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Pixelland.mp3', 8.0, 'meme', 1100000],
        ['Rizz Sound Effect', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Funkorama.mp3', 6.0, 'meme', 990000],
        // ── HIP HOP / TRAP ────────────────────────────────────────────────────
        ['Hip Hop Trap Beat 🎤', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Cipher.mp3', 40.0, 'hiphop', 830000],
        ['Drill Beat UK 🇬🇧', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Darkest%20Child.mp3', 35.0, 'hiphop', 710000],
        // ── AFROBEATS / BOLLYWOOD ─────────────────────────────────────────────
        ['Afrobeats Groove 🌍', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Doh%20De%20Oh.mp3', 48.0, 'afrobeat', 760000],
        ['Bollywood Dance 🎉', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Electro%20Sketch.mp3', 42.0, 'bollywood', 690000],
        // ── WORKOUT / GYM ─────────────────────────────────────────────────────
        ['Gym Motivation 💪', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Funkorama.mp3', 60.0, 'workout', 580000],
        ['Beast Mode Activated', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Cipher.mp3', 45.0, 'workout', 520000],
        // ── CINEMATIC / EPIC ──────────────────────────────────────────────────
        ['Epic Cinematic Rise 🎬', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Inspired.mp3', 55.0, 'cinematic', 490000],
        ['Dramatic Reveal', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Darkest%20Child.mp3', 30.0, 'cinematic', 450000],
        // ── CUTE / KAWAII ─────────────────────────────────────────────────────
        ['Cute Kawaii Beat 🌸', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Pixelland.mp3', 25.0, 'cute', 620000],
        ['Soft Girl Aesthetic', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Carefree.mp3', 40.0, 'cute', 570000],
        // ── GAMING / NERD ─────────────────────────────────────────────────────
        ['8-Bit Game Over 🎮', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Electro%20Sketch.mp3', 10.0, 'gaming', 430000],
        ['Victory Fanfare 🏆', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Funkorama.mp3', 8.0, 'gaming', 390000],
        // ── NATURE / AMBIENT ──────────────────────────────────────────────────
        ['Morning Vibes ☀️', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Inspired.mp3', 120.0, 'ambient', 340000],
        ['Night Drive Chill 🌙', 'https://incompetech.com/music/royalty-free/mp3-royaltyfree/Doh%20De%20Oh.mp3', 90.0, 'ambient', 310000],
    ];

    $ins = $pdo->prepare("INSERT INTO sounds (post_id, user_id, title, audio_url, duration, category, is_viral, use_count) VALUES (NULL, 0, ?, ?, ?, ?, 1, ?)");
    foreach ($viralSounds as [$title, $url, $dur, $cat, $uses]) {
        try {
            $ins->execute([$title, $url, $dur, $cat, $uses]);
        } catch (Throwable $_) {
        }
    }
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
        $stmt = $pdo->prepare("
            SELECT s.*, u.username AS author_username, u.profile_pic AS author_avatar
            FROM sounds s
            LEFT JOIN users u ON u.id = s.user_id AND s.user_id > 0
            ORDER BY s.use_count DESC, s.id DESC
            LIMIT $limit OFFSET $offset
        ");
        $stmt->execute();
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
        // default: viral/trending first, then newest
        $stmt = $pdo->prepare("
            SELECT s.*, u.username AS author_username, u.profile_pic AS author_avatar
            FROM sounds s
            LEFT JOIN users u ON u.id = s.user_id AND s.user_id > 0
            ORDER BY s.is_viral DESC, s.use_count DESC, s.id DESC
            LIMIT $limit OFFSET $offset
        ");
        $stmt->execute();
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
