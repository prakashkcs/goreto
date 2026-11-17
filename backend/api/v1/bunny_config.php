<?php
// BunnyCDN configuration.
//
// Values come from config/config.php when it defines a 'bunny' block, so the
// storage key does not have to live in version control:
//
//   'bunny' => [
//       'storage_zone'  => 'goreto',
//       'api_key'       => '...',
//       'pull_zone_url' => 'https://goreto.b-cdn.net',   // your real pull zone
//   ],
//
// pull_zone_url is what gets handed to clients after an upload. It used to be
// hardcoded to coinzop.com — the host from two migrations ago — so every file
// stored on Bunny came back as a dead link. With no pull zone configured we
// fall back to this install's own base URL, which at least resolves.

$__bunnyCfg = [];
$__cfgPath = '/var/www/html/ekloadmin/config/config.php';
if (is_file($__cfgPath)) {
    $__loaded = require $__cfgPath;
    if (is_array($__loaded)) {
        $__bunnyCfg = $__loaded['bunny'] ?? [];
        $__baseUrl  = rtrim((string) ($__loaded['base_url'] ?? 'https://goreto.org/ekloadmin'), '/');
    }
}
if (!isset($__baseUrl)) {
    $__baseUrl = 'https://goreto.org/ekloadmin';
}

define('BUNNY_STORAGE_ZONE', $__bunnyCfg['storage_zone'] ?? 'goreto');
define('BUNNY_API_KEY', $__bunnyCfg['api_key'] ?? '');
define('BUNNY_PULL_ZONE_URL', $__bunnyCfg['pull_zone_url'] ?? $__baseUrl);
define('BUNNY_STORAGE_ENDPOINT', $__bunnyCfg['storage_endpoint'] ?? 'https://storage.bunnycdn.com');

unset($__bunnyCfg, $__cfgPath, $__loaded, $__baseUrl);
