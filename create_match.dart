import 'dart:io';

void main() {
  const content = '''
<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

ini_set('display_errors', '1');
error_reporting(E_ALL);

function json_out(\$code, \$arr)
{
    http_response_code(\$code);
    echo json_encode(\$arr);
    exit;
}

// Quick check DB connection
require_once __DIR__ . '/db_connect.php';

if (!isset(\$pdo)) {
    json_out(500, ['status' => 'error', 'message' => 'Database connection failed']);
}

// ── SETUP TABLES ──
try {
    \$sql = "CREATE TABLE IF NOT EXISTS match_profiles (
        user_id INT NOT NULL PRIMARY KEY,
        gender VARCHAR(20) DEFAULT 'male',
        age INT NULL,
        location VARCHAR(255) NULL,
        bio TEXT NULL,
        income VARCHAR(100) NULL,
        income_status VARCHAR(50) DEFAULT 'none',
        interests TEXT NULL,
        qualities TEXT NULL,
        looking_for TEXT NULL,
        is_visible TINYINT(1) DEFAULT 1,
        cover_pic VARCHAR(500) NULL,
        profile_pic VARCHAR(500) NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;";
    \$pdo->exec(\$sql);

    // Table for bank statements
    \$sql2 = "CREATE TABLE IF NOT EXISTS income_proofs (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        file_url VARCHAR(500) NOT NULL,
        status VARCHAR(50) DEFAULT 'pending',
        uploaded_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;";
    \$pdo->exec(\$sql2);
}
catch (PDOException \$e) {
    // Ignore error if `users` table isn't created yet or other FK issues
    // Just in case, we create without FK if it fails
    try {
        \$pdo->exec("CREATE TABLE IF NOT EXISTS match_profiles (
            user_id INT NOT NULL PRIMARY KEY,
            gender VARCHAR(20) DEFAULT 'male',
            age INT NULL,
            location VARCHAR(255) NULL,
            bio TEXT NULL,
            income VARCHAR(100) NULL,
            income_status VARCHAR(50) DEFAULT 'none',
            interests TEXT NULL,
            qualities TEXT NULL,
            looking_for TEXT NULL,
            is_visible TINYINT(1) DEFAULT 1,
            cover_pic VARCHAR(500) NULL,
            profile_pic VARCHAR(500) NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;");

        \$pdo->exec("CREATE TABLE IF NOT EXISTS income_proofs (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            file_url VARCHAR(500) NOT NULL,
            status VARCHAR(50) DEFAULT 'pending',
            uploaded_at DATETIME DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;");
    }
    catch (PDOException \$e2) {
    // give up on table creation silently
    }
}

// ── FORCE ADD COLUMNS IF THEY DON'T EXIST ──
try {
    \$colsToAdd = [
        "gender" => "VARCHAR(20) DEFAULT 'male'",
        "age" => "INT NULL",
        "location" => "VARCHAR(255) NULL",
        "bio" => "TEXT NULL",
        "income" => "VARCHAR(100) NULL",
        "income_status" => "VARCHAR(50) DEFAULT 'none'",
        "interests" => "TEXT NULL",
        "qualities" => "TEXT NULL",
        "looking_for" => "TEXT NULL",
        "is_visible" => "TINYINT(1) DEFAULT 1",
        "cover_pic" => "VARCHAR(500) NULL",
        "profile_pic" => "VARCHAR(500) NULL"
    ];
    \$stmt = \$pdo->query("SHOW COLUMNS FROM match_profiles");
    \$existingCols = [];
    while (\$row = \$stmt->fetch(PDO::FETCH_ASSOC)) {
        \$existingCols[] = \$row['Field'];
    }
    foreach (\$colsToAdd as \$col => \$def) {
        if (!in_array(\$col, \$existingCols)) {
            \$pdo->exec("ALTER TABLE match_profiles ADD COLUMN \$col \$def");
        }
    }
}
catch (PDOException \$e) { /* ignore */
}

\$action = \$_POST['action'] ?? \$_GET['action'] ?? '';

// GET MY MATCH PROFILE
if (\$action === 'get_my_profile' || \$_SERVER['REQUEST_METHOD'] === 'GET') {
    \$userId = \$_GET['user_id'] ?? 0;
    if (!\$userId)
        json_out(400, ['status' => 'error', 'message' => 'user_id required']);

    \$stmt = \$pdo->prepare("SELECT * FROM match_profiles WHERE user_id = ?");
    \$stmt->execute([\$userId]);
    \$profile = \$stmt->fetch(PDO::FETCH_ASSOC);

    if (\$profile) {
        \$profile['interests'] = \$profile['interests'] ? explode(',', \$profile['interests']) : [];
        \$profile['qualities'] = \$profile['qualities'] ? explode(',', \$profile['qualities']) : [];
        \$profile['looking_for'] = \$profile['looking_for'] ? explode(',', \$profile['looking_for']) : [];
        \$profile['is_visible'] = (int)\$profile['is_visible'];
    }

    json_out(200, ['status' => 'success', 'profile' => \$profile]);
}

// SAVE MATCH PROFILE
if (\$action === 'save' && \$_SERVER['REQUEST_METHOD'] === 'POST') {
    \$userId = \$_POST['user_id'] ?? 0;
    if (!\$userId)
        json_out(400, ['status' => 'error', 'message' => 'user_id required']);

    // Parse fields
    \$interests = \$_POST['interests'] ?? '';
    \$qualities = \$_POST['qualities'] ?? '';
    \$lookingFor = \$_POST['looking_for'] ?? '';
    \$age = !empty(\$_POST['age']) ? (int)\$_POST['age'] : null;
    \$location = \$_POST['location'] ?? '';
    \$bio = \$_POST['bio'] ?? '';
    \$gender = \$_POST['gender'] ?? 'male';
    \$income = \$_POST['income'] ?? '';
    \$isVisible = isset(\$_POST['is_visible']) ? (int)\$_POST['is_visible'] : 1;

    // Helper: File Upload
    function uploadFile(\$fileField)
    {
        if (!isset(\$_FILES[\$fileField]) || \$_FILES[\$fileField]['error'] !== UPLOAD_ERR_OK) {
            return null;
        }
        \$dir = __DIR__ . '/uploads/match_profiles/';
        if (!is_dir(\$dir))
            @mkdir(\$dir, 0777, true);

        \$ext = strtolower(pathinfo(\$_FILES[\$fileField]['name'], PATHINFO_EXTENSION));
        \$allowed = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];
        if (!in_array(\$ext, \$allowed))
            return null;

        \$filename = uniqid('img_') . '.' . \$ext;
        \$dest = \$dir . \$filename;
        if (move_uploaded_file(\$_FILES[\$fileField]['tmp_name'], \$dest)) {
            // Return public URL relative to api/v1
            return 'uploads/match_profiles/' . \$filename;
        }
        return null;
    }

    \$profilePic = uploadFile('profile_pic');
    \$coverPic = uploadFile('cover_pic');

    // Build Upsert Query
    \$data = [
        'user_id' => \$userId,
        'gender' => \$gender,
        'age' => \$age,
        'location' => \$location,
        'bio' => \$bio,
        'income' => \$income,
        'interests' => \$interests,
        'qualities' => \$qualities,
        'looking_for' => \$lookingFor,
        'is_visible' => \$isVisible
    ];

    \$fields = array_keys(\$data);

    // Add images if uploaded
    if (\$profilePic) {
        \$fields[] = 'profile_pic';
        \$data['profile_pic'] = \$profilePic;
    }
    if (\$coverPic) {
        \$fields[] = 'cover_pic';
        \$data['cover_pic'] = \$coverPic;
    }

    // Check if new income proofs uploaded
    \$proof1 = uploadFile('income_proof_1');
    \$proof2 = uploadFile('income_proof_2');
    \$proof3 = uploadFile('income_proof_3');

    \$hasNewProofs = (\$proof1 || \$proof2 || \$proof3);
    \$chk = \$pdo->prepare("SELECT income, income_status FROM match_profiles WHERE user_id = ?");
    \$chk->execute([\$userId]);
    \$existing = \$chk->fetch(PDO::FETCH_ASSOC);

    \$oldIncomeNum = \$existing ? (float)\$existing['income'] : 0.0;
    \$oldStatus = \$existing ? \$existing['income_status'] : 'none';

    \$incomeChanged = false;
    if (\$income !== '') {
        \$incomeNum = (float)\$income;
        if (\$incomeNum != \$oldIncomeNum && \$oldStatus === 'verified') {
            \$incomeChanged = true;
        }
    }

    if (\$hasNewProofs || \$incomeChanged) {
        \$fields[] = 'income_status';
        \$data['income_status'] = 'pending';
        // Clear existing pending proofs since they're uploading/submitting a new iteration
        \$clearPending = \$pdo->prepare("DELETE FROM income_proofs WHERE user_id = ? AND status = 'pending'");
        \$clearPending->execute([\$userId]);
    }

    \$placeholders = implode(', ', array_fill(0, count(\$fields), '?'));
    \$updateFields = [];
    foreach (\$fields as \$f) {
        if (\$f !== 'user_id') {
            \$updateFields[] = "\$f = VALUES(\$f)";
        }
    }

    \$sql = "INSERT INTO match_profiles (" . implode(', ', \$fields) . ") 
            VALUES (\$placeholders) 
            ON DUPLICATE KEY UPDATE " . implode(', ', \$updateFields);

    \$stmt = \$pdo->prepare(\$sql);
    \$values = array_values(\$data);
    \$stmt->execute(\$values);

    // Save income proofs
    \$proofs = array_filter([\$proof1, \$proof2, \$proof3]);
    if (!empty(\$proofs)) {
        \$stmtProof = \$pdo->prepare("INSERT INTO income_proofs (user_id, file_url) VALUES (?, ?)");
        foreach (\$proofs as \$p) {
            \$stmtProof->execute([\$userId, \$p]);
        }
    }

    json_out(200, ['status' => 'success', 'message' => 'Profile saved']);
}

// CANCEL INCOME REVIEW
if (\$action === 'cancel_income_review' && \$_SERVER['REQUEST_METHOD'] === 'POST') {
    \$userId = \$_POST['user_id'] ?? 0;
    if (!\$userId) {
        json_out(400, ['status' => 'error', 'message' => 'user_id required']);
    }

    try {
        \$pdo->beginTransaction();

        // Delete pending proofs
        \$stmtDel = \$pdo->prepare("DELETE FROM income_proofs WHERE user_id = ? AND status = 'pending'");
        \$stmtDel->execute([\$userId]);

        // Reset income status on match profile
        \$stmtUpdate = \$pdo->prepare("UPDATE match_profiles SET income_status = 'none' WHERE user_id = ?");
        \$stmtUpdate->execute([\$userId]);

        \$pdo->commit();
        json_out(200, ['status' => 'success', 'message' => 'Income review cancelled successfully.']);
    }
    catch (Exception \$e) {
        \$pdo->rollBack();
        json_out(500, ['status' => 'error', 'message' => 'Failed to cancel review: ' . \$e->getMessage()]);
    }
}

json_out(400, ['status' => 'error', 'message' => 'Invalid action']);

''';

  File('final_match_profiles.php').writeAsStringSync(content);
}
