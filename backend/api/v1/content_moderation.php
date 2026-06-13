<?php
/**
 * Content Moderation Helper
 * Supports Google Cloud Vision API (SafeSearch) and AWS Rekognition.
 * For videos, extracts a frame with ffmpeg then checks the frame as an image.
 */

// ── Settings loader ───────────────────────────────────────────────────────────

function cm_load_settings(PDO $pdo): array
{
    try {
        $pdo->exec("CREATE TABLE IF NOT EXISTS content_moderation_settings (
            id INT AUTO_INCREMENT PRIMARY KEY,
            enabled TINYINT(1) NOT NULL DEFAULT 0,
            provider ENUM('none','google','aws') NOT NULL DEFAULT 'none',
            sensitivity ENUM('strict','moderate','relaxed') NOT NULL DEFAULT 'moderate',
            block_adult TINYINT(1) NOT NULL DEFAULT 1,
            block_violence TINYINT(1) NOT NULL DEFAULT 1,
            block_racy TINYINT(1) NOT NULL DEFAULT 0,
            google_api_key VARCHAR(500) NOT NULL DEFAULT '',
            aws_access_key VARCHAR(255) NOT NULL DEFAULT '',
            aws_secret_key VARCHAR(500) NOT NULL DEFAULT '',
            aws_region VARCHAR(50) NOT NULL DEFAULT 'us-east-1',
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

        $pdo->exec("CREATE TABLE IF NOT EXISTS moderation_log (
            id INT AUTO_INCREMENT PRIMARY KEY,
            post_id INT NULL,
            user_id INT NULL,
            file_path VARCHAR(500) NULL,
            provider VARCHAR(20) NOT NULL DEFAULT '',
            result ENUM('safe','blocked','error','skipped') NOT NULL DEFAULT 'safe',
            reason VARCHAR(255) NOT NULL DEFAULT '',
            confidence FLOAT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_ml_user (user_id),
            INDEX idx_ml_result (result),
            INDEX idx_ml_created (created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    } catch (Throwable $e) {}

    try {
        $row = $pdo->query("SELECT * FROM content_moderation_settings ORDER BY id ASC LIMIT 1")->fetch(PDO::FETCH_ASSOC);
        if ($row) return $row;
    } catch (Throwable $e) {}

    return [
        'enabled' => 0,
        'provider' => 'none',
        'sensitivity' => 'moderate',
        'block_adult' => 1,
        'block_violence' => 1,
        'block_racy' => 0,
        'google_api_key' => '',
        'aws_access_key' => '',
        'aws_secret_key' => '',
        'aws_region' => 'us-east-1',
    ];
}

// ── Likelihood thresholds ─────────────────────────────────────────────────────

function cm_google_threshold(string $sensitivity): array
{
    // Returns likelihood values that are considered "blocked"
    return match ($sensitivity) {
        'strict'  => ['POSSIBLE', 'LIKELY', 'VERY_LIKELY'],
        'relaxed' => ['VERY_LIKELY'],
        default   => ['LIKELY', 'VERY_LIKELY'],    // moderate
    };
}

function cm_aws_threshold(string $sensitivity): float
{
    return match ($sensitivity) {
        'strict'  => 50.0,
        'relaxed' => 85.0,
        default   => 70.0,
    };
}

// ── Google Cloud Vision SafeSearch ───────────────────────────────────────────

function cm_moderate_google(string $imagePath, array $settings): array
{
    $apiKey = $settings['google_api_key'] ?? '';
    if ($apiKey === '') {
        return ['safe' => true, 'error' => 'Google API key not configured'];
    }

    // Resize large images to stay under 10 MB base64 limit (~7.5 MB raw)
    $imageData = file_get_contents($imagePath);
    if ($imageData === false) {
        return ['safe' => true, 'error' => 'Cannot read file'];
    }

    // If image is >6 MB raw, try to resize via GD
    if (strlen($imageData) > 6_000_000 && extension_loaded('gd')) {
        $imageData = cm_resize_image_gd($imagePath) ?? $imageData;
    }

    $payload = json_encode([
        'requests' => [[
            'image'    => ['content' => base64_encode($imageData)],
            'features' => [['type' => 'SAFE_SEARCH_DETECTION']],
        ]],
    ]);

    $ctx = stream_context_create([
        'http' => [
            'method'  => 'POST',
            'header'  => "Content-Type: application/json\r\nContent-Length: " . strlen($payload),
            'content' => $payload,
            'timeout' => 20,
        ],
        'ssl' => ['verify_peer' => true],
    ]);

    $url      = 'https://vision.googleapis.com/v1/images:annotate?key=' . urlencode($apiKey);
    $response = @file_get_contents($url, false, $ctx);

    if ($response === false) {
        return ['safe' => true, 'error' => 'Google Vision API request failed'];
    }

    $data       = json_decode($response, true);
    $annotation = $data['responses'][0]['safeSearchAnnotation'] ?? [];

    if (empty($annotation)) {
        $errMsg = $data['responses'][0]['error']['message'] ?? ($data['error']['message'] ?? 'Unknown error');
        return ['safe' => true, 'error' => "Google API error: $errMsg"];
    }

    $threshold   = cm_google_threshold($settings['sensitivity'] ?? 'moderate');
    $blockAdult  = (bool)($settings['block_adult'] ?? true);
    $blockViol   = (bool)($settings['block_violence'] ?? true);
    $blockRacy   = (bool)($settings['block_racy'] ?? false);

    $adult    = $annotation['adult']    ?? 'UNKNOWN';
    $violence = $annotation['violence'] ?? 'UNKNOWN';
    $racy     = $annotation['racy']     ?? 'UNKNOWN';

    if ($blockAdult && in_array($adult, $threshold, true)) {
        return ['safe' => false, 'reason' => 'Adult content detected', 'label' => "adult:{$adult}", 'provider' => 'google'];
    }
    if ($blockViol && in_array($violence, $threshold, true)) {
        return ['safe' => false, 'reason' => 'Violent content detected', 'label' => "violence:{$violence}", 'provider' => 'google'];
    }
    if ($blockRacy && in_array($racy, $threshold, true)) {
        return ['safe' => false, 'reason' => 'Racy content detected', 'label' => "racy:{$racy}", 'provider' => 'google'];
    }

    return ['safe' => true, 'provider' => 'google', 'annotation' => $annotation];
}

function cm_resize_image_gd(string $path): ?string
{
    $img = @imagecreatefromstring(file_get_contents($path));
    if (!$img) return null;
    $w = imagesx($img);
    $h = imagesy($img);
    $scale = min(1.0, 1280 / max($w, $h));
    $nw = (int)($w * $scale);
    $nh = (int)($h * $scale);
    $resized = imagecreatetruecolor($nw, $nh);
    imagecopyresampled($resized, $img, 0, 0, 0, 0, $nw, $nh, $w, $h);
    imagedestroy($img);
    ob_start();
    imagejpeg($resized, null, 80);
    imagedestroy($resized);
    return ob_get_clean() ?: null;
}

// ── AWS Rekognition (SigV4 signed) ───────────────────────────────────────────

function cm_moderate_aws(string $imagePath, array $settings): array
{
    $accessKey = $settings['aws_access_key'] ?? '';
    $secretKey = $settings['aws_secret_key'] ?? '';
    $region    = $settings['aws_region']     ?? 'us-east-1';

    if ($accessKey === '' || $secretKey === '') {
        return ['safe' => true, 'error' => 'AWS credentials not configured'];
    }

    $imageData = file_get_contents($imagePath);
    if ($imageData === false) {
        return ['safe' => true, 'error' => 'Cannot read file'];
    }

    $minConf    = cm_aws_threshold($settings['sensitivity'] ?? 'moderate');
    $payload    = json_encode([
        'Image'         => ['Bytes' => base64_encode($imageData)],
        'MinConfidence' => $minConf,
    ]);

    $service  = 'rekognition';
    $host     = "rekognition.{$region}.amazonaws.com";
    $target   = 'RekognitionService.DetectModerationLabels';
    $datetime = gmdate('Ymd\THis\Z');
    $date     = gmdate('Ymd');

    $payloadHash = hash('sha256', $payload);

    // Canonical request (headers sorted alphabetically)
    $canonHeaders = "content-type:application/x-amz-json-1.1\nhost:{$host}\nx-amz-date:{$datetime}\nx-amz-target:{$target}\n";
    $signedHeaders = 'content-type;host;x-amz-date;x-amz-target';

    $canonRequest = implode("\n", ['POST', '/', '', $canonHeaders, $signedHeaders, $payloadHash]);

    $credScope   = "{$date}/{$region}/{$service}/aws4_request";
    $stringToSign = implode("\n", ['AWS4-HMAC-SHA256', $datetime, $credScope, hash('sha256', $canonRequest)]);

    $kDate    = hash_hmac('sha256', $date,          "AWS4{$secretKey}", true);
    $kRegion  = hash_hmac('sha256', $region,        $kDate,             true);
    $kService = hash_hmac('sha256', $service,       $kRegion,           true);
    $kSign    = hash_hmac('sha256', 'aws4_request', $kService,          true);
    $sig      = hash_hmac('sha256', $stringToSign,  $kSign);

    $authHeader = "AWS4-HMAC-SHA256 Credential={$accessKey}/{$credScope}, SignedHeaders={$signedHeaders}, Signature={$sig}";

    if (!function_exists('curl_init')) {
        return ['safe' => true, 'error' => 'cURL not available'];
    }

    $ch = curl_init("https://{$host}");
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $payload,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 25,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_HTTPHEADER     => [
            'Content-Type: application/x-amz-json-1.1',
            "Host: {$host}",
            "X-Amz-Date: {$datetime}",
            "X-Amz-Target: {$target}",
            "Authorization: {$authHeader}",
        ],
    ]);

    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlErr  = curl_error($ch);
    curl_close($ch);

    if ($response === false || $httpCode !== 200) {
        return ['safe' => true, 'error' => "AWS API error HTTP {$httpCode}: {$curlErr}"];
    }

    $data   = json_decode($response, true);
    $labels = $data['ModerationLabels'] ?? [];

    $adultCats = [
        'Explicit Nudity', 'Nudity', 'Graphic Male Nudity', 'Graphic Female Nudity',
        'Sexual Activity', 'Illustrated Explicit Nudity', 'Adult Toys', 'Suggestive',
        'Female Swimwear Or Underwear', 'Male Swimwear Or Underwear',
    ];
    $violenceCats = [
        'Violence', 'Graphic Violence Or Gore', 'Physical Violence',
        'Weapon Violence', 'Weapons', 'Self Injury',
    ];

    $blockAdult = (bool)($settings['block_adult'] ?? true);
    $blockViol  = (bool)($settings['block_violence'] ?? true);

    foreach ($labels as $lbl) {
        $name       = $lbl['Name']       ?? '';
        $confidence = (float)($lbl['Confidence'] ?? 0);

        if ($blockAdult && in_array($name, $adultCats, true) && $confidence >= $minConf) {
            return ['safe' => false, 'reason' => 'Adult content detected', 'label' => $name, 'confidence' => $confidence, 'provider' => 'aws'];
        }
        if ($blockViol && in_array($name, $violenceCats, true) && $confidence >= $minConf) {
            return ['safe' => false, 'reason' => 'Violent content detected', 'label' => $name, 'confidence' => $confidence, 'provider' => 'aws'];
        }
    }

    return ['safe' => true, 'provider' => 'aws', 'labels_checked' => count($labels)];
}

// ── Video frame extraction ────────────────────────────────────────────────────

function cm_extract_video_frame(string $videoPath): ?string
{
    $framePath = sys_get_temp_dir() . '/cm_frame_' . md5($videoPath) . '.jpg';

    // Try at 1 second first, then at frame 0
    foreach (['ffmpeg -ss 1 -i %s -vframes 1 -f image2 %s 2>/dev/null',
              'ffmpeg -i %s -vframes 1 -f image2 %s 2>/dev/null'] as $tpl) {
        $cmd = sprintf($tpl, escapeshellarg($videoPath), escapeshellarg($framePath));
        @exec($cmd, $out, $ret);
        if ($ret === 0 && file_exists($framePath) && filesize($framePath) > 0) {
            return $framePath;
        }
    }
    return null;
}

// ── Main entry point ──────────────────────────────────────────────────────────

/**
 * @param  string $filePath  Absolute path to the uploaded file
 * @param  string $fileType  'image' | 'video' | 'reel' | …
 * @param  array  $settings  Row from content_moderation_settings
 * @return array  ['safe'=>bool, 'reason'=>string, 'provider'=>string, ...]
 */
function cm_moderate(string $filePath, string $fileType, array $settings): array
{
    if (empty($settings['enabled'])) {
        return ['safe' => true, 'skipped' => true, 'reason' => 'Moderation disabled'];
    }

    $provider = $settings['provider'] ?? 'none';
    if ($provider === 'none') {
        return ['safe' => true, 'skipped' => true, 'reason' => 'No provider selected'];
    }

    if (!file_exists($filePath)) {
        return ['safe' => true, 'error' => 'File not found for moderation'];
    }

    // For video/reel, extract a frame to analyse as image
    $videoExts  = ['mp4', 'mov', 'avi', 'webm', 'mkv', 'flv', '3gp', 'wmv'];
    $ext        = strtolower(pathinfo($filePath, PATHINFO_EXTENSION));
    $isVideo    = in_array($ext, $videoExts, true)
               || stripos($fileType, 'video') !== false
               || $fileType === 'reel';

    $checkPath = $filePath;
    $tempFrame = null;

    if ($isVideo) {
        $tempFrame = cm_extract_video_frame($filePath);
        if (!$tempFrame) {
            return ['safe' => true, 'skipped' => true, 'reason' => 'Could not extract video frame (ffmpeg unavailable)'];
        }
        $checkPath = $tempFrame;
    }

    try {
        $result = match ($provider) {
            'google' => cm_moderate_google($checkPath, $settings),
            'aws'    => cm_moderate_aws($checkPath, $settings),
            default  => ['safe' => true, 'skipped' => true],
        };
    } finally {
        if ($tempFrame && file_exists($tempFrame)) {
            @unlink($tempFrame);
        }
    }

    return $result;
}

/**
 * Log a moderation result to the DB (fire-and-forget, never throws).
 */
function cm_log(PDO $pdo, array $result, int $userId = 0, ?int $postId = null, string $filePath = ''): void
{
    try {
        $status = match (true) {
            !empty($result['skipped'])       => 'skipped',
            !empty($result['error'])         => 'error',
            ($result['safe'] ?? true) === false => 'blocked',
            default                          => 'safe',
        };
        $pdo->prepare(
            "INSERT INTO moderation_log (post_id, user_id, file_path, provider, result, reason, confidence)
             VALUES (?, ?, ?, ?, ?, ?, ?)"
        )->execute([
            $postId,
            $userId ?: null,
            basename($filePath),
            $result['provider'] ?? '',
            $status,
            $result['reason'] ?? ($result['error'] ?? ''),
            $result['confidence'] ?? null,
        ]);
    } catch (Throwable $e) {}
}
