<?php
header('Content-Type: text/plain');
echo "upload_max_filesize: " . ini_get('upload_max_filesize') . "\n";
echo "post_max_size: " . ini_get('post_max_size') . "\n";
echo "max_file_uploads: " . ini_get('max_file_uploads') . "\n";
echo "memory_limit: " . ini_get('memory_limit') . "\n";

 = __DIR__ . '/uploads/kyc/';
echo "Upload Dir: " .  . "\n";
if (is_dir()) {
    echo "Directory exists: Yes\n";
    echo "Directory is writable: " . (is_writable() ? 'Yes' : 'No') . "\n";
     = scandir();
    echo "Number of files: " . (count() - 2) . "\n";
} else {
    echo "Directory exists: No\n";
    if (@mkdir(, 0777, true)) {
        echo "Created directory successfully\n";
    } else {
        echo "Failed to create directory\n";
    }
}

try {
    require_once __DIR__ . '/db_connect.php';
    echo "Database: Connected\n";
    
    // Check if table kyc_verifications exists and has correct columns
     = ->query("SHOW COLUMNS FROM kyc_verifications");
     = ->fetchAll(PDO::FETCH_COLUMN);
    echo "kyc_verifications columns: " . implode(', ', ) . "\n";
} catch (Exception ) {
    echo "Database Error: " . ->getMessage() . "\n";
}
?>
