<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

try {
    $viewer = requireUser($pdo);
    $viewerId = intval($viewer['id']);

    $raw = file_get_contents('php://input');
    $input = json_decode($raw, true) ?? $_POST;

    $originalPostId = intval($input['post_id'] ?? 0);
    $caption = trim((string)($input['caption'] ?? ''));

    if ($originalPostId <= 0) {
        out_json(400, ['status' => 'error', 'message' => 'post_id required']);
    }

    // 1. Fetch original post and owner privacy info
    // We join with users to check privacy_allow_repost
    $stmt = $pdo->prepare("
        SELECT p.*, u.id as owner_id, u.privacy_allow_repost 
        FROM posts p
        JOIN users u ON u.id = p.user_id
        WHERE p.id = ? 
        LIMIT 1
    ");
    $stmt->execute([$originalPostId]);
    $orig = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$orig) {
        out_json(404, ['status' => 'error', 'message' => 'Original post not found']);
    }

    $ownerId = intval($orig['owner_id']);

    // 2. CHECK PRIVACY: privacy_allow_repost
    // Default to 1 (ON) if column missing or null
    $allowRepost = isset($orig['privacy_allow_repost']) ? intval($orig['privacy_allow_repost']) : 1;

    // Exception: User can always reshare their own post
    if ($allowRepost === 0 && $viewerId !== $ownerId) {
        out_json(403, [
            'status' => 'error',
            'message' => 'This user has disabled resharing of their posts.'
        ]);
    }

    // 3. Create the Repost
    // A repost is a new post entry with repost_of pointing to original
    // We copy type and media URL from original
    $type = $orig['type'] ?? 'image';
    $mediaUrl = $orig['file_url'] ?? $orig['media_url'] ?? '';

    $ins = $pdo->prepare("
        INSERT INTO posts (user_id, type, file_url, caption, repost_of, repost_caption, created_at) 
        VALUES (?, ?, ?, ?, ?, ?, NOW())
    ");
    $ins->execute([
        $viewerId,
        $type,
        $mediaUrl,
        $orig['caption'] ?? '',
        $originalPostId,
        $caption, // the user's new caption for the share
    ]);

    $newId = $pdo->lastInsertId();

    // Notify original post owner
    if ($ownerId > 0 && $ownerId !== $viewerId) {
        try {
            require_once __DIR__ . '/notification_helper.php';
            $uSt = $pdo->prepare("SELECT name FROM users WHERE id = ?");
            $uSt->execute([$viewerId]);
            $uname = $uSt->fetchColumn() ?: 'Someone';
            send_app_notification($pdo, $ownerId, $viewerId, 'repost', 'Post Reshared', "$uname reshared your post.", $originalPostId);
        } catch (Throwable $_) {}
    }

    out_json(200, [
        'status' => 'success',
        'message' => 'Post reshared successfully',
        'post_id' => $newId
    ]);

}
catch (Throwable $e) {
    out_json(500, ['status' => 'error', 'message' => $e->getMessage()]);
}
