<?php
require_once 'config.php';
header('Content-Type: application/json');

// Check authentication
$headers = getallheaders();
$authHeader = isset($headers['Authorization']) ? $headers['Authorization'] : '';
$token = trim(str_replace('Bearer', '', $authHeader));

if (empty($token)) {
    echo json_encode(['status' => 'error', 'message' => 'Unauthorized']);
    exit;
}

$stmt = $conn->prepare("SELECT id FROM users WHERE api_token = ?");
$stmt->bind_param("s", $token);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    echo json_encode(['status' => 'error', 'message' => 'Invalid token']);
    exit;
}

$user = $result->fetch_assoc();
$sender_id = $user['id'];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $receiver_id = isset($_POST['receiver_id']) ? intval($_POST['receiver_id']) : 0;

    if ($receiver_id <= 0) {
        echo json_encode(['status' => 'error', 'message' => 'Invalid receiver']);
        exit;
    }

    if (!isset($_FILES['audio_file'])) {
        echo json_encode(['status' => 'error', 'message' => 'No audio file uploaded']);
        exit;
    }

    $file = $_FILES['audio_file'];

    // Check for upload errors
    if ($file['error'] !== UPLOAD_ERR_OK) {
        echo json_encode(['status' => 'error', 'message' => 'File upload error: ' . $file['error']]);
        exit;
    }

    // Process the uploaded audio
    $upload_dir = __DIR__ . '/uploads/chat_audio/';
    if (!is_dir($upload_dir)) {
        mkdir($upload_dir, 0755, true);
    }

    $file_ext = pathinfo($file['name'], PATHINFO_EXTENSION);
    // basic sanitization of ext
    if (empty($file_ext)) {
        $file_ext = 'm4a'; // default assumption for flutter_sound
    }

    // generate unique filename
    $filename = uniqid('audio_', true) . '.' . $file_ext;
    $target_file = $upload_dir . $filename;

    if (move_uploaded_file($file['tmp_name'], $target_file)) {
        // --- BunnyCDN Integration ---
        require_once __DIR__ . '/bunny_helper.php';
        $bunnyPath = 'uploads/chat_audio/' . $filename;
        $cdnUrl = uploadToBunny($target_file, $bunnyPath);

        if ($cdnUrl) {
            $audio_url = $cdnUrl;
        // @unlink($target_file);
        }
        else {
            $audio_url = 'uploads/chat_audio/' . $filename; // Fallback
        }
        // ---------------------------

        // Insert message into DB
        $stmt = $conn->prepare("INSERT INTO messages (sender_id, receiver_id, message, type) VALUES (?, ?, ?, 'audio')");
        $stmt->bind_param("iis", $sender_id, $receiver_id, $audio_url);

        if ($stmt->execute()) {
            $msg_id = $stmt->insert_id;

            // Fetch the inserted message to return
            $get_stmt = $conn->prepare("SELECT * FROM messages WHERE id = ?");
            $get_stmt->bind_param("i", $msg_id);
            $get_stmt->execute();
            $msg_row = $get_stmt->get_result()->fetch_assoc();

            echo json_encode([
                'status' => 'success',
                'message' => 'Voice message uploaded and sent',
                'data' => $msg_row
            ]);
        }
        else {
            echo json_encode(['status' => 'error', 'message' => 'Database error: ' . $conn->error]);
        }
    }
    else {
        echo json_encode(['status' => 'error', 'message' => 'Failed to move uploaded file']);
    }
}
else {
    echo json_encode(['status' => 'error', 'message' => 'Invalid request method']);
}
?>
