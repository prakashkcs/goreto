<?php
/**
 * api_trending.php — Advanced Viral Algorithm v2
 *
 * Viral Score Formula (per post):
 *   base  = likes×1.0 + comments×3.0 + shares×5.0 + views×0.05 + saves×2.0
 *   time  = base / (age_hours + 2)^1.5          ← time decay (gravity model)
 *   vel   = interactions_last_1h × 10            ← velocity bonus
 *   cross = ×1.20 if author has IG/TT/YT linked  ← cross-platform boost
 *   score = (time + vel) × cross
 *
 * GET ?action=posts|reels|hashtags|sounds|leaderboard
 * GET ?period=1h|6h|24h|7d|30d|all
 * GET ?limit=1-100
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    echo json_encode(['status' => 'success']);
    exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';
$config = require __DIR__ . '/../../config/config.php';

function out_json(int $code, array $payload): void
{
    http_response_code($code);
    echo json_encode($payload);
    exit;
}

function norm_url(?string $url, string $baseUrl): string
{
    if (!$url)
        return '';
    $url = trim($url);
    if ($url === '')
        return '';
    if (strpos($url, 'uploads/') !== false && !preg_match('~^https?://~i', $url))
        return 'https://goreto.org/ekloadmin/' . ltrim($url, '/');
    if (preg_match('~^https?://~i', $url))
        return $url;
    return rtrim($baseUrl, '/') . '/' . ltrim($url, '/');
}

try {
    if (!isset($pdo) || !($pdo instanceof PDO))
        out_json(500, ['status' => 'error', 'message' => 'DB unavailable']);

    $baseUrl = rtrim($config['base_url'] ?? 'https://goreto.org/ekloadmin/api/v1', '/');
    $action = strtolower(trim($_GET['action'] ?? 'posts'));
    $limit = max(1, min(100, intval($_GET['limit'] ?? 30)));
    $period = strtolower($_GET['period'] ?? '24h');

    // Resolve optional viewer
    $viewerId = 0;
    try {
        $v = requireUser($pdo);
        $viewerId = intval($v['id']);
    } catch (Throwable $_) {
    }

    // Period → hours
    $periodHours = match ($period) {
        '1h' => 1,
        '6h' => 6,
        '7d' => 168,
        '30d' => 720,
        'all' => 99999,
        default => 24,
    };

    // ── Ensure tables ────────────────────────────────────────────────────────
    $pdo->exec("CREATE TABLE IF NOT EXISTS post_trending_scores (
        post_id    INT PRIMARY KEY,
        score      FLOAT NOT NULL DEFAULT 0,
        velocity   FLOAT NOT NULL DEFAULT 0,
        cross_boost TINYINT NOT NULL DEFAULT 0,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    // ── Recompute trending scores (runs on every request, lightweight) ───────
    // We use a MySQL expression to compute the score inline so no cron needed.
    // The INSERT … ON DUPLICATE KEY UPDATE keeps the table fresh.
    $pdo->exec("
        INSERT INTO post_trending_scores (post_id, score, velocity, cross_boost)
        SELECT
            p.id AS post_id,
            (
              (
                COALESCE(p.likes_count,0)*1.0 +
                COALESCE(p.comments_count,0)*3.0 +
                COALESCE(p.view_count,0)*0.05 +
                COALESCE(p.shares_count,0)*5.0 +
                COALESCE(p.saves_count,0)*2.0
              ) / POW(GREATEST(TIMESTAMPDIFF(HOUR, p.created_at, NOW()),0) + 2, 1.5)
              +
              (SELECT COUNT(*) FROM post_likes pl2
               WHERE pl2.post_id=p.id AND pl2.created_at >= NOW()-INTERVAL 1 HOUR)*10
              +
              (SELECT COUNT(*) FROM post_comments pc2
               WHERE pc2.post_id=p.id AND pc2.created_at >= NOW()-INTERVAL 1 HOUR)*30
            ) * IF(
              COALESCE(u.instagram,'')!='' OR COALESCE(u.tiktok,'')!='' OR COALESCE(u.youtube,'')!='',
              1.20, 1.0
            ) AS score,
            (SELECT COUNT(*) FROM post_likes pl2
             WHERE pl2.post_id=p.id AND pl2.created_at >= NOW()-INTERVAL 1 HOUR)*10 AS velocity,
            IF(
              COALESCE(u.instagram,'')!='' OR COALESCE(u.tiktok,'')!='' OR COALESCE(u.youtube,'')!='',
              1, 0
            ) AS cross_boost
        FROM posts p
        LEFT JOIN users u ON u.id = p.user_id
        WHERE p.created_at >= NOW() - INTERVAL ? HOUR
        ON DUPLICATE KEY UPDATE
            score      = VALUES(score),
            velocity   = VALUES(velocity),
            cross_boost= VALUES(cross_boost),
            updated_at = NOW()
    ");
    // Note: PDO exec doesn't support bound params; use prepare for the INTERVAL
    $stmt = $pdo->prepare("
        INSERT INTO post_trending_scores (post_id, score, velocity, cross_boost)
        SELECT
            p.id AS post_id,
            (
              (
                COALESCE(p.likes_count,0)*1.0 +
                COALESCE(p.comments_count,0)*3.0 +
                COALESCE(p.view_count,0)*0.05 +
                COALESCE(p.shares_count,0)*5.0 +
                COALESCE(p.saves_count,0)*2.0
              ) / POW(GREATEST(TIMESTAMPDIFF(HOUR, p.created_at, NOW()),0) + 2, 1.5)
              +
              (SELECT COUNT(*) FROM post_likes pl2
               WHERE pl2.post_id=p.id AND pl2.created_at >= NOW()-INTERVAL 1 HOUR)*10
              +
              (SELECT COUNT(*) FROM post_comments pc2
               WHERE pc2.post_id=p.id AND pc2.created_at >= NOW()-INTERVAL 1 HOUR)*30
            ) * IF(
              COALESCE(u.instagram,'')!='' OR COALESCE(u.tiktok,'')!='' OR COALESCE(u.youtube,'')!='',
              1.20, 1.0
            ) AS score,
            (SELECT COUNT(*) FROM post_likes pl2
             WHERE pl2.post_id=p.id AND pl2.created_at >= NOW()-INTERVAL 1 HOUR)*10 AS velocity,
            IF(
              COALESCE(u.instagram,'')!='' OR COALESCE(u.tiktok,'')!='' OR COALESCE(u.youtube,'')!='',
              1, 0
            ) AS cross_boost
        FROM posts p
        LEFT JOIN users u ON u.id = p.user_id
        WHERE p.created_at >= NOW() - INTERVAL ? HOUR
        ON DUPLICATE KEY UPDATE
            score       = VALUES(score),
            velocity    = VALUES(velocity),
            cross_boost = VALUES(cross_boost),
            updated_at  = NOW()
    ");
    $stmt->execute([$periodHours]);

    // ── ACTION: posts / reels ─────────────────────────────────────────────────
    if ($action === 'posts' || $action === 'reels') {
        $typeFilter = $action === 'reels' ? "AND LOWER(p.type) IN ('video','reel')" : '';

        $sql = "
            SELECT
                p.id, p.user_id, p.caption, p.file_url AS media, p.type, p.created_at,
                COALESCE(pts.score, 0)      AS trend_score,
                COALESCE(pts.velocity, 0)   AS velocity,
                COALESCE(pts.cross_boost,0) AS cross_boost,
                COALESCE(p.likes_count, 0)    AS likes_count,
                COALESCE(p.comments_count, 0) AS comments_count,
                COALESCE(p.view_count, 0)     AS view_count,
                COALESCE(p.shares_count, 0)   AS shares_count,
                u.name     AS author_name,
                u.username AS author_username,
                u.profile_pic AS author_avatar,
                u.subscription_status AS author_subscription_status,
                COALESCE(u.instagram,'') AS author_instagram,
                COALESCE(u.tiktok,'')    AS author_tiktok,
                COALESCE(u.youtube,'')   AS author_youtube,
                CASE WHEN fl.follower_id IS NOT NULL THEN 1 ELSE 0 END AS is_following,
                CASE WHEN ul.user_id     IS NOT NULL THEN 1 ELSE 0 END AS is_liked
            FROM posts p
            LEFT JOIN post_trending_scores pts ON pts.post_id = p.id
            LEFT JOIN users u ON u.id = p.user_id
            LEFT JOIN follows fl ON fl.follower_id = ? AND fl.following_id = p.user_id
            LEFT JOIN (SELECT post_id, user_id FROM post_likes WHERE user_id = ?) ul ON ul.post_id = p.id
            WHERE p.created_at >= NOW() - INTERVAL ? HOUR
              AND p.subscriber_only = 0
              $typeFilter
            ORDER BY COALESCE(pts.score, 0) DESC, p.id DESC
            LIMIT $limit
        ";

        $stmt = $pdo->prepare($sql);
        $stmt->execute([$viewerId, $viewerId, $periodHours]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $posts = array_map(function ($r) use ($baseUrl) {
            $media = norm_url($r['media'] ?? '', $baseUrl);
            $avatar = norm_url($r['author_avatar'] ?? '', $baseUrl);
            $hasCross = $r['author_instagram'] || $r['author_tiktok'] || $r['author_youtube'];
            return [
                'id' => (string) $r['id'],
                'post_id' => (string) $r['id'],
                'user_id' => (string) $r['user_id'],
                'caption' => (string) ($r['caption'] ?? ''),
                'file_url' => $media,
                'media_url' => $media,
                'image_url' => $media,
                'video' => $media,
                'type' => (string) ($r['type'] ?? ''),
                'post_type' => (string) ($r['type'] ?? ''),
                'created_at' => (string) ($r['created_at'] ?? ''),
                'trend_score' => round(floatval($r['trend_score']), 4),
                'velocity' => round(floatval($r['velocity']), 2),
                'cross_boost' => (bool) $r['cross_boost'],
                'likes_count' => intval($r['likes_count']),
                'comments_count' => intval($r['comments_count']),
                'view_count' => intval($r['view_count']),
                'shares_count' => intval($r['shares_count']),
                'is_liked' => intval($r['is_liked']),
                'is_following' => intval($r['is_following']),
                'author_name' => (string) ($r['author_name'] ?? ''),
                'author_username' => (string) ($r['author_username'] ?? ''),
                'author_avatar' => $avatar,
                'author_subscription_status' => (string) ($r['author_subscription_status'] ?? 'inactive'),
                'author_cross_platform' => $hasCross ? true : false,
            ];
        }, $rows);

        out_json(200, ['status' => 'success', 'posts' => $posts, 'period' => $period]);
    }

    // ── ACTION: leaderboard (top viral users) ─────────────────────────────────
    if ($action === 'leaderboard') {
        $stmt = $pdo->prepare("
            SELECT
                u.id, u.name, u.username, u.profile_pic,
                COUNT(DISTINCT p.id)           AS post_count,
                COALESCE(SUM(pts.score),0)     AS total_viral_score,
                COALESCE(SUM(pts.velocity),0)  AS total_velocity,
                MAX(pts.cross_boost)           AS cross_boost,
                (SELECT COUNT(*) FROM follows f WHERE f.following_id=u.id) AS followers
            FROM users u
            JOIN posts p ON p.user_id=u.id AND p.created_at >= NOW()-INTERVAL ? HOUR
            LEFT JOIN post_trending_scores pts ON pts.post_id=p.id
            GROUP BY u.id
            ORDER BY total_viral_score DESC
            LIMIT $limit
        ");
        $stmt->execute([$periodHours]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $leaders = array_map(function ($r) use ($baseUrl) {
            return [
                'user_id' => (string) $r['id'],
                'name' => (string) $r['name'],
                'username' => (string) $r['username'],
                'avatar' => norm_url($r['profile_pic'] ?? '', $baseUrl),
                'post_count' => intval($r['post_count']),
                'viral_score' => round(floatval($r['total_viral_score']), 2),
                'velocity' => round(floatval($r['total_velocity']), 2),
                'cross_boost' => (bool) $r['cross_boost'],
                'followers' => intval($r['followers']),
            ];
        }, $rows);

        out_json(200, ['status' => 'success', 'leaderboard' => $leaders, 'period' => $period]);
    }

    // ── ACTION: hashtags ──────────────────────────────────────────────────────
    if ($action === 'hashtags') {
        $hasHashtagsTbl = false;
        try {
            $pdo->query("SELECT 1 FROM post_hashtags LIMIT 1");
            $hasHashtagsTbl = true;
        } catch (Throwable $_) {
        }

        if ($hasHashtagsTbl) {
            $stmt = $pdo->prepare("
                SELECT h.tag,
                    COUNT(*)                       AS post_count,
                    SUM(COALESCE(pts.score, 0))    AS trend_score,
                    SUM(COALESCE(pts.velocity, 0)) AS velocity
                FROM post_hashtags h
                LEFT JOIN post_trending_scores pts ON pts.post_id = h.post_id
                LEFT JOIN posts p ON p.id = h.post_id
                WHERE p.created_at >= NOW() - INTERVAL ? HOUR
                GROUP BY h.tag
                ORDER BY trend_score DESC, post_count DESC
                LIMIT $limit
            ");
            $stmt->execute([$periodHours]);
        } else {
            $stmt = $pdo->prepare("
                SELECT
                    LOWER(SUBSTRING_INDEX(SUBSTRING_INDEX(caption,'#',-1),' ',1)) AS tag,
                    COUNT(*)                       AS post_count,
                    SUM(COALESCE(pts.score, 0))    AS trend_score,
                    SUM(COALESCE(pts.velocity, 0)) AS velocity
                FROM posts p
                LEFT JOIN post_trending_scores pts ON pts.post_id = p.id
                WHERE caption LIKE '%#%'
                  AND p.created_at >= NOW() - INTERVAL ? HOUR
                GROUP BY tag
                HAVING tag != '' AND LENGTH(tag) > 1
                ORDER BY trend_score DESC, post_count DESC
                LIMIT $limit
            ");
            $stmt->execute([$periodHours]);
        }

        $hashtags = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $result = array_map(fn($r) => [
            'tag' => '#' . ltrim((string) $r['tag'], '#'),
            'post_count' => intval($r['post_count']),
            'trend_score' => round(floatval($r['trend_score']), 2),
            'velocity' => round(floatval($r['velocity']), 2),
        ], $hashtags);

        out_json(200, ['status' => 'success', 'hashtags' => $result, 'period' => $period]);
    }

    // ── ACTION: sounds ────────────────────────────────────────────────────────
    if ($action === 'sounds') {
        $hasSoundCol = false;
        try {
            $pdo->query("SELECT sound_name FROM posts LIMIT 1");
            $hasSoundCol = true;
        } catch (Throwable $_) {
        }

        if (!$hasSoundCol)
            out_json(200, ['status' => 'success', 'sounds' => []]);

        $stmt = $pdo->prepare("
            SELECT sound_name AS name,
                COUNT(*)                       AS use_count,
                SUM(COALESCE(pts.score, 0))    AS trend_score,
                SUM(COALESCE(pts.velocity, 0)) AS velocity
            FROM posts p
            LEFT JOIN post_trending_scores pts ON pts.post_id = p.id
            WHERE sound_name IS NOT NULL AND sound_name != ''
              AND p.created_at >= NOW() - INTERVAL ? HOUR
            GROUP BY sound_name
            ORDER BY trend_score DESC, use_count DESC
            LIMIT $limit
        ");
        $stmt->execute([$periodHours]);
        $sounds = $stmt->fetchAll(PDO::FETCH_ASSOC);

        out_json(200, ['status' => 'success', 'sounds' => $sounds, 'period' => $period]);
    }

    out_json(400, ['status' => 'error', 'message' => 'Unknown action. Use: posts|reels|hashtags|sounds|leaderboard']);

} catch (Throwable $e) {
    out_json(500, ['status' => 'error', 'message' => $e->getMessage()]);
}
