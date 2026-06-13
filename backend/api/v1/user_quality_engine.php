<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    echo json_encode(['status' => 'ok']); exit;
}

require_once __DIR__ . '/db_connect.php';

$userId = intval($_GET['user_id'] ?? 0);
if ($userId <= 0) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'message' => 'user_id required']);
    exit;
}

// ─── Helper: clamp + round ────────────────────────────────────────────────────
function clamp(float $v, float $lo, float $hi): float {
    return round(max($lo, min($hi, $v)), 4);
}

// ─── Logarithmic soft-cap: grows fast at start, slows near cap ────────────────
function logScore(float $value, float $cap, float $sensitivity = 1.0): float {
    if ($value <= 0) return 0.0;
    return clamp($cap * log1p($value * $sensitivity) / log1p($cap * $sensitivity * 10), 0, $cap);
}

try {
    // ══════════════════════════════════════════════════════════════════════════
    // 1. CORE USER DATA
    // ══════════════════════════════════════════════════════════════════════════
    $u = $pdo->prepare("SELECT id, created_at FROM users WHERE id = ?");
    $u->execute([$userId]);
    $user = $u->fetch(PDO::FETCH_ASSOC);
    if (!$user) {
        echo json_encode(['status' => 'error', 'message' => 'User not found']);
        exit;
    }

    // Fetch optional columns safely
    foreach (['bio','gender','dob','kyc_status','income_status','profile_pic','cover_pic','last_active'] as $col) {
        $user[$col] = null;
        try {
            $s = $pdo->prepare("SELECT `$col` FROM users WHERE id = ?");
            $s->execute([$userId]);
            $user[$col] = $s->fetchColumn() ?: null;
        } catch (Throwable $e) {}
    }

    // Account age in days
    $createdAt     = new DateTime($user['created_at'] ?? 'now');
    $accountAgeDays = max(0, (new DateTime())->diff($createdAt)->days);

    // Days since last active — falls back to 0 (assume active) if column missing
    $inactiveDays = 0;
    if ($user['last_active']) {
        $inactiveDays = max(0, (new DateTime())->diff(new DateTime($user['last_active']))->days);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 2. SOCIAL COUNTS
    // ══════════════════════════════════════════════════════════════════════════
    // Followers
    $followersCount = 0;
    try {
        $s = $pdo->prepare("SELECT COUNT(*) FROM follows WHERE following_id = ?");
        $s->execute([$userId]);
        $followersCount = (int)$s->fetchColumn();
    } catch (Throwable $e) {}

    // Following (engagement ratio)
    $followingCount = 0;
    try {
        $s = $pdo->prepare("SELECT COUNT(*) FROM follows WHERE follower_id = ?");
        $s->execute([$userId]);
        $followingCount = (int)$s->fetchColumn();
    } catch (Throwable $e) {}

    // ══════════════════════════════════════════════════════════════════════════
    // 3. POST ENGAGEMENT
    // ══════════════════════════════════════════════════════════════════════════
    $postCount       = 0;
    $totalLikes      = 0;
    $totalComments   = 0;
    $totalViews      = 0;

    try {
        $s = $pdo->prepare("SELECT COUNT(*) FROM posts WHERE user_id = ? AND is_deleted = 0");
        $s->execute([$userId]);
        $postCount = (int)$s->fetchColumn();
    } catch (Throwable $e) {}

    try {
        $s = $pdo->prepare("
            SELECT COALESCE(SUM(likes_count),0), COALESCE(SUM(comments_count),0), COALESCE(SUM(views_count),0)
            FROM posts WHERE user_id = ? AND is_deleted = 0
        ");
        $s->execute([$userId]);
        [$totalLikes, $totalComments, $totalViews] = $s->fetch(PDO::FETCH_NUM) ?: [0, 0, 0];
    } catch (Throwable $e) {}

    // ══════════════════════════════════════════════════════════════════════════
    // 4. PROPOSALS
    // ══════════════════════════════════════════════════════════════════════════
    $proposalsReceived = 0;
    $proposalsAccepted = 0;
    $proposalsSent     = 0;
    $proposalsSentAccepted = 0;

    try {
        $s = $pdo->prepare("SELECT COUNT(*) FROM match_proposals WHERE receiver_id = ?");
        $s->execute([$userId]);
        $proposalsReceived = (int)$s->fetchColumn();

        $s = $pdo->prepare("SELECT COUNT(*) FROM match_proposals WHERE receiver_id = ? AND status = 'accepted'");
        $s->execute([$userId]);
        $proposalsAccepted = (int)$s->fetchColumn();

        $s = $pdo->prepare("SELECT COUNT(*) FROM match_proposals WHERE sender_id = ?");
        $s->execute([$userId]);
        $proposalsSent = (int)$s->fetchColumn();

        $s = $pdo->prepare("SELECT COUNT(*) FROM match_proposals WHERE sender_id = ? AND status = 'accepted'");
        $s->execute([$userId]);
        $proposalsSentAccepted = (int)$s->fetchColumn();
    } catch (Throwable $e) {
        // Try alternate table name
        try {
            $s = $pdo->prepare("SELECT COUNT(*) FROM proposals WHERE to_user_id = ?");
            $s->execute([$userId]);
            $proposalsReceived = (int)$s->fetchColumn();

            $s = $pdo->prepare("SELECT COUNT(*) FROM proposals WHERE to_user_id = ? AND status = 'accepted'");
            $s->execute([$userId]);
            $proposalsAccepted = (int)$s->fetchColumn();
        } catch (Throwable $e2) {}
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 5. GIFTS RECEIVED
    // ══════════════════════════════════════════════════════════════════════════
    $giftsReceived = 0;
    $giftsValue    = 0;
    try {
        $s = $pdo->prepare("SELECT COUNT(*), COALESCE(SUM(coin_amount),0) FROM gift_transactions WHERE receiver_id = ?");
        $s->execute([$userId]);
        [$giftsReceived, $giftsValue] = $s->fetch(PDO::FETCH_NUM) ?: [0, 0];
    } catch (Throwable $e) {}

    // ══════════════════════════════════════════════════════════════════════════
    // 6. LIVE STREAMS
    // ══════════════════════════════════════════════════════════════════════════
    $liveSessions    = 0;
    $totalViewers    = 0;
    try {
        $s = $pdo->prepare("SELECT COUNT(*), COALESCE(SUM(peak_viewers),0) FROM live_history WHERE user_id = ?");
        $s->execute([$userId]);
        [$liveSessions, $totalViewers] = $s->fetch(PDO::FETCH_NUM) ?: [0, 0];
    } catch (Throwable $e) {}

    // ══════════════════════════════════════════════════════════════════════════
    // 7. MATCH PROFILE COMPLETENESS
    // ══════════════════════════════════════════════════════════════════════════
    $profileComplete = 0.0;
    try {
        $s = $pdo->prepare("SELECT bio, interests, looking_for, qualities, dob, city, gender FROM match_profiles WHERE user_id = ?");
        $s->execute([$userId]);
        $mp = $s->fetch(PDO::FETCH_ASSOC);
        if ($mp) {
            $fields = [
                !empty($mp['bio'])         => 0.20,
                !empty($mp['interests'])   => 0.15,
                !empty($mp['looking_for']) => 0.15,
                !empty($mp['qualities'])   => 0.10,
                !empty($mp['dob'])         => 0.10,
                !empty($mp['city'])        => 0.10,
                !empty($mp['gender'])      => 0.05,
                !empty($user['profile_pic']) => 0.10,
                !empty($user['cover_pic'])   => 0.05,
            ];
            foreach ($fields as $filled => $weight) {
                if ($filled) $profileComplete += $weight;
            }
        }
    } catch (Throwable $e) {}
    // Also use base users table bio/pic
    if ($profileComplete == 0.0) {
        $profileComplete  = 0.0;
        $profileComplete += empty($user['bio'])         ? 0 : 0.35;
        $profileComplete += empty($user['profile_pic']) ? 0 : 0.40;
        $profileComplete += empty($user['cover_pic'])   ? 0 : 0.25;
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 8. ACTIVITY RECENCY
    //    Full credit if active in last 3 days, drops off over 30 days
    // ══════════════════════════════════════════════════════════════════════════
    $activityScore = 0.0;
    if ($inactiveDays <= 3) {
        $activityScore = 1.0;
    } elseif ($inactiveDays <= 30) {
        $activityScore = 1.0 - (($inactiveDays - 3) / 27.0) * 0.6; // down to 0.4
    } elseif ($inactiveDays <= 90) {
        $activityScore = 0.4 - (($inactiveDays - 30) / 60.0) * 0.4; // down to 0
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 9. COMPUTE WEIGHTED SCORES (max possible = 10.0)
    // ══════════════════════════════════════════════════════════════════════════

    //  FACTOR                         WEIGHT   FORMULA
    $s_followers   = logScore($followersCount,   2.00, 0.05);  // max 2.00
    $s_proposals   = logScore($proposalsReceived,1.50, 0.30);  // max 1.50
    $s_engagement  = logScore($totalLikes + $totalComments * 1.5 + $totalViews * 0.1, 1.50, 0.008); // max 1.50
    $s_kyc         = ($user['kyc_status'] === 'approved')    ? 1.00 : 0.00; // max 1.00
    $s_income      = ($user['income_status'] === 'approved') ? 0.50 : 0.00; // max 0.50
    $s_activity    = clamp($activityScore * 1.00, 0, 1.00);   // max 1.00
    $s_gifts       = logScore($giftsValue,        0.50, 0.002); // max 0.50 (by value)
    $s_live        = logScore($liveSessions,      0.50, 0.40);  // max 0.50
    $s_posts       = logScore($postCount,         0.50, 0.15);  // max 0.50
    $s_profile     = clamp($profileComplete * 0.50, 0, 0.50); // max 0.50
    // Acceptance desirability bonus: ratio of accepted proposals received
    $s_desirability = 0.0;
    if ($proposalsReceived > 0) {
        $ratio          = $proposalsAccepted / $proposalsReceived;
        $s_desirability = clamp($ratio * 0.50, 0, 0.50); // max 0.50
    }

    $rawScore = $s_followers + $s_proposals + $s_engagement
              + $s_kyc + $s_income + $s_activity
              + $s_gifts + $s_live + $s_posts + $s_profile + $s_desirability;

    $rating = round(clamp($rawScore, 0.0, 10.0), 2);

    // ══════════════════════════════════════════════════════════════════════════
    // 10. DETERMINE TIER LABEL
    // ══════════════════════════════════════════════════════════════════════════
    $tier = match(true) {
        $rating >= 9.0 => 'Legendary',
        $rating >= 7.5 => 'Elite',
        $rating >= 6.0 => 'Premium',
        $rating >= 4.5 => 'Popular',
        $rating >= 3.0 => 'Rising',
        $rating >= 1.5 => 'New',
        default        => 'Unrated',
    };

    // ══════════════════════════════════════════════════════════════════════════
    // 11. CACHE IN USERS TABLE
    // ══════════════════════════════════════════════════════════════════════════
    try {
        $pdo->prepare("UPDATE users SET rating = ? WHERE id = ?")->execute([$rating, $userId]);
    } catch (Throwable $e) {}

    echo json_encode([
        'status'             => 'success',
        'user_id'            => $userId,
        'rating'             => $rating,
        'tier'               => $tier,
        'total_proposals'    => $proposalsReceived,
        'accepted_proposals' => $proposalsAccepted,
        'followers'          => $followersCount,
        'post_count'         => $postCount,
        'total_engagement'   => $totalLikes + $totalComments,
        'live_sessions'      => $liveSessions,
        'gifts_received'     => $giftsReceived,
        'kyc_verified'       => $user['kyc_status'] === 'approved',
        'income_verified'    => $user['income_status'] === 'approved',
        'profile_complete'   => round($profileComplete * 100),
        'score_breakdown'    => [
            'followers'       => round($s_followers, 2),
            'proposals'       => round($s_proposals, 2),
            'engagement'      => round($s_engagement, 2),
            'kyc'             => round($s_kyc, 2),
            'income'          => round($s_income, 2),
            'activity'        => round($s_activity, 2),
            'gifts'           => round($s_gifts, 2),
            'live'            => round($s_live, 2),
            'posts'           => round($s_posts, 2),
            'profile'         => round($s_profile, 2),
            'desirability'    => round($s_desirability, 2),
        ],
    ]);

} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
