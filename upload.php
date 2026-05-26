<?php
$ftp_server = "ftp-lovevibepro.alwaysdata.net";
$ftp_user = "lovevibepro";
$ftp_pass = "K[t?U<22_h-&!Z*";

$conn_id = ftp_connect($ftp_server) or die("Could not connect to $ftp_server");
if (@ftp_login($conn_id, $ftp_user, $ftp_pass)) {
    echo "Connected as $ftp_user@$ftp_server\n";
    ftp_chdir($conn_id, "www/api/v1");
    
    $local_file = 'downloaded_match_profiles.php';
    $server_file = 'match_profiles.php';
    
    if (ftp_put($conn_id, $server_file, $local_file, FTP_BINARY)) {
        echo "Successfully uploaded $local_file to $server_file\n";
    } else {
        echo "There was a problem while uploading $file\n";
    }
} else {
    echo "Could not login\n";
}
ftp_close($conn_id);
?>
