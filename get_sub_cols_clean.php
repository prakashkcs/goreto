<?php
require_once __DIR__ . "/db_connect.php";
try {
  $st = $pdo->query("SHOW COLUMNS FROM user_subscriptions");
  echo json_encode($st->fetchAll(PDO::FETCH_ASSOC));
} catch (Throwable $e) {
  echo json_encode(["Error" => $e->getMessage()]);
}
?>
