<?php
// analytics.php — Viral post analytics & impression tracking
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

function out(int $code, array $arr): void
{
    http_response_code($code);
    echo json_encode($arr);
    exit;
}

// Attempt to resolve authenticated user without hard-blocking on 401.
// Returns user_id (int > 0) on success, or 0 if unauthenticated.
function auth_user_id(PDO $pdo): int
{
    try {
        $user = requireUser($pdo);
        return (int)($user['id'] ?? 0);
    } catch (Throwable $e) {
        return 0;
    }
}

// ---------------------------------------------------------------------------
// Schema migrations (safe, idempotent)
// ---------------------------------------------------------------------------
try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS `post_impressions` (
        `id`            BIGINT AUTO_INCREMENT PRIMARY KEY,
        `post_id`       INT NOT NULL,
        `user_id`       INT NOT NULL DEFAULT 0,
        `source`        ENUM('feed','explore','following','reels','search','profile') NOT NULL DEFAULT 'feed',
        `watch_pct`     TINYINT NOT NULL DEFAULT 0,
        `time_spent_ms` INT NOT NULL DEFAULT 0,
        `rewatched`     TINYINT(1) NOT NULL DEFAULT 0,
        `created_at`    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX `idx_pi_post_id`        (`post_id`),
        INDEX `idx_pi_user_created`   (`user_id`, `created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
} catch (Throwable $e) { /* table already exists */ }

try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS `post_virality` (
        `post_id`              INT PRIMARY KEY,
        `impression_count`     INT NOT NULL DEFAULT 0,
        `unique_viewers`       INT NOT NULL DEFAULT 0,
        `avg_watch_pct`        FLOAT NOT NULL DEFAULT 0,
        `completion_rate`      FLOAT NOT NULL DEFAULT 0,
        `share_count`          INT NOT NULL DEFAULT 0,
        `save_count`           INT NOT NULL DEFAULT 0,
        `profile_visit_count`  INT NOT NULL DEFAULT 0,
        `rewatch_count`        INT NOT NULL DEFAULT 0,
        `viral_score`          FLOAT NOT NULL DEFAULT 0,
        `velocity_1h`          FLOAT NOT NULL DEFAULT 1.0,
        `velocity_24h`         FLOAT NOT NULL DEFAULT 1.0,
        `is_viral`             TINYINT(1) NOT NULL DEFAULT 0,
        `last_computed`        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        `updated_at`           TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX `idx_pv_viral_score` (`viral_score`),
        INDEX `idx_pv_is_viral`    (`is_viral`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
} catch (Throwable $e) { /* table already exists */ }

// Ensure post_profile_visits table for profile_visit tracking
try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS `post_profile_visits` (
        `id`         INT AUTO_INCREMENT PRIMARY KEY,
        `post_id`    INT NOT NULL,
        `user_id`    INT NOT NULL DEFAULT 0,
        `creator_id` INT NOT NULL DEFAULT 0,
        `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX `idx_ppv_post_id` (`post_id`),
        INDEX `idx_ppv_creator` (`creator_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
} catch (Throwable $e) { }

// ---------------------------------------------------------------------------
// Request parsing
// ---------------------------------------------------------------------------
$raw  = file_get_contents('php://input');
$json = json_decode($raw, true);
if (!is_array($json)) $json = [];
$data = array_merge($_POST, $json);

$action = $data['action'] ?? $_GET['action'] ?? '';

// ---------------------------------------------------------------------------
// ACTION: batch
// Accepts array of events; does NOT require auth (uses token if present).
// ---------------------------------------------------------------------------
if ($action === 'batch') {
    $uid    = auth_user_id($pdo);
    $events = $data['events'] ?? [];
    if (!is_array($events)) {
        out(400, ['status' => 'error', 'message' => 'events must be an array']);
    }

    $processed = 0;

    $stmtImpression = $pdo->prepare(
        "INSERT INTO post_impressions (post_id, user_id, source, watch_pct, time_spent_ms, rewatched)
         VALUES (?, ?, ?, ?, ?, ?)"
    );
    $stmtEngage = $pdo->prepare(
        "INSERT IGNORE INTO post_engagements (post_id, user_id, action, watch_seconds)
         VALUES (?, ?, ?, 0)"
    );

    foreach ($events as $ev) {
        if (!is_array($ev)) continue;
        $type    = (string)($ev['type'] ?? '');
        $post_id = (int)($ev['post_id'] ?? 0);
        if ($post_id <= 0) continue;

        try {
            if ($type === 'impression' || $type === 'watch_complete') {
                $source       = in_array($ev['source'] ?? '', ['feed','explore','following','reels','search','profile'])
                                ? $ev['source'] : 'feed';
                $watch_pct    = max(0, min(100, (int)($ev['watch_pct'] ?? 0)));
                $time_ms      = max(0, (int)($ev['time_spent_ms'] ?? 0));
                $rewatched    = ($ev['rewatched'] ?? false) ? 1 : 0;

                // For watch_complete, derive time from duration_sec if not provided
                if ($type === 'watch_complete' && $time_ms === 0) {
                    $dur   = max(0, (int)($ev['duration_sec'] ?? 0));
                    $time_ms = (int)($dur * ($watch_pct / 100.0) * 1000);
                }

                $stmtImpression->execute([$post_id, $uid, $source, $watch_pct, $time_ms, $rewatched]);

                // Also upsert post_views for unique-view compatibility
                try {
                    $pdo->prepare(
                        "INSERT IGNORE INTO post_views (post_id, user_id, ip_address) VALUES (?, ?, ?)"
                    )->execute([$post_id, $uid ?: null, $_SERVER['REMOTE_ADDR'] ?? null]);
                } catch (Throwable $e) { }

                $processed++;

            } elseif ($type === 'save') {
                if ($uid > 0) {
                    $stmtEngage->execute([$post_id, $uid, 'save']);
                    $processed++;
                }

            } elseif ($type === 'share') {
                if ($uid > 0) {
                    $stmtEngage->execute([$post_id, $uid, 'share']);
                    $processed++;
                }

            } elseif ($type === 'profile_visit') {
                $creator_id = (int)($ev['creator_id'] ?? 0);
                $pdo->prepare(
                    "INSERT INTO post_profile_visits (post_id, user_id, creator_id) VALUES (?, ?, ?)"
                )->execute([$post_id, $uid, $creator_id]);
                $processed++;
            }
        } catch (Throwable $e) {
            // Skip individual failed events; keep processing the rest
        }
    }

    out(200, ['status' => 'ok', 'processed' => $processed]);
}

// ---------------------------------------------------------------------------
// ACTION: impression
// Single impression event (GET or POST). Auth optional.
// ---------------------------------------------------------------------------
if ($action === 'impression') {
    $uid       = auth_user_id($pdo);
    $post_id   = (int)($data['post_id'] ?? $_GET['post_id'] ?? 0);
    if ($post_id <= 0) out(400, ['status' => 'error', 'message' => 'post_id required']);

    $sourceRaw = (string)($data['source'] ?? $_GET['source'] ?? 'feed');
    $source    = in_array($sourceRaw, ['feed','explore','following','reels','search','profile']) ? $sourceRaw : 'feed';
    $watch_pct = max(0, min(100, (int)($data['watch_pct'] ?? $_GET['watch_pct'] ?? 0)));
    $time_ms   = max(0, (int)($data['time_spent_ms'] ?? $_GET['time_spent_ms'] ?? 0));
    $rewatched = (int)(bool)($data['rewatched'] ?? $_GET['rewatched'] ?? 0);

    $pdo->prepare(
        "INSERT INTO post_impressions (post_id, user_id, source, watch_pct, time_spent_ms, rewatched)
         VALUES (?, ?, ?, ?, ?, ?)"
    )->execute([$post_id, $uid, $source, $watch_pct, $time_ms, $rewatched]);

    // Keep post_views in sync for legacy compatibility
    try {
        $pdo->prepare(
            "INSERT IGNORE INTO post_views (post_id, user_id, ip_address) VALUES (?, ?, ?)"
        )->execute([$post_id, $uid ?: null, $_SERVER['REMOTE_ADDR'] ?? null]);
    } catch (Throwable $e) { }

    out(200, ['status' => 'ok', 'message' => 'impression recorded']);
}

// ---------------------------------------------------------------------------
// ACTION: watch_complete
// Video fully watched or near-complete. Requires auth.
// ---------------------------------------------------------------------------
if ($action === 'watch_complete') {
    $user    = requireUser($pdo);
    $uid     = (int)$user['id'];
    $post_id = (int)($data['post_id'] ?? 0);
    if ($post_id <= 0) out(400, ['status' => 'error', 'message' => 'post_id required']);

    $watch_pct   = max(0, min(100, (int)($data['watch_pct'] ?? 100)));
    $duration    = max(0, (int)($data['duration_sec'] ?? 0));
    $watch_secs  = (int)($duration * $watch_pct / 100.0);

    // Upsert watch engagement with accumulated seconds
    $pdo->prepare(
        "INSERT INTO post_engagements (post_id, user_id, action, watch_seconds)
         VALUES (?, ?, 'watch', ?)
         ON DUPLICATE KEY UPDATE
           watch_seconds = GREATEST(watch_seconds, VALUES(watch_seconds)),
           updated_at    = NOW()"
    )->execute([$post_id, $uid, $watch_secs]);

    // Also record in post_impressions with watch percentage
    $pdo->prepare(
        "INSERT INTO post_impressions (post_id, user_id, source, watch_pct, time_spent_ms, rewatched)
         VALUES (?, ?, 'feed', ?, ?, 0)"
    )->execute([$post_id, $uid, $watch_pct, $watch_secs * 1000]);

    out(200, ['status' => 'ok', 'message' => 'watch_complete recorded']);
}

// ---------------------------------------------------------------------------
// ACTION: save
// Requires auth.
// ---------------------------------------------------------------------------
if ($action === 'save') {
    $user    = requireUser($pdo);
    $uid     = (int)$user['id'];
    $post_id = (int)($data['post_id'] ?? 0);
    if ($post_id <= 0) out(400, ['status' => 'error', 'message' => 'post_id required']);

    $pdo->prepare(
        "INSERT IGNORE INTO post_engagements (post_id, user_id, action, watch_seconds)
         VALUES (?, ?, 'save', 0)"
    )->execute([$post_id, $uid]);

    out(200, ['status' => 'ok', 'message' => 'post saved']);
}

// ---------------------------------------------------------------------------
// ACTION: profile_visit
// Requires auth.
// ---------------------------------------------------------------------------
if ($action === 'profile_visit') {
    $user       = requireUser($pdo);
    $uid        = (int)$user['id'];
    $post_id    = (int)($data['post_id'] ?? 0);
    $creator_id = (int)($data['creator_id'] ?? 0);
    if ($post_id <= 0) out(400, ['status' => 'error', 'message' => 'post_id required']);

    $pdo->prepare(
        "INSERT INTO post_profile_visits (post_id, user_id, creator_id) VALUES (?, ?, ?)"
    )->execute([$post_id, $uid, $creator_id]);

    out(200, ['status' => 'ok', 'message' => 'profile_visit recorded']);
}

// ---------------------------------------------------------------------------
// ACTION: compute_viral
// Recompute viral scores for posts active in last 7 days.
// Intended for cron / internal use; requires auth (admin or any valid user).
// ---------------------------------------------------------------------------
if ($action === 'compute_viral') {
    requireUser($pdo); // must be authenticated

    // Fetch posts that have received impressions in the last 7 days
    $activePosts = $pdo->query(
        "SELECT DISTINCT post_id FROM post_impressions
         WHERE created_at >= NOW() - INTERVAL 7 DAY"
    )->fetchAll(PDO::FETCH_COLUMN);

    // Also include any post in post_virality that hasn't been recomputed recently
    $existing = $pdo->query(
        "SELECT post_id FROM post_virality
         WHERE updated_at < NOW() - INTERVAL 1 HOUR"
    )->fetchAll(PDO::FETCH_COLUMN);

    $postIds = array_values(array_unique(array_merge($activePosts, $existing)));

    $updated = 0;

    foreach ($postIds as $pid) {
        $pid = (int)$pid;
        if ($pid <= 0) continue;

        try {
            // ── Impression metrics (last 24h) ──
            $imp = $pdo->prepare(
                "SELECT
                    COUNT(*)                                          AS impression_count,
                    COUNT(DISTINCT user_id)                          AS unique_viewers,
                    AVG(CASE WHEN watch_pct > 0 THEN watch_pct END)  AS avg_watch_pct,
                    SUM(CASE WHEN watch_pct >= 80 THEN 1 ELSE 0 END) AS completions,
                    SUM(rewatched)                                   AS rewatch_count
                 FROM post_impressions
                 WHERE post_id = ? AND created_at >= NOW() - INTERVAL 24 HOUR"
            );
            $imp->execute([$pid]);
            $im = $imp->fetch(PDO::FETCH_ASSOC);

            $impression_count = max(1, (int)($im['impression_count'] ?? 0));
            $unique_viewers   = (int)($im['unique_viewers']   ?? 0);
            $avg_watch_pct    = (float)($im['avg_watch_pct']  ?? 0);
            $completions      = (int)($im['completions']      ?? 0);
            $rewatch_count    = (int)($im['rewatch_count']    ?? 0);
            $completion_rate  = $completions / $impression_count;
            $rewatch_rate     = $rewatch_count / $impression_count;

            // ── Post base metrics ──
            $postData = $pdo->prepare(
                "SELECT
                    COALESCE(p.likes_count, lc.likes_count, 0)       AS like_count,
                    COALESCE(p.comments_count, cc.comments_count, 0)  AS comment_count,
                    p.created_at
                 FROM posts p
                 LEFT JOIN (SELECT post_id, COUNT(*) AS likes_count    FROM post_likes    GROUP BY post_id) lc ON lc.post_id = p.id
                 LEFT JOIN (SELECT post_id, COUNT(*) AS comments_count FROM post_comments GROUP BY post_id) cc ON cc.post_id = p.id
                 WHERE p.id = ? LIMIT 1"
            );
            $postData->execute([$pid]);
            $pd = $postData->fetch(PDO::FETCH_ASSOC);
            if (!$pd) continue;

            $like_count    = (float)($pd['like_count']    ?? 0);
            $comment_count = (float)($pd['comment_count'] ?? 0);
            $post_created  = $pd['created_at'] ?? null;

            // ── Engagement counts ──
            $engData = $pdo->prepare(
                "SELECT action, COUNT(*) AS cnt
                 FROM post_engagements
                 WHERE post_id = ?
                 GROUP BY action"
            );
            $engData->execute([$pid]);
            $engRows = $engData->fetchAll(PDO::FETCH_ASSOC);
            $share_count = 0;
            $save_count  = 0;
            foreach ($engRows as $er) {
                if ($er['action'] === 'share') $share_count = (int)$er['cnt'];
                if ($er['action'] === 'save')  $save_count  = (int)$er['cnt'];
            }

            // ── Profile visit count ──
            $pvRow = $pdo->prepare("SELECT COUNT(*) FROM post_profile_visits WHERE post_id = ?");
            $pvRow->execute([$pid]);
            $profile_visit_count = (int)$pvRow->fetchColumn();

            // ── Rates (per impression) ──
            $like_rate    = $like_count    / $impression_count;
            $comment_rate = $comment_count / $impression_count;
            $share_rate   = $share_count   / $impression_count;
            $save_rate    = $save_count    / $impression_count;

            // ── Velocity: engagement acceleration ──
            $vel1h = $pdo->prepare(
                "SELECT COUNT(*) FROM post_impressions
                 WHERE post_id = ? AND created_at >= NOW() - INTERVAL 1 HOUR"
            );
            $vel1h->execute([$pid]);
            $eng_1h = (int)$vel1h->fetchColumn();

            $velPrev = $pdo->prepare(
                "SELECT COUNT(*) FROM post_impressions
                 WHERE post_id = ?
                   AND created_at >= NOW() - INTERVAL 2 HOUR
                   AND created_at <  NOW() - INTERVAL 1 HOUR"
            );
            $velPrev->execute([$pid]);
            $eng_prev_1h = (int)$velPrev->fetchColumn();

            $velocity_1h   = max(0.5, min(5.0, $eng_1h / max(1, $eng_prev_1h)));
            $velocity_factor = max(0.5, min(3.0, $velocity_1h));

            // 24h velocity for storage
            $vel24h = $pdo->prepare(
                "SELECT COUNT(*) FROM post_impressions
                 WHERE post_id = ? AND created_at >= NOW() - INTERVAL 24 HOUR"
            );
            $vel24h->execute([$pid]);
            $eng_24h = (int)$vel24h->fetchColumn();

            $velPrev24 = $pdo->prepare(
                "SELECT COUNT(*) FROM post_impressions
                 WHERE post_id = ?
                   AND created_at >= NOW() - INTERVAL 48 HOUR
                   AND created_at <  NOW() - INTERVAL 24 HOUR"
            );
            $velPrev24->execute([$pid]);
            $eng_prev_24h = (int)$velPrev24->fetchColumn();

            $velocity_24h = max(0.5, min(5.0, $eng_24h / max(1, $eng_prev_24h)));

            // ── Time decay ──
            $age_hours  = 0;
            if ($post_created) {
                $age_hours = max(0, (int)((time() - strtotime($post_created)) / 3600));
            }
            $time_decay = exp(-$age_hours / 72.0); // 72h half-life

            // ── Core viral score formula ──
            $viral_score = (
                3.5 * $share_rate      +
                3.0 * $save_rate       +
                2.5 * $rewatch_rate    +
                2.0 * $comment_rate    +
                1.5 * $like_rate       +
                2.0 * $completion_rate +
                1.0 * ($avg_watch_pct / 100.0)
            ) * $velocity_factor * $time_decay * 1000;

            $is_viral = ($viral_score > 30 && $velocity_1h > 1.2) ? 1 : 0;

            // ── UPSERT post_virality ──
            $pdo->prepare(
                "INSERT INTO post_virality
                    (post_id, impression_count, unique_viewers, avg_watch_pct,
                     completion_rate, share_count, save_count, profile_visit_count,
                     rewatch_count, viral_score, velocity_1h, velocity_24h, is_viral, last_computed)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
                 ON DUPLICATE KEY UPDATE
                    impression_count    = VALUES(impression_count),
                    unique_viewers      = VALUES(unique_viewers),
                    avg_watch_pct       = VALUES(avg_watch_pct),
                    completion_rate     = VALUES(completion_rate),
                    share_count         = VALUES(share_count),
                    save_count          = VALUES(save_count),
                    profile_visit_count = VALUES(profile_visit_count),
                    rewatch_count       = VALUES(rewatch_count),
                    viral_score         = VALUES(viral_score),
                    velocity_1h         = VALUES(velocity_1h),
                    velocity_24h        = VALUES(velocity_24h),
                    is_viral            = VALUES(is_viral),
                    last_computed       = NOW()"
            )->execute([
                $pid, $impression_count, $unique_viewers, $avg_watch_pct,
                $completion_rate, $share_count, $save_count, $profile_visit_count,
                $rewatch_count, $viral_score, $velocity_1h, $velocity_24h, $is_viral
            ]);

            // ── Keep post_trending_scores in sync (legacy compatibility) ──
            try {
                $pdo->prepare(
                    "INSERT INTO post_trending_scores (post_id, score)
                     VALUES (?, ?)
                     ON DUPLICATE KEY UPDATE score = ?, updated_at = NOW()"
                )->execute([$pid, $viral_score, $viral_score]);
            } catch (Throwable $e) { }

            $updated++;
        } catch (Throwable $e) {
            // Skip individual post failures; continue batch
        }
    }

    out(200, ['status' => 'ok', 'updated' => $updated, 'total_candidates' => count($postIds)]);
}

// ---------------------------------------------------------------------------
// ACTION: get_post_stats
// Creator / admin dashboard stats for a single post.
// Requires auth.
// ---------------------------------------------------------------------------
if ($action === 'get_post_stats') {
    requireUser($pdo);
    $post_id = (int)($data['post_id'] ?? $_GET['post_id'] ?? 0);
    if ($post_id <= 0) out(400, ['status' => 'error', 'message' => 'post_id required']);

    // 7-day impression aggregate
    $impStats = $pdo->prepare(
        "SELECT
            COUNT(*)                                            AS impressions_7d,
            COUNT(DISTINCT user_id)                            AS unique_viewers,
            AVG(CASE WHEN watch_pct > 0 THEN watch_pct END)    AS avg_watch_pct,
            SUM(CASE WHEN watch_pct >= 80 THEN 1 ELSE 0 END)   AS completions,
            COUNT(*)                                            AS total_for_rate
         FROM post_impressions
         WHERE post_id = ? AND created_at >= NOW() - INTERVAL 7 DAY"
    );
    $impStats->execute([$post_id]);
    $is = $impStats->fetch(PDO::FETCH_ASSOC);

    $impressions_7d  = (int)($is['impressions_7d']  ?? 0);
    $unique_viewers  = (int)($is['unique_viewers']  ?? 0);
    $avg_watch_pct   = round((float)($is['avg_watch_pct'] ?? 0), 1);
    $completion_rate = $impressions_7d > 0
                       ? round((int)($is['completions'] ?? 0) / $impressions_7d, 4)
                       : 0.0;

    // Source breakdown
    $sourceRows = $pdo->prepare(
        "SELECT source, COUNT(*) AS cnt
         FROM post_impressions
         WHERE post_id = ? AND created_at >= NOW() - INTERVAL 7 DAY
         GROUP BY source
         ORDER BY cnt DESC"
    );
    $sourceRows->execute([$post_id]);
    $top_sources = [];
    foreach ($sourceRows->fetchAll(PDO::FETCH_ASSOC) as $sr) {
        $top_sources[$sr['source']] = (int)$sr['cnt'];
    }

    // Engagement counts
    $engRows = $pdo->prepare(
        "SELECT action, COUNT(*) AS cnt FROM post_engagements WHERE post_id = ? GROUP BY action"
    );
    $engRows->execute([$post_id]);
    $share_count = 0; $save_count = 0;
    foreach ($engRows->fetchAll(PDO::FETCH_ASSOC) as $er) {
        if ($er['action'] === 'share') $share_count = (int)$er['cnt'];
        if ($er['action'] === 'save')  $save_count  = (int)$er['cnt'];
    }

    // Post base counts
    $baseRow = $pdo->prepare(
        "SELECT
            COALESCE(p.likes_count, lc.cnt, 0)    AS like_count,
            COALESCE(p.comments_count, cc.cnt, 0)  AS comment_count
         FROM posts p
         LEFT JOIN (SELECT post_id, COUNT(*) AS cnt FROM post_likes    GROUP BY post_id) lc ON lc.post_id = p.id
         LEFT JOIN (SELECT post_id, COUNT(*) AS cnt FROM post_comments GROUP BY post_id) cc ON cc.post_id = p.id
         WHERE p.id = ? LIMIT 1"
    );
    $baseRow->execute([$post_id]);
    $br = $baseRow->fetch(PDO::FETCH_ASSOC) ?: [];
    $like_count    = (int)($br['like_count']    ?? 0);
    $comment_count = (int)($br['comment_count'] ?? 0);

    // Virality row
    $virRow = $pdo->prepare(
        "SELECT viral_score, is_viral, velocity_1h, velocity_24h
         FROM post_virality WHERE post_id = ? LIMIT 1"
    );
    $virRow->execute([$post_id]);
    $vr = $virRow->fetch(PDO::FETCH_ASSOC) ?: [];

    out(200, [
        'status'          => 'ok',
        'post_id'         => $post_id,
        'impressions_7d'  => $impressions_7d,
        'unique_viewers'  => $unique_viewers,
        'avg_watch_pct'   => $avg_watch_pct,
        'completion_rate' => $completion_rate,
        'share_count'     => $share_count,
        'save_count'      => $save_count,
        'like_count'      => $like_count,
        'comment_count'   => $comment_count,
        'viral_score'     => round((float)($vr['viral_score']  ?? 0), 4),
        'is_viral'        => (int)($vr['is_viral']    ?? 0),
        'velocity_1h'     => round((float)($vr['velocity_1h']  ?? 1.0), 4),
        'velocity_24h'    => round((float)($vr['velocity_24h'] ?? 1.0), 4),
        'top_sources'     => $top_sources,
    ]);
}

// ---------------------------------------------------------------------------
// ACTION: trending_posts
// Returns top 20 viral posts. Requires auth.
// ---------------------------------------------------------------------------
if ($action === 'trending_posts') {
    requireUser($pdo);

    $rows = $pdo->query(
        "SELECT
            p.id,
            p.user_id,
            p.caption,
            p.file_url AS media,
            p.type,
            p.created_at,
            COALESCE(lc.cnt, 0)  AS likes_count,
            COALESCE(cc.cnt, 0)  AS comments_count,
            u.name               AS author_name,
            u.username           AS author_username,
            u.profile_pic        AS author_avatar,
            pv.viral_score,
            pv.is_viral,
            pv.velocity_1h,
            pv.impression_count,
            pv.unique_viewers,
            pv.completion_rate
         FROM post_virality pv
         JOIN posts p ON p.id = pv.post_id
         LEFT JOIN users u ON u.id = p.user_id
         LEFT JOIN (SELECT post_id, COUNT(*) AS cnt FROM post_likes    GROUP BY post_id) lc ON lc.post_id = p.id
         LEFT JOIN (SELECT post_id, COUNT(*) AS cnt FROM post_comments GROUP BY post_id) cc ON cc.post_id = p.id
         WHERE pv.viral_score > 0
         ORDER BY pv.viral_score DESC
         LIMIT 20"
    )->fetchAll(PDO::FETCH_ASSOC);

    $posts = [];
    foreach ($rows as $r) {
        $posts[] = [
            'post_id'          => (string)$r['id'],
            'user_id'          => (string)$r['user_id'],
            'caption'          => (string)$r['caption'],
            'media'            => (string)$r['media'],
            'type'             => (string)$r['type'],
            'created_at'       => (string)$r['created_at'],
            'likes_count'      => (int)$r['likes_count'],
            'comments_count'   => (int)$r['comments_count'],
            'author_name'      => (string)($r['author_name'] ?? ''),
            'author_username'  => (string)($r['author_username'] ?? ''),
            'author_avatar'    => (string)($r['author_avatar'] ?? ''),
            'viral_score'      => round((float)$r['viral_score'], 4),
            'is_viral'         => (int)$r['is_viral'],
            'velocity_1h'      => round((float)$r['velocity_1h'], 4),
            'impression_count' => (int)$r['impression_count'],
            'unique_viewers'   => (int)$r['unique_viewers'],
            'completion_rate'  => round((float)$r['completion_rate'], 4),
        ];
    }

    out(200, ['status' => 'ok', 'posts' => $posts, 'count' => count($posts)]);
}

// ---------------------------------------------------------------------------
// Legacy actions forwarded from old analytics.php
// ---------------------------------------------------------------------------
if ($action === 'session_start') {
    $user       = requireUser($pdo);
    $uid        = (int)$user['id'];
    $session_id  = trim((string)($data['session_id'] ?? ''));
    if ($session_id === '') out(400, ['status' => false, 'message' => 'session_id required']);
    $platform    = trim((string)($data['platform'] ?? 'android'));
    $app_version = trim((string)($data['app_version'] ?? ''));
    $device      = trim((string)($data['device'] ?? ''));
    $pdo->prepare(
        "INSERT INTO user_sessions (user_id, session_id, started_at, platform, app_version, device)
         VALUES (?, ?, NOW(), ?, ?, ?)
         ON DUPLICATE KEY UPDATE started_at = started_at"
    )->execute([$uid, $session_id, $platform, $app_version, $device]);
    out(200, ['status' => true, 'message' => 'session started']);
}

if ($action === 'session_end') {
    $user       = requireUser($pdo);
    $uid        = (int)$user['id'];
    $session_id = trim((string)($data['session_id'] ?? ''));
    if ($session_id === '') out(400, ['status' => false, 'message' => 'session_id required']);
    $pdo->prepare(
        "UPDATE user_sessions
         SET ended_at = NOW(),
             duration_sec = GREATEST(0, TIMESTAMPDIFF(SECOND, started_at, NOW()))
         WHERE session_id = ? AND user_id = ? AND ended_at IS NULL"
    )->execute([$session_id, $uid]);
    out(200, ['status' => true, 'message' => 'session ended']);
}

if ($action === 'watch') {
    $user    = requireUser($pdo);
    $uid     = (int)$user['id'];
    $kind    = strtolower(trim((string)($data['content_kind'] ?? 'post')));
    if (!in_array($kind, ['reel', 'video', 'post'], true)) $kind = 'post';
    $content_id = (int)($data['content_id'] ?? 0);
    $watch_sec  = (int)($data['watch_sec'] ?? 0);
    if ($content_id <= 0 || $watch_sec <= 0) out(400, ['status' => false, 'message' => 'content_id and watch_sec required']);
    $pdo->prepare(
        "INSERT INTO content_watch (user_id, content_kind, content_id, watch_sec, started_at, ended_at)
         VALUES (?, ?, ?, ?, NOW(), NOW())"
    )->execute([$uid, $kind, $content_id, $watch_sec]);
    out(200, ['status' => true, 'message' => 'watch recorded']);
}

out(400, ['status' => 'error', 'message' => 'Invalid action']);
