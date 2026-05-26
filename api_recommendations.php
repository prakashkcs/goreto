<?php
/**
 * api_recommendations.php — Personalised user & content recommendations
 *
 * GET  ?action=users              — "People you may know" (collaborative filtering)
 * GET  ?action=posts&interests=.. — Recommended posts based on interest vector
 * GET  ?action=creators           — Top creators to follow based on engagement
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

function rout(int $code, array $payload): void
{
    http_response_code($code);
    echo json_encode($payload);
    exit;
}

function rnorm(?string $url, string $base): string
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
        rout(500, ['status' => 'error', 'message' => 'DB unavailable']);

    // Auth required for personalised results
    try {
        $user = requireUser($pdo);
    } catch (Throwable $_) {
        rout(401, ['status' => 'error', 'message' => 'Authentication required']);
    }

    $userId = intval($user['id']);
    $baseUrl = rtrim($config['base_url'] ?? 'https://goreto.org/ekloadmin/api/v1', '/');
    $action = strtolower(trim($_GET['action'] ?? 'users'));
    $limit = max(1, min(50, intval($_GET['limit'] ?? 20)));

    // ── Ensure trending table ─────────────────────────────────────────────────
    $pdo->exec("CREATE TABLE IF NOT EXISTS post_trending_scores (
        post_id INT PRIMARY KEY,
        score FLOAT NOT NULL DEFAULT 0,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    // ── ACTION: users — "People you may know" ────────────────────────────────
    if ($action === 'users') {
        /**
         * Strategy (layered, merged by score):
         * 1. Followers of people you follow (2nd-degree connections)
         * 2. Users who liked the same posts as you
         * 3. Users with matching interests (match_profiles)
         * 4. Popular users you don't follow yet (fallback)
         */

        $candidates = []; // userId => score

        // ── Layer 1: 2nd-degree follows ──────────────────────────────────────
        try {
            $stmt = $pdo->prepare("
                SELECT f2.following_id AS uid, COUNT(*) AS mutual_count
                FROM follows f1
                JOIN follows f2 ON f2.follower_id = f1.following_id
                WHERE f1.follower_id = ?
                  AND f2.following_id != ?
                  AND f2.following_id NOT IN (
                      SELECT following_id FROM follows WHERE follower_id = ?
                  )
                GROUP BY f2.following_id
                ORDER BY mutual_count DESC
                LIMIT 100
            ");
            $stmt->execute([$userId, $userId, $userId]);
            foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
                $uid = intval($r['uid']);
                $candidates[$uid] = ($candidates[$uid] ?? 0) + intval($r['mutual_count']) * 3.0;
            }
        } catch (Throwable $_) {
        }

        // ── Layer 2: Co-likers (liked same posts) ─────────────────────────────
        try {
            $stmt = $pdo->prepare("
                SELECT pl2.user_id AS uid, COUNT(*) AS shared_likes
                FROM post_likes pl1
                JOIN post_likes pl2 ON pl2.post_id = pl1.post_id AND pl2.user_id != ?
                WHERE pl1.user_id = ?
                  AND pl2.user_id NOT IN (
                      SELECT following_id FROM follows WHERE follower_id = ?
                  )
                GROUP BY pl2.user_id
                ORDER BY shared_likes DESC
                LIMIT 100
            ");
            $stmt->execute([$userId, $userId, $userId]);
            foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
                $uid = intval($r['uid']);
                $candidates[$uid] = ($candidates[$uid] ?? 0) + intval($r['shared_likes']) * 1.5;
            }
        } catch (Throwable $_) {
        }

        // ── Layer 3: Matching interests from match_profiles ───────────────────
        try {
            $myInterests = '';
            $stmt = $pdo->prepare("SELECT interests FROM match_profiles WHERE user_id = ? LIMIT 1");
            $stmt->execute([$userId]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if ($row)
                $myInterests = strtolower($row['interests'] ?? '');

            if ($myInterests !== '') {
                $interestList = array_filter(array_map('trim', explode(',', $myInterests)));
                if (!empty($interestList)) {
                    // Build LIKE conditions for each interest
                    $likes = implode(' OR ', array_fill(0, count($interestList), 'LOWER(mp.interests) LIKE ?'));
                    $params = array_map(fn($i) => '%' . $i . '%', $interestList);
                    $params[] = $userId;

                    $stmt2 = $pdo->prepare("
                        SELECT mp.user_id AS uid, COUNT(*) AS interest_matches
                        FROM match_profiles mp
                        WHERE ($likes)
                          AND mp.user_id != ?
                          AND mp.user_id NOT IN (
                              SELECT following_id FROM follows WHERE follower_id = $userId
                          )
                        GROUP BY mp.user_id
                        ORDER BY interest_matches DESC
                        LIMIT 100
                    ");
                    $stmt2->execute($params);
                    foreach ($stmt2->fetchAll(PDO::FETCH_ASSOC) as $r) {
                        $uid = intval($r['uid']);
                        $candidates[$uid] = ($candidates[$uid] ?? 0) + intval($r['interest_matches']) * 2.0;
                    }
                }
            }
        } catch (Throwable $_) {
        }

        // ── Layer 4: Popular users fallback ──────────────────────────────────
        if (count($candidates) < $limit) {
            try {
                $stmt = $pdo->prepare("
                    SELECT u.id AS uid,
                           (SELECT COUNT(*) FROM follows WHERE following_id = u.id) AS follower_count
                    FROM users u
                    WHERE u.id != ?
                      AND u.id NOT IN (
                          SELECT following_id FROM follows WHERE follower_id = ?
                      )
                    ORDER BY follower_count DESC
                    LIMIT 50
                ");
                $stmt->execute([$userId, $userId]);
                foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $r) {
                    $uid = intval($r['uid']);
                    if (!isset($candidates[$uid])) {
                        $candidates[$uid] = floatval($r['follower_count']) * 0.1;
                    }
                }
            } catch (Throwable $_) {
            }
        }

        // Sort by score, take top $limit
        arsort($candidates);
        $topIds = array_slice(array_keys($candidates), 0, $limit);

        if (empty($topIds)) {
            rout(200, ['status' => 'success', 'users' => []]);
        }

        $placeholders = implode(',', array_fill(0, count($topIds), '?'));
        $stmt = $pdo->prepare("
            SELECT u.id, u.name, u.username, u.profile_pic, u.bio,
                   u.subscription_status,
                   (SELECT COUNT(*) FROM follows WHERE following_id = u.id) AS followers_count,
                   (SELECT COUNT(*) FROM posts WHERE user_id = u.id) AS posts_count,
                   CASE WHEN fl.follower_id IS NOT NULL THEN 1 ELSE 0 END AS is_following
            FROM users u
            LEFT JOIN follows fl ON fl.follower_id = ? AND fl.following_id = u.id
            WHERE u.id IN ($placeholders)
        ");
        $stmt->execute(array_merge([$userId], $topIds));
        $userRows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // Re-sort by candidate score
        usort(
            $userRows,
            fn($a, $b) =>
            ($candidates[intval($b['id'])] ?? 0) <=> ($candidates[intval($a['id'])] ?? 0)
        );

        $users = array_map(function ($r) use ($baseUrl, $candidates) {
            $avatar = rnorm($r['profile_pic'] ?? '', $baseUrl);
            return [
                'id' => (string) $r['id'],
                'name' => (string) ($r['name'] ?? ''),
                'username' => (string) ($r['username'] ?? ''),
                'profile_pic' => $avatar,
                'avatar' => $avatar,
                'bio' => (string) ($r['bio'] ?? ''),
                'subscription_status' => (string) ($r['subscription_status'] ?? 'inactive'),
                'followers_count' => intval($r['followers_count']),
                'posts_count' => intval($r['posts_count']),
                'is_following' => intval($r['is_following']),
                'relevance_score' => round($candidates[intval($r['id'])] ?? 0, 2),
            ];
        }, $userRows);

        rout(200, ['status' => 'success', 'users' => $users]);
    }

    // ── ACTION: posts — interest-based post recommendations ──────────────────
    if ($action === 'posts') {
        // Accept interest vector from client (JSON map of category => weight)
        $interestsParam = trim($_GET['interests'] ?? '');
        $interestWeights = [];
        if ($interestsParam !== '') {
            try {
                $decoded = json_decode($interestsParam, true);
                if (is_array($decoded))
                    $interestWeights = $decoded;
            } catch (Throwable $_) {
            }
        }

        // Build ORDER BY expression using interest weights
        // We score posts by: trending_score + following_boost + interest_match
        $interestScore = '0';
        foreach ($interestWeights as $cat => $weight) {
            $cat = preg_replace('/[^a-z0-9_]/', '', strtolower($cat));
            $weight = round(floatval($weight), 4);
            if ($cat === '' || $weight <= 0)
                continue;
            $interestScore .= " + (CASE WHEN LOWER(COALESCE(p.caption,'')) LIKE '%{$cat}%' OR LOWER(COALESCE(p.hashtags,'')) LIKE '%{$cat}%' THEN {$weight} ELSE 0 END)";
        }

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
                CASE WHEN ul.user_id IS NOT NULL THEN 1 ELSE 0 END AS is_liked,
                (
                    COALESCE(pts.score, 0) * 0.4
                    + (CASE WHEN fl.follower_id IS NOT NULL THEN 2.0 ELSE 0 END)
                    + ($interestScore)
                    + (LOG(1 + COALESCE(lc.likes_count, 0)) * 0.3)
                    - (TIMESTAMPDIFF(HOUR, p.created_at, NOW()) * 0.02)
                ) AS rec_score
            FROM posts p
            LEFT JOIN post_trending_scores pts ON pts.post_id = p.id
            LEFT JOIN users u ON u.id = p.user_id
            LEFT JOIN (SELECT post_id, COUNT(*) AS likes_count FROM post_likes GROUP BY post_id) lc ON lc.post_id = p.id
            LEFT JOIN (SELECT post_id, COUNT(*) AS comments_count FROM post_comments GROUP BY post_id) cc ON cc.post_id = p.id
            LEFT JOIN (SELECT post_id, COUNT(*) AS views FROM post_views GROUP BY post_id) vc ON vc.post_id = p.id
            LEFT JOIN follows fl ON fl.follower_id = ? AND fl.following_id = p.user_id
            LEFT JOIN (SELECT post_id, user_id FROM post_likes WHERE user_id = ?) ul ON ul.post_id = p.id
            WHERE p.subscriber_only = 0
              AND p.created_at >= NOW() - INTERVAL 30 DAY
            ORDER BY rec_score DESC
            LIMIT $limit
        ";

        $stmt = $pdo->prepare($sql);
        $stmt->execute([$userId, $userId]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $posts = array_map(function ($r) use ($baseUrl) {
            $media = rnorm($r['media'] ?? '', $baseUrl);
            $avatar = rnorm($r['author_avatar'] ?? '', $baseUrl);
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
                'rec_score' => round(floatval($r['rec_score']), 4),
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

        rout(200, ['status' => 'success', 'posts' => $posts]);
    }

    // ── ACTION: creators — top creators to follow ─────────────────────────────
    if ($action === 'creators') {
        $stmt = $pdo->prepare("
            SELECT
                u.id, u.name, u.username, u.profile_pic, u.bio,
                u.subscription_status,
                COUNT(DISTINCT f.follower_id) AS followers_count,
                COUNT(DISTINCT p.id) AS posts_count,
                COALESCE(SUM(pts.score), 0) AS total_trend_score,
                CASE WHEN fl.follower_id IS NOT NULL THEN 1 ELSE 0 END AS is_following
            FROM users u
            LEFT JOIN follows f ON f.following_id = u.id
            LEFT JOIN posts p ON p.user_id = u.id
            LEFT JOIN post_trending_scores pts ON pts.post_id = p.id
            LEFT JOIN follows fl ON fl.follower_id = ? AND fl.following_id = u.id
            WHERE u.id != ?
              AND fl.follower_id IS NULL
            GROUP BY u.id
            ORDER BY (total_trend_score * 0.5 + LOG(1 + followers_count) * 2) DESC
            LIMIT $limit
        ");
        $stmt->execute([$userId, $userId]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $creators = array_map(function ($r) use ($baseUrl) {
            $avatar = rnorm($r['profile_pic'] ?? '', $baseUrl);
            return [
                'id' => (string) $r['id'],
                'name' => (string) ($r['name'] ?? ''),
                'username' => (string) ($r['username'] ?? ''),
                'profile_pic' => $avatar,
                'avatar' => $avatar,
                'bio' => (string) ($r['bio'] ?? ''),
                'subscription_status' => (string) ($r['subscription_status'] ?? 'inactive'),
                'followers_count' => intval($r['followers_count']),
                'posts_count' => intval($r['posts_count']),
                'is_following' => intval($r['is_following']),
            ];
        }, $rows);

        rout(200, ['status' => 'success', 'creators' => $creators]);
    }

    rout(400, ['status' => 'error', 'message' => 'Unknown action']);

} catch (Throwable $e) {
    rout(500, ['status' => 'error', 'message' => $e->getMessage()]);
}
