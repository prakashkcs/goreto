<?php
header('Content-Type: text/plain');
$src = __DIR__ . '/../../admin/kyc_review.php';
$dst = __DIR__ . '/kyc_review_source.txt';
if (copy($src, $dst)) {
    echo "Successfully copied to $dst\n";
} else {
    echo "Failed to copy $src to $dst\n";
}
