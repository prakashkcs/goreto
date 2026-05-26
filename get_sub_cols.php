<?php
require_once __DIR__ . "/db_connect.php";
try {
  $st = $pdo->query("SHOW COLUMNS FROM user_subscriptions");
  $cols = $st->fetchAll(PDO::FETCH_COLUMN);
  print_r($cols);
} catch (Throwable $e) {
  echo "Error: " . $e->getMessage();
}
?>
