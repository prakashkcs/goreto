<?php
error_reporting(E_ALL);
ini_set('display_errors', '1');
require_once __DIR__ . '/db_connect.php';

try {
    \ = \->query('SHOW TABLES');
    \ = \->fetchAll(PDO::FETCH_COLUMN);
    echo "Tables: " . implode(', ', \) . "<br><br>";

    if (in_array('income_proofs', \)) {
        echo "income_proofs exists.<br>";
        \ = \->query('SHOW COLUMNS FROM income_proofs');
        \ = \->fetchAll(PDO::FETCH_ASSOC);
        echo "<pre>"; print_r(\); echo "</pre>";
        
        // Try the actual query from income_review.php
        \ = "SELECT p.*, u.id AS u_id, u.name AS u_name, u.username AS u_username FROM income_proofs p LEFT JOIN users u ON u.id = p.user_id LIMIT 10";
        \ = \->query(\);
        \ = \->fetchAll(PDO::FETCH_ASSOC);
        echo "<pre>Query result:\n"; print_r(\); echo "</pre>";
    } else {
        echo "income_proofs DOES NOT EXIST.<br>";
    }
} catch (PDOException \) {
    echo "PDO Error: " . \->getMessage();
}
?>
