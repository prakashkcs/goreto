<?php
// ekloadmin/admin/_core.php
ini_set('display_errors', 1);
error_reporting(E_ALL);

$config = require __DIR__ . '/../config/config.php';

session_name($config['admin']['session_name'] ?? 'love_vibe_admin');
session_start();

try {
    $db = $config['db'];
    $pdo = new PDO(
        "mysql:host={$db['host']};dbname={$db['name']};charset={$db['charset']}",
        $db['user'],
        $db['pass'],
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC
        ]
    );
} catch (PDOException $e) {
    die("Database connection failed: " . $e->getMessage());
}

// Ensure admin_users exists with expected columns
$pdo->exec("
CREATE TABLE IF NOT EXISTS admin_users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(100) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
");

// Bootstrap admin if empty
$c = (int)($pdo->query("SELECT COUNT(*) c FROM admin_users")->fetch()['c'] ?? 0);
if ($c === 0) {
  $u = $config['admin']['bootstrap_username'] ?? 'admin';
  $p = $config['admin']['bootstrap_password'] ?? 'admin123';
  $h = password_hash($p, PASSWORD_DEFAULT);
  $stmt = $pdo->prepare("INSERT INTO admin_users (username, password_hash) VALUES (?, ?)");
  $stmt->execute([$u, $h]);
}

function admin_require_login() {
  if (empty($_SESSION['admin_id'])) {
    header("Location: login.php");
    exit;
  }
}
function admin_logout() {
  session_destroy();
  header("Location: login.php");
  exit;
}
