<?php
/**
 * api_hashtags.php — Hashtag search & ranked post results
 *
 * GET  ?action=search&q=love        — ranked posts matching hashtag
 * GET  ?action=trending&limit=20    — top trending hashtags (delegates to api_trending)
 * GET  ?action=related&tag=love     — hashtags co-occurring with given tag
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

function hout(int $code, array $payload): void
{
    http_response_code($code);
    echo json_encode($payload);
    exit;
}

function hnorm(?string $url, string $base): string
{
    if (!$url || trim($url) === '')
        return '';
    $url = trim($url);
    if (strpos($url, 'uploads/') !== false && !preg_match('~^https?://~i', $url))
        return 'https://goreto.org/ekloadmin/' . ltrim($url, '/');
    if (preg_match('~^https?://~i', $url))
        return $url;
    return rtrim($base, '/') . '/' . ltrim($url, '/');
}

try {
    if (!isset($pdo) || !($pdo instanceof PDO))
        hout(500, ['status' => 'error', 'message' => 'DB unavailable']);

    $baseUrl = rtrim($config['base_url'] ?? 'https://goreto.org/ekloadmin/api/v1', '/');
    $action = strtolower(trim($_GET['action'] ?? 'search'));
    $limit = max(1, min(100, intval($_GET['limit'] ?? 30)));
    $page = max(1, intval($_GET['page'] ?? 1));
    $offset = ($page - 1) * $limit;

    $viewerId = 0;
    try {
        $v = requireUser($pdo);
        $viewerId = intval($v['id']);
    } catch (Throwable $_) {
    }

    // ── Ensure trending table ─────────────────────────────────────────────────
    $pdo->exec("CREATE TABLE IF NOT EXISTS post_trending_scores (
        post_id INT PRIMARY KEY,
        score FLOAT NOT NULL DEFAULT 0,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    // ── ACTION: search ────────────────────────────────────────────────────────
    if ($action === 'search') {
        $q = trim($_GET['q'] ?? '');
        if ($q === '')
            hout(400, ['status' => 'error', 'message' => 'q is required']);

        // Normalise: strip leading # and lowercase
        $tag = strtolower(ltrim($q, '#'));

        // Check if dedicated hashtag table exists
        $hasHashtagsTbl = false;
        try {
            $pdo->query("SELECT 1 FROM post_hashtags LIMIT 1");
            $hasHashtagsTbl = true;
        } catch (Throwable $_) {
        }

        if ($hasHashtagsTbl) {
            // Join through post_hashtags for exact tag match
            $sql = "
                SELECT
                    p.id, p.user_id, p.caption, p.file_url AS media, p.type, p.created_at,
                    COALESCE(pts.score, 0) AS trend_score,
                    COALESCE(lc.likes_count, 0) AS likes_count,
                    COALESCE(cc.comments_count, 0) AS comments_count,
                    COALESCE(vc.views, 0) AS view_count,
                    u.name AS author_name, u.username AS author_username,
                    u.profile_pic AS author_avatar,
                    u.subscription_status AS author_subscription_status,
                    CASE WHEN fl.follower_id IS NOT NULL THEN 1 ELSE 0 END AS is_following,
                    CASE WHEN ul.user_id IS NOT NULL THEN 1 ELSE 0 END AS is_liked
                FROM post_hashtags h
                JOIN posts p ON p.id = h.post_id
                LEFT JOIN post_trending_scores pts ON pts.post_id = p.id
                LEFT JOIN users u ON u.id = p.user_id
                LEFT JOIN (SELECT post_id, COUNT(*) AS likes_count FROM post_likes GROUP BY post_id) lc ON lc.post_id = p.id
                LEFT JOIN (SELECT post_id, COUNT(*) AS comments_count FROM post_comments GROUP BY post_id) cc ON cc.post_id = p.id
                LEFT JOIN (SELECT post_id, COUNT(*) AS views FROM post_views GROUP BY post_id) vc ON vc.post_id = p.id
                LEFT JOIN follows fl ON fl.follower_id = ? AND fl.following_id = p.user_id
                LEFT JOIN (SELECT post_id, user_id FROM post_likes WHERE user_id = ?) ul ON ul.post_id = p.id
                WHERE LOWER(h.tag) = ?
                  AND p.subscriber_only = 0
                ORDER BY COALESCE(pts.score, 0) DESC, lc.likes_count DESC, p.id DESC
                LIMIT $limit OFFSET $offset
            ";
            $stmt = $pdo->prepare($sql);
            $stmt->execute([$viewerId, $viewerId, $tag]);
        } else {
            // Fallback: LIKE search on caption
            $sql = "
                SELECT
                    p.id, p.user_id, p.caption, p.file_url AS media, p.type, p.created_at,
                    COALESCE(pts.score, 0) AS trend_score,
                    COALESCE(lc.likes_count, 0) AS likes_count,
                    COALESCE(cc.comments_count, 0) AS comments_count,
                    COALESCE(vc.views, 0) AS view_count,
                    u.name AS author_name, u.username AS author_username,
                    u.profile_pic AS author_avatar,
                    u.subscription_status AS author_subscription_status,
                    CASE WHEN fl.follower_id IS NOT NULL THEN 1 ELSE 0 END AS is_following,
                    CASE WHEN ul.user_id IS NOT NULL THEN 1 ELSE 0 END AS is_liked
                FROM posts p
                LEFT JOIN post_trending_scores pts ON pts.post_id = p.id
                LEFT JOIN users u ON u.id = p.user_id
                LEFT JOIN (SELECT post_id, COUNT(*) AS likes_count FROM post_likes GROUP BY post_id) lc ON lc.post_id = p.id
                LEFT JOIN (SELECT post_id, COUNT(*) AS comments_count FROM post_comments GROUP BY post_id) cc ON cc.post_id = p.id
                LEFT JOIN (SELECT post_id, COUNT(*) AS views FROM post_views GROUP BY post_id) vc ON vc.post_id = p.id
                LEFT JOIN follows fl ON fl.follower_id = ? AND fl.following_id = p.user_id
                LEFT JOIN (SELECT post_id, user_id FROM post_likes WHERE user_id = ?) ul ON ul.post_id = p.id
                WHERE (LOWER(p.caption) LIKE ? OR LOWER(p.hashtags) LIKE ?)
                  AND p.subscriber_only = 0
                ORDER BY COALESCE(pts.score, 0) DESC, lc.likes_count DESC, p.id DESC
                LIMIT $limit OFFSET $offset
            ";
            $like = '%#' . $tag . '%';
            $stmt = $pdo->prepare($sql);
            $stmt->execute([$viewerId, $viewerId, $like, $like]);
        }

        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $posts = array_map(function ($r) use ($baseUrl) {
            $media = hnorm($r['media'] ?? '', $baseUrl);
            $avatar = hnorm($r['author_avatar'] ?? '', $baseUrl);
            return [
                'id' => (string) $r['id'],
                'post_id' => (string) $r['id'],
                'user_id' => (string) $r['user_id'],
                'caption' => (string) ($r['caption'] ?? ''),
                'file_url' => $media,
                'media_url' => $media,
                'image_url' => $media,
                'type' => (string) ($r['type'] ?? ''),
                'created_at' => (string) ($r['created_at'] ?? ''),
                'trend_score' => round(floatval($r['trend_score']), 4),
                'likes_count' => intval($r['likes_count']),
                'comments_count' => intval($r['comments_count']),
                'view_count' => intval($r['view_count']),
                'is_liked' => intval($r['is_liked']),
                'is_following' => intval($r['is_following']),
                'author_name' => (string) ($r['author_name'] ?? ''),
                'author_username' => (string) ($r['author_username'] ?? ''),
                'author_avatar' => $avatar,
                'author_subscription_status' => (string) ($r['author_subscription_status'] ?? 'inactive'),
            ];
        }, $rows);

        hout(200, [
            'status' => 'success',
            'tag' => '#' . $tag,
            'page' => $page,
            'posts' => $posts,
        ]);
    }

    // ── ACTION: trending ──────────────────────────────────────────────────────
    if ($action === 'trending') {
        // Delegate to api_trending.php logic inline
        $period = strtolower($_GET['period'] ?? '24h');
        $periodHours = match ($period) {
            '7d' => 168,
            '30d' => 720,
            'all' => 99999,
            default => 24,
        };

        $hasHashtagsTbl = false;
        try {
            $pdo->query("SELECT 1 FROM post_hashtags LIMIT 1");
            $hasHashtagsTbl = true;
        } catch (Throwable $_) {
        }

        if ($hasHashtagsTbl) {
            $stmt = $pdo->prepare("
                SELECT h.tag, COUNT(*) AS post_count,
                       SUM(COALESCE(pts.score, 0)) AS trend_score
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
                    LOWER(SUBSTRING_INDEX(SUBSTRING_INDEX(caption, '#', -1), ' ', 1)) AS tag,
                    COUNT(*) AS post_count,
                    SUM(COALESCE(pts.score, 0)) AS trend_score
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

        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        $hashtags = array_map(fn($r) => [
            'tag' => '#' . ltrim((string) $r['tag'], '#'),
            'post_count' => intval($r['post_count']),
            'trend_score' => round(floatval($r['trend_score']), 2),
        ], $rows);

        hout(200, ['status' => 'success', 'hashtags' => $hashtags, 'period' => $period]);
    }

    // ── ACTION: related ───────────────────────────────────────────────────────
    if ($action === 'related') {
        $tag = strtolower(ltrim(trim($_GET['tag'] ?? ''), '#'));
        if ($tag === '')
            hout(400, ['status' => 'error', 'message' => 'tag is required']);

        $hasHashtagsTbl = false;
        try {
            $pdo->query("SELECT 1 FROM post_hashtags LIMIT 1");
            $hasHashtagsTbl = true;
        } catch (Throwable $_) {
        }

        if ($hasHashtagsTbl) {
            // Find posts with this tag, then find other tags on those posts
            $stmt = $pdo->prepare("
                SELECT h2.tag, COUNT(*) AS co_count
                FROM post_hashtags h1
                JOIN post_hashtags h2 ON h2.post_id = h1.post_id AND LOWER(h2.tag) != ?
                WHERE LOWER(h1.tag) = ?
                GROUP BY h2.tag
                ORDER BY co_count DESC
                LIMIT $limit
            ");
            $stmt->execute([$tag, $tag]);
            $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
            $related = array_map(fn($r) => [
                'tag' => '#' . ltrim((string) $r['tag'], '#'),
                'co_count' => intval($r['co_count']),
            ], $rows);
        } else {
            $related = [];
        }

        hout(200, ['status' => 'success', 'tag' => '#' . $tag, 'related' => $related]);
    }

    hout(400, ['status' => 'error', 'message' => 'Unknown action']);

} catch (Throwable $e) {
    hout(500, ['status' => 'error', 'message' => $e->getMessage()]);
}
