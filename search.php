<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    echo json_encode(['status' => 'success']);
    exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

$config = require __DIR__ . '/../../config/config.php';
$baseUrl = rtrim(($config['base_url'] ?? 'https://goreto.org/ekloadmin/api/v1'), '/');

function out_json(int $code, array $payload): void
{
    http_response_code($code);
    echo json_encode($payload);
    exit;
}

function norm_url(?string $url, string $baseUrl): ?string
{
    if ($url === null)
        return null;
    $url = trim((string)$url);
    if ($url === '')
        return '';

    // CDN Redirection for relative upload paths
    if (strpos($url, 'uploads/') !== false && !preg_match('~^https?://~i', $url)) {
        return 'https://goreto.org/ekloadmin/' . ltrim($url, '/');
    }

    if (preg_match('~^https?://~i', $url))
        return $url;
    $baseUrl = str_replace('/api/v1', '', $baseUrl);
    if ($url[0] === '/')
        return $baseUrl . $url;
    return $baseUrl . '/' . $url;
}

try {
    if (!isset($pdo) || !($pdo instanceof PDO)) {
        out_json(500, ['status' => 'error', 'message' => 'DB connection not available']);
    }

    $action = $_GET['action'] ?? '';
    $query = trim($_GET['q'] ?? '');

    if ($query === '') {
        out_json(200, ['status' => 'success', 'results' => []]);
    }

    $qLike = '%' . $query . '%';

    // Identify viewer to filter out blocked users
    $viewerId = 0;
    try {
        if (isset($_SERVER['HTTP_AUTHORIZATION'])) {
            $viewer = requireUser($pdo);
            $viewerId = (int)$viewer['id'];
        }
    } catch (Throwable $e) {}

    $blockFilterUsers = "";
    $blockFilterPosts = "";
    $paramsUsers = [$qLike, $qLike];
    $paramsPosts = [$qLike];

    if ($viewerId > 0) {
        $blockFilterUsers = "AND id NOT IN (SELECT blocked_id FROM user_blocks WHERE blocker_id = ?) 
                             AND id NOT IN (SELECT blocker_id FROM user_blocks WHERE blocked_id = ?)";
        $paramsUsers[] = $viewerId;
        $paramsUsers[] = $viewerId;

        $blockFilterPosts = "AND p.user_id NOT IN (SELECT blocked_id FROM user_blocks WHERE blocker_id = ?) 
                             AND p.user_id NOT IN (SELECT blocker_id FROM user_blocks WHERE blocked_id = ?)";
        $paramsPosts[] = $viewerId;
        $paramsPosts[] = $viewerId;
    }

    if ($action === 'users') {
        $stmt = $pdo->prepare("SELECT id, name, username, profile_pic as avatar FROM users WHERE (name LIKE ? OR username LIKE ?) $blockFilterUsers AND COALESCE(privacy_allow_find_id, 1) = 1 ORDER BY (username LIKE ?) DESC, (name LIKE ?) DESC LIMIT 50");
        $paramsUsers[] = "$query%";
        $paramsUsers[] = "$query%";
        $stmt->execute($paramsUsers);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $results = [];
        foreach ($rows as $r) {
            $results[] = [
                'id' => (string)$r['id'],
                'name' => (string)$r['name'],
                'username' => (string)$r['username'],
                'avatar' => norm_url($r['avatar'], $baseUrl)
            ];
        }
        out_json(200, ['status' => 'success', $action => $results, 'results' => $results]);
    }
    else if ($action === 'search') { // posts
        // Basic post search matching caption
        $stmt = $pdo->prepare("
            SELECT p.id as post_id, p.user_id, p.caption, p.file_url, p.type,
                   p.created_at, u.name as author_name, u.username as author_username, 
                   u.profile_pic as author_avatar, p.subscriber_only
            FROM posts p
            LEFT JOIN users u ON p.user_id = u.id
            WHERE p.caption LIKE ? $blockFilterPosts
            ORDER BY p.id DESC
            LIMIT 50
        ");
        $stmt->execute($paramsPosts);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $results = [];
        foreach ($rows as $r) {
            $media = norm_url($r['file_url'], $baseUrl);
            $results[] = [
                'id' => (string)$r['post_id'],
                'post_id' => (string)$r['post_id'],
                'user_id' => (string)$r['user_id'],
                'caption' => (string)$r['caption'],
                'media_url' => $media,
                'image_url' => $media,
                'type' => (string)$r['type'],
                'created_at' => (string)$r['created_at'],
                'author_name' => (string)$r['author_name'],
                'author_username' => (string)$r['author_username'],
                'author_avatar' => norm_url($r['author_avatar'], $baseUrl),
                'subscriber_only' => (int)($r['subscriber_only'] ?? 0)
            ];
        }
        out_json(200, ['status' => 'success', 'results' => $results, 'posts' => $results]);
    }
    else {
        out_json(400, ['status' => 'error', 'message' => 'Invalid action']);
    }

}
catch (Throwable $e) {
    out_json(500, ['status' => 'error', 'message' => $e->getMessage()]);
}
