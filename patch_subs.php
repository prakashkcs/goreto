<?php
require_once __DIR__ . "/db_connect.php";
try {
  $st = $pdo->prepare("UPDATE users SET subscription_status='active' WHERE kyc_status='verified' OR kyc_status='approved'");
  $st->execute();
  echo "Affected rows: " . $st->rowCount();
} catch (Throwable $e) {
  echo $e->getMessage();
}
?>
