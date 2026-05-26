<?php
echo "Current Dir: " . __DIR__ . "\n";
echo "Real Path: " . realpath('.') . "\n";
echo "Parent Real Path: " . realpath('..') . "\n";
echo "Grandparent Real Path: " . realpath('../..') . "\n";
echo "Great-Grandparent Real Path: " . realpath('../../..') . "\n";
?>
