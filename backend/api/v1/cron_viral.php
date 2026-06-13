<?php
// cron_viral.php — Runs compute_viral directly via PHP CLI. Not web-accessible.
if (php_sapi_name() !== 'cli') {
    http_response_code(403);
    exit;
}

define('CRON_MODE', true);

// Bootstrap DB
$dbFile = __DIR__ . '/db_connect.php';
if (!file_exists($dbFile)) {
    fwrite(STDERR, 'db_connect.php not found' . PHP_EOL);
    exit(1);
}
require_once $dbFile;

// ---- Replicate compute_viral logic from analytics.php ----
$activePosts = $pdo->query(
    "SELECT DISTINCT post_id FROM post_impressions WHERE created_at >= NOW() - INTERVAL 7 DAY"
)->fetchAll(PDO::FETCH_COLUMN);

$existing = $pdo->query(
    "SELECT post_id FROM post_virality WHERE updated_at < NOW() - INTERVAL 1 HOUR"
)->fetchAll(PDO::FETCH_COLUMN);

$postIds = array_values(array_unique(array_merge($activePosts, $existing)));
$updated = 0;

foreach ($postIds as $pid) {
    $pid = (int)$pid;
    if ($pid <= 0) continue;
    try {
        $imp = $pdo->prepare(
            "SELECT COUNT(*) AS impression_count, COUNT(DISTINCT user_id) AS unique_viewers,
                    AVG(CASE WHEN watch_pct > 0 THEN watch_pct END) AS avg_watch_pct,
                    SUM(CASE WHEN watch_pct >= 80 THEN 1 ELSE 0 END) AS completions,
                    SUM(rewatched) AS rewatch_count
             FROM post_impressions WHERE post_id = ? AND created_at >= NOW() - INTERVAL 24 HOUR"
        );
        $imp->execute([$pid]);
        $im = $imp->fetch(PDO::FETCH_ASSOC);
        $impression_count = max(1, (int)($im['impression_count'] ?? 0));
        $unique_viewers   = (int)($im['unique_viewers'] ?? 0);
        $avg_watch_pct    = (float)($im['avg_watch_pct'] ?? 0);
        $completions      = (int)($im['completions'] ?? 0);
        $rewatch_count    = (int)($im['rewatch_count'] ?? 0);
        $completion_rate  = $completions / $impression_count;
        $rewatch_rate     = $rewatch_count / $impression_count;

        $pd = $pdo->prepare(
            "SELECT COALESCE(p.likes_count, lc.likes_count, 0) AS like_count,
                    COALESCE(p.comments_count, cc.comments_count, 0) AS comment_count,
                    p.created_at
             FROM posts p
             LEFT JOIN (SELECT post_id, COUNT(*) AS likes_count FROM post_likes GROUP BY post_id) lc ON lc.post_id = p.id
             LEFT JOIN (SELECT post_id, COUNT(*) AS comments_count FROM post_comments GROUP BY post_id) cc ON cc.post_id = p.id
             WHERE p.id = ? LIMIT 1"
        );
        $pd->execute([$pid]);
        $pdRow = $pd->fetch(PDO::FETCH_ASSOC);
        if (!$pdRow) continue;
        $like_count    = (float)($pdRow['like_count'] ?? 0);
        $comment_count = (float)($pdRow['comment_count'] ?? 0);
        $post_created  = $pdRow['created_at'] ?? null;

        $engRows = $pdo->prepare("SELECT action, COUNT(*) AS cnt FROM post_engagements WHERE post_id = ? GROUP BY action");
        $engRows->execute([$pid]);
        $share_count = 0; $save_count = 0;
        foreach ($engRows->fetchAll(PDO::FETCH_ASSOC) as $er) {
            if ($er['action'] === 'share') $share_count = (int)$er['cnt'];
            if ($er['action'] === 'save')  $save_count  = (int)$er['cnt'];
        }

        $pvRow = $pdo->prepare("SELECT COUNT(*) FROM post_profile_visits WHERE post_id = ?");
        $pvRow->execute([$pid]);
        $profile_visit_count = (int)$pvRow->fetchColumn();

        $like_rate    = $like_count    / $impression_count;
        $comment_rate = $comment_count / $impression_count;
        $share_rate   = $share_count   / $impression_count;
        $save_rate    = $save_count    / $impression_count;

        $vel1h = $pdo->prepare("SELECT COUNT(*) FROM post_impressions WHERE post_id = ? AND created_at >= NOW() - INTERVAL 1 HOUR");
        $vel1h->execute([$pid]);
        $eng_1h = (int)$vel1h->fetchColumn();

        $velPrev = $pdo->prepare("SELECT COUNT(*) FROM post_impressions WHERE post_id = ? AND created_at >= NOW() - INTERVAL 2 HOUR AND created_at < NOW() - INTERVAL 1 HOUR");
        $velPrev->execute([$pid]);
        $eng_prev_1h = (int)$velPrev->fetchColumn();
        $velocity_1h     = max(0.5, min(5.0, $eng_1h / max(1, $eng_prev_1h)));
        $velocity_factor = max(0.5, min(3.0, $velocity_1h));

        $vel24h = $pdo->prepare("SELECT COUNT(*) FROM post_impressions WHERE post_id = ? AND created_at >= NOW() - INTERVAL 24 HOUR");
        $vel24h->execute([$pid]);
        $eng_24h = (int)$vel24h->fetchColumn();
        $velPrev24 = $pdo->prepare("SELECT COUNT(*) FROM post_impressions WHERE post_id = ? AND created_at >= NOW() - INTERVAL 48 HOUR AND created_at < NOW() - INTERVAL 24 HOUR");
        $velPrev24->execute([$pid]);
        $eng_prev_24h  = (int)$velPrev24->fetchColumn();
        $velocity_24h  = max(0.5, min(5.0, $eng_24h / max(1, $eng_prev_24h)));

        $age_hours  = $post_created ? max(0, (int)((time() - strtotime($post_created)) / 3600)) : 0;
        $time_decay = exp(-$age_hours / 72.0);

        $viral_score = (
            3.5 * $share_rate +
            3.0 * $save_rate  +
            2.5 * $rewatch_rate +
            2.0 * $comment_rate +
            1.5 * $like_rate +
            2.0 * $completion_rate +
            1.0 * ($avg_watch_pct / 100.0)
        ) * $velocity_factor * $time_decay * 1000;

        $is_viral = ($viral_score > 30 && $velocity_1h > 1.2) ? 1 : 0;

        $pdo->prepare(
            "INSERT INTO post_virality
                (post_id, impression_count, unique_viewers, avg_watch_pct, completion_rate,
                 share_count, save_count, profile_visit_count, rewatch_count, viral_score,
                 velocity_1h, velocity_24h, is_viral, last_computed)
             VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,NOW())
             ON DUPLICATE KEY UPDATE
                impression_count=VALUES(impression_count), unique_viewers=VALUES(unique_viewers),
                avg_watch_pct=VALUES(avg_watch_pct), completion_rate=VALUES(completion_rate),
                share_count=VALUES(share_count), save_count=VALUES(save_count),
                profile_visit_count=VALUES(profile_visit_count), rewatch_count=VALUES(rewatch_count),
                viral_score=VALUES(viral_score), velocity_1h=VALUES(velocity_1h),
                velocity_24h=VALUES(velocity_24h), is_viral=VALUES(is_viral), last_computed=NOW()"
        )->execute([$pid, $impression_count, $unique_viewers, $avg_watch_pct, $completion_rate,
                    $share_count, $save_count, $profile_visit_count, $rewatch_count,
                    $viral_score, $velocity_1h, $velocity_24h, $is_viral]);

        try {
            $pdo->prepare("INSERT INTO post_trending_scores (post_id, score) VALUES (?,?) ON DUPLICATE KEY UPDATE score=?, updated_at=NOW()"
            )->execute([$pid, $viral_score, $viral_score]);
        } catch (Throwable $e) {}

        $updated++;
    } catch (Throwable $e) {}
}

echo date('Y-m-d H:i:s') . " viral scores updated: $updated / " . count($postIds) . PHP_EOL;
