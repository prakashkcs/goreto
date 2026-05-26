<?php
$file = '.htaccess';
$newContent = "# Redirect old profile GET requests to profile_v17.php
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteCond %{REQUEST_METHOD} GET
RewriteRule ^profile\.php$ profile_v17.php [L,QSA]

RewriteCond %{REQUEST_METHOD} GET
RewriteRule ^profile_v16\.php$ profile_v17.php [L,QSA]
</IfModule>
";
file_put_contents($file, $newContent);
echo "Success";
?>
