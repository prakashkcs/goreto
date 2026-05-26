<?php
header("Content-Type: application/json; charset=utf-8");
header("Access-Control-Allow-Origin: *");

require_once __DIR__ . "/db_connect.php";

$action = $_GET["action"] ?? "";

// GET /api_subscriptions.php?action=my_subscribers&user_id=123
if ($action === "my_subscribers") {
    $userId = (int)($_GET["user_id"] ?? 0);
    if ($userId <= 0) {
        echo json_encode(["status" => "error", "message" => "Invalid user_id"]);
        exit;
    }

    $sql = "
        SELECT 
            s.id AS subscription_id,
            s.subscriber_id,
            s.started_at,
            s.expires_at,
            s.status,
            u.name,
            u.username,
            u.profile_pic
        FROM user_subscriptions s
        JOIN users u ON u.id = s.subscriber_id
        WHERE s.creator_id = ? AND s.status = 'active'
        ORDER BY s.started_at DESC
    ";

    try {
        $stmt = $pdo->prepare($sql);
        $stmt->execute([$userId]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $subscribers = [];
        foreach ($rows as $row) {
            $p = trim((string)$row["profile_pic"]);
            if ($p !== "" && !preg_match("~^https?://~i", $p)) {
                $p = "https://goreto.org/ekloadmin/" . ltrim($p, "/");
            }

            // Calculate total renewals based on months since started_at
            $createdAt = new DateTime($row["started_at"]);
            $now = new DateTime();
            $diff = $createdAt->diff($now);
            $months = ($diff->y * 12) + $diff->m;
            $renewals = max(0, $months); // 0 if in first month, 1 if in second month etc.

            $subscribers[] = [
                "id" => $row["subscriber_id"],
                "name" => $row["name"],
                "username" => $row["username"],
                "avatar" => $p,
                "subscribe_time" => $row["started_at"],
                "expires_at" => $row["expires_at"],
                "total_renewals" => $renewals,
                "status" => $row["status"],
            ];
        }

        echo json_encode([
            "status" => "success",
            "subscribers" => $subscribers
        ]);

    } catch (Throwable $e) {
        echo json_encode(["status" => "error", "message" => $e->getMessage()]);
    }
    exit;
}

echo json_encode(["status" => "error", "message" => "Unknown action"]);
?>
