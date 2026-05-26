<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/email_helper.php';

function out_json(array $data, int $code = 200): void
{
    http_response_code($code);
    echo json_encode($data);
    exit;
}

function generateResetCode(): string
{
    return strtoupper(substr(str_shuffle('ABCDEFGHJKLMNPQRSTUVWXYZ23456789'), 0, 6));
}

function ensureResetTable(PDO $db): void
{
    $db->exec("CREATE TABLE IF NOT EXISTS password_resets (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        email VARCHAR(255) NOT NULL,
        code VARCHAR(10) NOT NULL,
        expires_at DATETIME NOT NULL,
        used_at DATETIME DEFAULT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_email (email),
        INDEX idx_code (code),
        INDEX idx_expires (expires_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
}

try {
    $database = new Database();
    $db = $database->connect();
    ensureResetTable($db);

    $input = json_decode(file_get_contents('php://input'));
    $action = $_GET['action'] ?? '';

    // ─── FORGOT PASSWORD - Send reset code ───
    if ($action === 'forgot_password') {
        $email = htmlspecialchars(strip_tags($input->email ?? ''));

        if (empty($email) || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
            out_json(['status' => 'error', 'message' => 'Valid email is required'], 400);
        }

        // Find user
        $stmt = $db->prepare("SELECT id, name FROM users WHERE email = ?");
        $stmt->execute([$email]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$user) {
            // Don't reveal if email exists - same message
            out_json(['status' => 'success', 'message' => 'If this email exists, a reset code has been sent']);
        }

        // Invalidate old unused codes
        $db->prepare("UPDATE password_resets SET used_at = NOW() WHERE email = ? AND used_at IS NULL")
            ->execute([$email]);

        // Generate new code
        $code = generateResetCode();
        $expires = date('Y-m-d H:i:s', strtotime('+15 minutes'));

        $db->prepare("INSERT INTO password_resets (user_id, email, code, expires_at) VALUES (?, ?, ?, ?)")
            ->execute([$user['id'], $email, $code, $expires]);

        // Send email
        $emailHelper = new EmailHelper();
        $sent = $emailHelper->sendPasswordReset($email, $code, $user['name'] ?? '');

        if ($sent) {
            out_json([
                'status' => 'success',
                'message' => 'Reset code sent to your email',
                'expires_in' => 900 // 15 minutes in seconds
            ]);
        } else {
            out_json([
                'status' => 'error',
                'message' => 'Failed to send email. Please try again later.'
            ], 500);
        }
    }

    // ─── VERIFY CODE ───
    if ($action === 'verify_code') {
        $email = htmlspecialchars(strip_tags($input->email ?? ''));
        $code = strtoupper(trim($input->code ?? ''));

        if (empty($email) || empty($code)) {
            out_json(['status' => 'error', 'message' => 'Email and code are required'], 400);
        }

        $stmt = $db->prepare("SELECT id, user_id, expires_at, used_at FROM password_resets
                              WHERE email = ? AND code = ? ORDER BY created_at DESC LIMIT 1");
        $stmt->execute([$email, $code]);
        $reset = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$reset) {
            out_json(['status' => 'error', 'message' => 'Invalid code'], 400);
        }

        if ($reset['used_at'] !== null) {
            out_json(['status' => 'error', 'message' => 'Code already used'], 400);
        }

        if (strtotime($reset['expires_at']) < time()) {
            out_json(['status' => 'error', 'message' => 'Code expired'], 400);
        }

        out_json([
            'status' => 'success',
            'message' => 'Code verified',
            'reset_id' => (int) $reset['id']
        ]);
    }

    // ─── RESET PASSWORD ───
    if ($action === 'reset_password') {
        $email = htmlspecialchars(strip_tags($input->email ?? ''));
        $code = strtoupper(trim($input->code ?? ''));
        $newPassword = $input->new_password ?? '';

        if (empty($email) || empty($code) || empty($newPassword)) {
            out_json(['status' => 'error', 'message' => 'Email, code and new password are required'], 400);
        }

        if (strlen($newPassword) < 6) {
            out_json(['status' => 'error', 'message' => 'Password must be at least 6 characters'], 400);
        }

        // Verify code again
        $stmt = $db->prepare("SELECT id, user_id, expires_at, used_at FROM password_resets
                              WHERE email = ? AND code = ? ORDER BY created_at DESC LIMIT 1");
        $stmt->execute([$email, $code]);
        $reset = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$reset || $reset['used_at'] !== null || strtotime($reset['expires_at']) < time()) {
            out_json(['status' => 'error', 'message' => 'Invalid or expired code'], 400);
        }

        // Hash new password
        $hash = password_hash($newPassword, PASSWORD_BCRYPT);

        // Update user password
        $db->prepare("UPDATE users SET password_hash = ? WHERE email = ?")
            ->execute([$hash, $email]);

        // Mark code as used
        $db->prepare("UPDATE password_resets SET used_at = NOW() WHERE id = ?")
            ->execute([$reset['id']]);

        // Invalidate all auth tokens for security
        $db->prepare("DELETE FROM user_auth_tokens WHERE user_id = ?")
            ->execute([$reset['user_id']]);

        out_json([
            'status' => 'success',
            'message' => 'Password reset successfully. Please login with your new password.'
        ]);
    }

    out_json(['status' => 'error', 'message' => 'Unknown action'], 400);

} catch (Throwable $e) {
    error_log('Password reset error: ' . $e->getMessage());
    out_json(['status' => 'error', 'message' => 'Server error'], 500);
}
