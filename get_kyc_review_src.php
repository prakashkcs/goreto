<?php
$f = "kyc_review.php";
if (file_exists($f)) {
    echo "--- $f CONTENT ---\n";
    echo file_get_contents($f);
} else {
    echo "$f NOT FOUND\n";
}
?>
