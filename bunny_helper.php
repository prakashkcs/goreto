<?php
require_once __DIR__ . '/bunny_config.php';

/**
 * Uploads a local file to BunnyCDN Storage.
 * 
 * @param string $localPath Path to the local file.
 * @param string $bunnyPath Path on the BunnyCDN storage (e.g., 'uploads/image.jpg').
 * @return string|false The URL of the uploaded file on the Pull Zone, or false on failure.
 */
function uploadToBunny($localPath, $bunnyPath)
{
    if (!file_exists($localPath)) {
        return false;
    }

    $fileName = basename($localPath);
    $url = BUNNY_STORAGE_ENDPOINT . '/' . BUNNY_STORAGE_ZONE . '/' . ltrim($bunnyPath, '/');

    $ch = curl_init();

    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, "PUT");
    curl_setopt($ch, CURLOPT_POSTFIELDS, file_get_contents($localPath));
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        "AccessKey: " . BUNNY_API_KEY,
        "Content-Type: application/octet-stream",
    ]);

    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($httpCode >= 200 && $httpCode < 300) {
        return rtrim(BUNNY_PULL_ZONE_URL, '/') . '/' . ltrim($bunnyPath, '/');
    }

    return false;
}
?>
