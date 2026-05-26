<?php
// HARD PHP REDIRECT TO BYPASS ALL CACHES AND FLUTTER APP VERSIONS
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    require_once __DIR__ . '/profile_v17.php';
    exit;
}
// For POST (saving match profile) - we shouldn't get here but keep it safe
echo json_encode(["status" => "success", "message" => "Redirected"]);
?>
