<?php
$pdo = new PDO("mysql:host=localhost;dbname=sharexhu_dbeklo;charset=utf8mb4", "sharexhu_dbeklo", "BMVRgNZPyUTAFP2E36bc");
$cols = $pdo->query("DESCRIBE posts")->fetchAll(PDO::FETCH_COLUMN);
echo implode("\n", $cols);
