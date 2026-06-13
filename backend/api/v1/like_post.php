<?php
// Thin compat proxy — older Flutter clients POST to /like_post.php with
// {post_id}, server-side likes/notifications live in likes.php?action=toggle.
$_GET['action'] = 'toggle';
if (!isset($_POST['post_id'])) {
    $body = json_decode(file_get_contents('php://input'), true);
    if (is_array($body) && isset($body['post_id'])) {
        $_POST['post_id'] = $body['post_id'];
    }
}
require __DIR__ . '/likes.php';
