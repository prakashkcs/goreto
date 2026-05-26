<?php
$server = 'coinzop.com';
$user = 'coinzopadmin@coinzop.com';
$pass = 'Prakas12@';

$conn = ftp_connect($server);
ftp_login($conn, $user, $pass);
ftp_chdir($conn, 'admin');
ftp_put($conn, 'wallet_requests.php', 'admin_wallet_requests.php', FTP_BINARY);
ftp_chdir($conn, '../api/v1');
ftp_put($conn, 'wallet.php', 'wallet.php', FTP_BINARY);
ftp_close($conn);
echo "Done";
?>
