<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

$config = require __DIR__ . '/../../config/config.php';

try {
    $db = $config['db'];
    $dsn = "mysql:host={$db['host']};dbname={$db['name']};charset={$db['charset']}";
    $pdo = new PDO($dsn, $db['user'], $db['pass'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);

    $result = [];

    // 1. Check likes for post 55
    $stmt = $pdo->prepare("SELECT * FROM post_likes WHERE post_id = 55");
    $stmt->execute();
    $result['post_55_likes'] = $stmt->fetchAll();

    // 2. Check all posts with empty type
    $stmt = $pdo->query("SELECT id, user_id, type, LEFT(file_url, 80) as file_url FROM posts WHERE type = '' OR type IS NULL");
    $result['empty_type_posts'] = $stmt->fetchAll();

    // 3. Fix empty type to 'video' for .mp4 files, 'image' for .jpg/.png
    $updated = 0;
    $stmt = $pdo->query("SELECT id, file_url FROM posts WHERE type = '' OR type IS NULL");
    $rows = $stmt->fetchAll();
    foreach ($rows as $row) {
        $url = strtolower($row['file_url'] ?? '');
        $newType = 'image'; // default
        if (str_ends_with($url, '.mp4') || str_ends_with($url, '.mov') || str_ends_with($url, '.webm')) {
            $newType = 'video';
        }
        $upd = $pdo->prepare("UPDATE posts SET type = ? WHERE id = ?");
        $upd->execute([$newType, $row['id']]);
        $updated++;
    }
    $result['fixed_empty_types'] = $updated;

    // 4. Now show all posts for user 1 with correct types
    $stmt = $pdo->query("SELECT id, user_id, type, LEFT(file_url, 80) as file_url, caption FROM posts WHERE user_id = 1 ORDER BY id DESC");
    $result['user1_posts_after_fix'] = $stmt->fetchAll();

    // 5. Test the full posts.php SELECT query manually
    try {
        $sql = "SELECT p.id, p.user_id, p.caption, p.file_url AS media, p.type, p.created_at,
                COALESCE(lc.likes_count, 0) AS likes_count,
                COALESCE(cc.comments_count, 0) AS comments_count,
                COALESCE(vc.total_views, 0) AS views_total,
                COALESCE(p.subscriber_only, 0) AS subscriber_only
                FROM posts p
                LEFT JOIN users u ON u.id = p.user_id
                LEFT JOIN (SELECT post_id, COUNT(*) AS likes_count FROM post_likes GROUP BY post_id) lc ON lc.post_id = p.id
                LEFT JOIN (SELECT post_id, COUNT(*) AS comments_count FROM post_comments GROUP BY post_id) cc ON cc.post_id = p.id
                LEFT JOIN (SELECT post_id, COUNT(*) AS total_views FROM post_views GROUP BY post_id) vc ON vc.post_id = p.id
                WHERE p.user_id = 1
                ORDER BY p.id DESC LIMIT 10";
        $stmt = $pdo->query($sql);
        $result['full_profile_query'] = $stmt->fetchAll();
    }
    catch (Throwable $e) {
        $result['full_profile_query_error'] = $e->getMessage();
    }

    echo json_encode($result, JSON_PRETTY_PRINT);

}
catch (Throwable $e) {
    echo json_encode(['error' => $e->getMessage()], JSON_PRETTY_PRINT);
}
