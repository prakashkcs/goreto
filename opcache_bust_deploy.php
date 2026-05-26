<?php
// Deploy updated account.php and auth_middleware.php to api/v1/
// Also test filesystem write access

$dir = __DIR__;
echo "__DIR__: $dir\n";

// Test write access
$testFile = "$dir/test_write_access.php";
$writeTest = file_put_contents($testFile, "<?php echo 'WRITE_OK';");
echo "Write test: " . ($writeTest !== false ? "OK ($writeTest bytes)" : "FAILED") . "\n";
if ($writeTest !== false) {
    echo "Test file URL: https://goreto.org/ekloadmin/test_write_access.php\n";
}

// Create api/v1 directory if needed
$apiV1Dir = "$dir/api/v1";
if (!is_dir($apiV1Dir)) {
    $mkdir = mkdir($apiV1Dir, 0755, true);
    echo "mkdir api/v1: " . ($mkdir ? "OK" : "FAILED") . "\n";
} else {
    echo "api/v1 dir: EXISTS\n";
}

// Write auth_middleware.php
$amContent = '<?php
// auth_middleware.php - API v1 authentication middleware
header("Content-Type: application/json");

// CORS headers
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(200);
    exit;
}

// Skip auth for public endpoints
$publicEndpoints = ["auth.php", "api_auth.php", "signup", "login", "forgot_password", "verify_otp"];
$scriptName = basename($_SERVER["SCRIPT_NAME"] ?? "");
$requestUri = $_SERVER["REQUEST_URI"] ?? "";
foreach ($publicEndpoints as $ep) {
    if (strpos($scriptName, $ep) !== false || strpos($requestUri, $ep) !== false) {
        return; // Allow without token
    }
}

// Get auth token
$headers = getallheaders();
$authHeader = $headers["Authorization"] ?? "";
$token = "";
if (strpos($authHeader, "Bearer ") === 0) {
    $token = substr($authHeader, 7);
}
if (empty($token)) {
    $token = $_GET["token"] ?? "";
}

if (empty($token)) {
    http_response_code(401);
    echo json_encode(["status" => "error", "message" => "No auth token provided"]); // CHANGED from "Invalid token"
    exit;
}

require_once __DIR__ . "/../../db_connect.php";

$stmt = $pdo->prepare("SELECT id, username, email, role FROM users WHERE auth_token = ? LIMIT 1");
$stmt->execute([$token]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$user) {
    http_response_code(401);
    echo json_encode(["status" => "error", "message" => "Token not found in database"]); // CHANGED from "Invalid token"
    exit;
}

$currentUserId = (int)$user["id"];
$currentUser = $user;
';

$amPath = "$apiV1Dir/auth_middleware.php";
$amWrite = file_put_contents($amPath, $amContent);
echo "Write auth_middleware.php: " . ($amWrite !== false ? "OK ($amWrite bytes)" : "FAILED") . "\n";

// Write account.php
$accountContent = '<?php
require_once __DIR__ . "/auth_middleware.php";

if ($_SERVER["REQUEST_METHOD"] === "DELETE") {
    // Parse DELETE body (PHP does not populate $_POST for DELETE)
    $input = json_decode(file_get_contents("php://input"), true);
    $reason = $input["reason"] ?? "User requested";

    try {
        $pdo->beginTransaction();

        $tables = [
            "blocked_users", "chat_messages", "comments", "follows",
            "likes", "match_proposals", "notifications", "posts",
            "reels", "stories", "user_actions", "wallet_transactions",
            "user_subscriptions"
        ];
        foreach ($tables as $table) {
            $pdo->prepare("DELETE FROM $table WHERE user_id = ? OR follower_id = ? OR following_id = ? OR sender_id = ? OR receiver_id = ? OR from_user_id = ? OR to_user_id = ?")
                ->execute([$currentUserId, $currentUserId, $currentUserId, $currentUserId, $currentUserId, $currentUserId, $currentUserId]);
        }

        $stmt = $pdo->prepare("DELETE FROM users WHERE id = ?");
        $stmt->execute([$currentUserId]);

        $pdo->commit();
        echo json_encode(["status" => "success", "message" => "Account deleted permanently"]);
    } catch (Exception $e) {
        $pdo->rollBack();
        http_response_code(500);
        echo json_encode(["status" => "error", "message" => "Delete failed: " . $e->getMessage()]);
    }
    exit;
}

if ($_SERVER["REQUEST_METHOD"] === "GET") {
    $stmt = $pdo->prepare("SELECT id, username, email, full_name, bio, avatar, cover_photo, gender, dob, location, phone, is_verified, created_at FROM users WHERE id = ?");
    $stmt->execute([$currentUserId]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($user) {
        echo json_encode(["status" => "success", "data" => $user]);
    } else {
        http_response_code(404);
        echo json_encode(["status" => "error", "message" => "User not found"]);
    }
    exit;
}

http_response_code(405);
echo json_encode(["status" => "error", "message" => "Method not allowed. Use GET or DELETE."]);
';

$accountPath = "$apiV1Dir/account.php";
$accountWrite = file_put_contents($accountPath, $accountContent);
echo "Write account.php: " . ($accountWrite !== false ? "OK ($accountWrite bytes)" : "FAILED") . "\n";

// Clear opcache
if (function_exists("opcache_reset")) {
    $r = opcache_reset();
    echo "opcache_reset: " . ($r ? "OK" : "FAILED") . "\n";
}
$files = [$amPath, $accountPath];
foreach ($files as $f) {
    if (function_exists("opcache_invalidate")) {
        opcache_invalidate($f, true);
        echo "invalidated: $f\n";
    }
}

echo "\nDone. Check test file at: https://goreto.org/ekloadmin/test_write_access.php\n";
