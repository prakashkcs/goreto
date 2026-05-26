<?php
require_once __DIR__ . "/db_connect.php";
try {
  $st = $pdo->query("SHOW COLUMNS FROM user_subscriptions");
  file_put_contents("sub_cols.json", json_encode($st->fetchAll(PDO::FETCH_COLUMN)));
  echo "OK";
} catch (Throwable $e) {
  echo "Error: " . $e->getMessage();
}
?>
