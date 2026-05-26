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

// ─── Helpers ──────────────────────────────────────────────────────────────────

function clamp(float $v, float $lo, float $hi): float {
    return max($lo, min($hi, $v));
}

/**
 * Hard-to-max score function.
 * At v = threshold  →  0.50 × cap
 * At v = 10×        →  0.66 × cap
 * At v = 100×       →  0.79 × cap
 * At v = 1000×      →  0.88 × cap   ← nearly impossible to hit cap
 *
 * Exponent 0.28 gives aggressive diminishing returns.
 */
function hardScore(float $value, float $cap, float $threshold): float {
    if ($value <= 0.0 || $threshold <= 0.0) return 0.0;
    $v = pow($value, 0.28);
    $t = pow($threshold, 0.28);
    return (float) clamp($cap * $v / ($t + $v), 0.0, $cap);
}

/**
 * Safe DB fetch — returns 0 / [] on any error so missing tables never crash.
 */
function dbFetch(PDO $pdo, string $sql, array $params = []): mixed {
    try {
        $s = $pdo->prepare($sql);
        $s->execute($params);
        return $s->fetchColumn();
    } catch (Throwable $e) { return 0; }
}
function dbFetchRow(PDO $pdo, string $sql, array $params = []): array {
    try {
        $s = $pdo->prepare($sql);
        $s->execute($params);
        return $s->fetch(PDO::FETCH_NUM) ?: [0, 0, 0, 0];
    } catch (Throwable $e) { return [0, 0, 0, 0]; }
}

try {
    // ══════════════════════════════════════════════════════════════════════════
    // 1. CORE USER DATA
    // ══════════════════════════════════════════════════════════════════════════
    $u = $pdo->prepare("SELECT id, created_at FROM users WHERE id = ?");
    $u->execute([$userId]);
    $user = $u->fetch(PDO::FETCH_ASSOC);
    if (!$user) {
        echo json_encode(['status' => 'error', 'message' => 'User not found']); exit;
    }

    foreach (['bio','gender','dob','kyc_status','income_status','profile_pic','cover_pic','last_active'] as $col) {
        $user[$col] = null;
        try {
            $s = $pdo->prepare("SELECT `$col` FROM users WHERE id = ?");
            $s->execute([$userId]);
            $user[$col] = $s->fetchColumn() ?: null;
        } catch (Throwable $e) {}
    }

    $createdAt      = new DateTime($user['created_at'] ?? 'now');
    $accountAgeDays = max(0, (new DateTime())->diff($createdAt)->days);

    $inactiveDays = 0;
    if ($user['last_active']) {
        $inactiveDays = max(0, (new DateTime())->diff(new DateTime($user['last_active']))->days);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 2. SOCIAL COUNTS
    // ══════════════════════════════════════════════════════════════════════════
    $followersCount = (int) dbFetch($pdo, "SELECT COUNT(*) FROM follows WHERE following_id = ?", [$userId]);
    $followingCount = (int) dbFetch($pdo, "SELECT COUNT(*) FROM follows WHERE follower_id  = ?", [$userId]);

    // ══════════════════════════════════════════════════════════════════════════
    // 3. POST ENGAGEMENT
    // ══════════════════════════════════════════════════════════════════════════
    $postCount     = (int) dbFetch($pdo, "SELECT COUNT(*) FROM posts WHERE user_id = ? AND is_deleted = 0", [$userId]);
    [$totalLikes, $totalComments, $totalViews] = array_slice(dbFetchRow($pdo,
        "SELECT COALESCE(SUM(likes_count),0), COALESCE(SUM(comments_count),0), COALESCE(SUM(views_count),0)
         FROM posts WHERE user_id = ? AND is_deleted = 0", [$userId]), 0, 3);

    // Posts active in last 30 days (content consistency signal)
    $recentPostCount = (int) dbFetch($pdo,
        "SELECT COUNT(*) FROM posts WHERE user_id = ? AND is_deleted = 0 AND created_at >= NOW() - INTERVAL 30 DAY",
        [$userId]);

    // Average posts per day over account lifetime (spam detection)
    $postsPerDay = $accountAgeDays > 0 ? $postCount / $accountAgeDays : $postCount;

    // ══════════════════════════════════════════════════════════════════════════
    // 4. PROPOSALS
    // ══════════════════════════════════════════════════════════════════════════
    $proposalsReceived     = 0; $proposalsAccepted  = 0;
    $proposalsSent         = 0; $proposalsSentAcc   = 0; $proposalsSentRej = 0;

    try {
        $proposalsReceived = (int) dbFetch($pdo,
            "SELECT COUNT(*) FROM match_proposals WHERE receiver_id = ?", [$userId]);
        $proposalsAccepted = (int) dbFetch($pdo,
            "SELECT COUNT(*) FROM match_proposals WHERE receiver_id = ? AND status = 'accepted'", [$userId]);
        $proposalsSent     = (int) dbFetch($pdo,
            "SELECT COUNT(*) FROM match_proposals WHERE sender_id = ?", [$userId]);
        $proposalsSentAcc  = (int) dbFetch($pdo,
            "SELECT COUNT(*) FROM match_proposals WHERE sender_id = ? AND status = 'accepted'", [$userId]);
        $proposalsSentRej  = (int) dbFetch($pdo,
            "SELECT COUNT(*) FROM match_proposals WHERE sender_id = ? AND status = 'rejected'", [$userId]);
    } catch (Throwable $e) {
        // alternate table
        try {
            $proposalsReceived = (int) dbFetch($pdo,
                "SELECT COUNT(*) FROM proposals WHERE to_user_id = ?", [$userId]);
            $proposalsAccepted = (int) dbFetch($pdo,
                "SELECT COUNT(*) FROM proposals WHERE to_user_id = ? AND status = 'accepted'", [$userId]);
        } catch (Throwable $e2) {}
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 5. GIFTS RECEIVED
    // ══════════════════════════════════════════════════════════════════════════
    [$giftsReceived, $giftsValue] = array_slice(dbFetchRow($pdo,
        "SELECT COUNT(*), COALESCE(SUM(coin_amount),0) FROM gift_transactions WHERE receiver_id = ?",
        [$userId]), 0, 2);

    // ══════════════════════════════════════════════════════════════════════════
    // 6. LIVE STREAMS
    // ══════════════════════════════════════════════════════════════════════════
    [$liveSessions, $totalLiveViewers] = array_slice(dbFetchRow($pdo,
        "SELECT COUNT(*), COALESCE(SUM(peak_viewers),0) FROM live_history WHERE user_id = ?",
        [$userId]), 0, 2);

    // ══════════════════════════════════════════════════════════════════════════
    // 7. COMMUNITY TRUST SIGNALS
    // ══════════════════════════════════════════════════════════════════════════
    $reportsReceived = 0; $blocksReceived = 0;
    try {
        $reportsReceived = (int) dbFetch($pdo,
            "SELECT COUNT(*) FROM user_reports WHERE reported_id = ?", [$userId]);
    } catch (Throwable $e) {
        try {
            $reportsReceived = (int) dbFetch($pdo,
                "SELECT COUNT(*) FROM reports WHERE target_id = ?", [$userId]);
        } catch (Throwable $e2) {}
    }
    try {
        $blocksReceived = (int) dbFetch($pdo,
            "SELECT COUNT(*) FROM blocked_users WHERE blocked_id = ?", [$userId]);
    } catch (Throwable $e) {
        try {
            $blocksReceived = (int) dbFetch($pdo,
                "SELECT COUNT(*) FROM user_blocks WHERE target_id = ?", [$userId]);
        } catch (Throwable $e2) {}
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 8. DAILY ACTIVITY COUNT (distinct active days in last 30d)
    // ══════════════════════════════════════════════════════════════════════════
    $activeDaysLast30 = 0;
    try {
        $activeDaysLast30 = (int) dbFetch($pdo,
            "SELECT COUNT(DISTINCT DATE(created_at)) FROM activity_logs
             WHERE user_id = ? AND created_at >= NOW() - INTERVAL 30 DAY", [$userId]);
    } catch (Throwable $e) {
        try {
            $activeDaysLast30 = (int) dbFetch($pdo,
                "SELECT COUNT(DISTINCT DATE(last_seen)) FROM user_sessions
                 WHERE user_id = ? AND last_seen >= NOW() - INTERVAL 30 DAY", [$userId]);
        } catch (Throwable $e2) {
            // Fall back: if last_active within 30 days, estimate from inactiveDays
            if ($inactiveDays <= 30) {
                $activeDaysLast30 = max(1, 30 - $inactiveDays);
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 9. PROFILE COMPLETENESS
    // ══════════════════════════════════════════════════════════════════════════
    $profileComplete = 0.0;
    try {
        $s = $pdo->prepare("SELECT bio, interests, looking_for, qualities, dob, city, gender FROM match_profiles WHERE user_id = ?");
        $s->execute([$userId]);
        $mp = $s->fetch(PDO::FETCH_ASSOC);
        if ($mp) {
            $fields = [
                !empty($mp['bio'])           => 0.20,
                !empty($mp['interests'])     => 0.15,
                !empty($mp['looking_for'])   => 0.15,
                !empty($mp['qualities'])     => 0.10,
                !empty($mp['dob'])           => 0.10,
                !empty($mp['city'])          => 0.10,
                !empty($mp['gender'])        => 0.05,
                !empty($user['profile_pic']) => 0.10,
                !empty($user['cover_pic'])   => 0.05,
            ];
            foreach ($fields as $filled => $weight) {
                if ($filled) $profileComplete += $weight;
            }
        }
    } catch (Throwable $e) {}
    if ($profileComplete == 0.0) {
        $profileComplete += empty($user['bio'])         ? 0 : 0.35;
        $profileComplete += empty($user['profile_pic']) ? 0 : 0.40;
        $profileComplete += empty($user['cover_pic'])   ? 0 : 0.25;
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 10. COMPUTE ADVANCED WEIGHTED SCORES
    // ══════════════════════════════════════════════════════════════════════════

    // ── A. ACTIVITY SCORE (max 1.8) ──────────────────────────────────────────
    // Based on recent distinct active days. 30/30 days = full score.
    // Strongly penalised for inactivity via the global decay multiplier later.
    $activityRatio  = clamp($activeDaysLast30 / 30.0, 0.0, 1.0);
    // Recent-activity bonus: square root so 15/30 days = 0.71 not 0.5
    $s_activity = clamp(sqrt($activityRatio) * 1.8, 0.0, 1.8);

    // ── B. FOLLOWERS SCORE (max 1.5) ─────────────────────────────────────────
    // Threshold = 500 organic followers to hit half-score.
    // Anti-follow-spam: if following >> followers, multiply score down hard.
    $followerMultiplier = 1.0;
    if ($followingCount > 200 && $followingCount > $followersCount * 5) {
        // Likely mass-following to gain followers back — reduce to 30%
        $followerMultiplier = 0.30;
    } elseif ($followingCount > $followersCount * 3 && $followingCount > 100) {
        $followerMultiplier = 0.60;
    }
    $s_followers = hardScore($followersCount, 1.5, 500) * $followerMultiplier;

    // ── C. PROPOSAL SCORE (max 1.8) ──────────────────────────────────────────
    // Proposals received: hard threshold 15 to hit half-score
    $s_propReceived = hardScore($proposalsReceived, 0.90, 15);

    // Accept-ratio signal (only meaningful when ≥ 5 proposals received)
    $acceptRatioBonus = 0.0;
    if ($proposalsReceived >= 5) {
        $acceptRatio = $proposalsAccepted / $proposalsReceived;
        if ($acceptRatio >= 0.25 && $acceptRatio <= 0.70) {
            // Sweet spot: selective but welcoming
            $acceptRatioBonus = 0.60 * ($acceptRatio / 0.70);
        } elseif ($acceptRatio > 0.70) {
            // Too accepting → desperate signal, slight bonus only
            $acceptRatioBonus = 0.20;
        } elseif ($acceptRatio >= 0.10) {
            // Low but exists
            $acceptRatioBonus = 0.10;
        }
        // Below 10% = no bonus (sending to wrong people or low desirability)
    }

    // Sent-proposal spam penalty
    $sentSpamPenalty = 0.0;
    if ($proposalsSent >= 10) {
        $sentRejRate = $proposalsSentRej / $proposalsSent;
        if ($sentRejRate > 0.70) {
            $sentSpamPenalty = -0.50; // most people reject you → negative signal
        } elseif ($sentRejRate > 0.50) {
            $sentSpamPenalty = -0.25;
        }
        // Proposal spam rate per day
        $proposalsPerDay = $accountAgeDays > 0 ? $proposalsSent / $accountAgeDays : $proposalsSent;
        if ($proposalsPerDay > 3.0) {
            $sentSpamPenalty -= 0.30; // spamming proposals is anti-social
        }
    }

    $s_proposals = clamp($s_propReceived + $acceptRatioBonus + $sentSpamPenalty, 0.0, 1.80);

    // ── D. CONTENT QUALITY SCORE (max 1.6) ───────────────────────────────────
    // Engagement rate: how much people interact per view
    $engagementRaw  = (float)$totalLikes + (float)$totalComments * 2.0 + (float)$totalViews * 0.03;
    // Quality multiplier — reward high engagement rate, penalise post spam
    $contentQualMult = 1.0;
    if ($postCount > 5 && $totalViews > 0) {
        $avgEngPerView = ($totalLikes + $totalComments * 2) / max($totalViews, 1);
        if ($avgEngPerView < 0.005) {
            $contentQualMult = 0.40; // very low engagement despite views = low quality
        } elseif ($avgEngPerView < 0.02) {
            $contentQualMult = 0.70;
        }
    }
    // Post spam detection: > 10 posts per day average
    if ($postsPerDay > 10.0) {
        $contentQualMult *= 0.50;
    }
    // Threshold 200 engagement-units to hit half-score
    $s_contentEng   = hardScore($engagementRaw, 1.20, 200) * $contentQualMult;
    // Consistent posting bonus (recent posts) — threshold 20 recent posts
    $s_postConsist  = hardScore($recentPostCount, 0.40, 20);
    $s_content      = clamp($s_contentEng + $s_postConsist, 0.0, 1.60);

    // ── E. VERIFICATION SCORE (max 0.8) ──────────────────────────────────────
    $s_kyc    = ($user['kyc_status']    === 'approved') ? 0.50 : 0.00;
    $s_income = ($user['income_status'] === 'approved') ? 0.30 : 0.00;
    $s_verif  = $s_kyc + $s_income;

    // ── F. PROFILE COMPLETENESS (max 0.5) ────────────────────────────────────
    $s_profile = clamp($profileComplete * 0.50, 0.0, 0.50);

    // ── G. GIFT ECONOMY (max 0.5) ────────────────────────────────────────────
    // Threshold 1000 coins worth of gifts to hit half-score
    $s_gifts = hardScore((float)$giftsValue, 0.50, 1000.0);

    // ── H. LIVE STREAM QUALITY (max 0.5) ─────────────────────────────────────
    // Combined signal: sessions × average viewers
    $avgLiveViewers = $liveSessions > 0 ? (float)$totalLiveViewers / $liveSessions : 0;
    $liveQuality    = (float)$liveSessions * max($avgLiveViewers, 1.0);
    $s_live = hardScore($liveQuality, 0.50, 200.0); // threshold: 200 viewer-sessions

    // ── I. ACCOUNT AGE BONUS (max 0.3) ───────────────────────────────────────
    // Linear: 0 at day 0, caps at 365 days (1 year = 0.30)
    $s_age = clamp($accountAgeDays / 365.0 * 0.30, 0.0, 0.30);

    // ── J. COMMUNITY TRUST PENALTY (0 to -2.0) ───────────────────────────────
    // Each verified report -0.25, capped at -1.20
    // Each block -0.04, capped at -0.80
    $s_trust = -(clamp($reportsReceived * 0.25, 0.0, 1.20))
               -(clamp($blocksReceived  * 0.04, 0.0, 0.80));

    // ══════════════════════════════════════════════════════════════════════════
    // 11. RAW SUM & NORMALISE TO 10.0
    //     Theoretical max positive = 1.8+1.5+1.8+1.6+0.8+0.5+0.5+0.5+0.3 = 9.3
    // ══════════════════════════════════════════════════════════════════════════
    $rawScore = $s_activity + $s_followers + $s_proposals + $s_content
              + $s_verif + $s_profile + $s_gifts + $s_live + $s_age + $s_trust;

    $normalised = $rawScore * (10.0 / 9.3); // scale to 10

    // ══════════════════════════════════════════════════════════════════════════
    // 12. INACTIVITY DECAY — MULTIPLICATIVE, AGGRESSIVE
    //     This is the primary "easy to decrease" lever.
    //     Even a star account drops to near-zero if dormant for 3 months.
    // ══════════════════════════════════════════════════════════════════════════
    $decayMultiplier = match(true) {
        $inactiveDays <= 3  => 1.00,
        $inactiveDays <= 7  => 0.88,
        $inactiveDays <= 14 => 0.72,
        $inactiveDays <= 21 => 0.58,
        $inactiveDays <= 30 => 0.42,
        $inactiveDays <= 45 => 0.26,
        $inactiveDays <= 60 => 0.14,
        $inactiveDays <= 90 => 0.05,
        default             => 0.01, // essentially zero after 90 days
    };
    $decayedScore = $normalised * $decayMultiplier;

    // ══════════════════════════════════════════════════════════════════════════
    // 13. MATURITY GATE — NEW ACCOUNTS CANNOT JUMP TO HIGH SCORES
    //     No matter how well they perform, young accounts are hard-capped.
    //     This prevents fake/new accounts from gaming the system.
    // ══════════════════════════════════════════════════════════════════════════
    $ageCap = match(true) {
        $accountAgeDays < 7   => 1.0,   // < 1 week  : max 1.0
        $accountAgeDays < 30  => 2.5,   // < 1 month : max 2.5
        $accountAgeDays < 90  => 4.5,   // < 3 months: max 4.5
        $accountAgeDays < 180 => 6.5,   // < 6 months: max 6.5
        $accountAgeDays < 365 => 8.0,   // < 1 year  : max 8.0
        default               => 10.0,  // 1 year+   : uncapped
    };

    $rating = (float) round(clamp($decayedScore, 0.0, $ageCap), 2);

    // ══════════════════════════════════════════════════════════════════════════
    // 14. TIER LABEL
    // ══════════════════════════════════════════════════════════════════════════
    $tier = match(true) {
        $rating >= 9.0 => 'Legendary',  // #FF9500  — virtually impossible to reach
        $rating >= 7.5 => 'Elite',       // #BF5AF2
        $rating >= 6.0 => 'Premium',     // #0A84FF
        $rating >= 4.5 => 'Popular',     // #30D158
        $rating >= 3.0 => 'Rising',      // #FF6B9D
        $rating >= 1.5 => 'Active',      // #8E8E93
        $rating >= 0.5 => 'New',         // #636366
        default        => 'Unrated',     // #3A3A3C
    };

    // ══════════════════════════════════════════════════════════════════════════
    // 15. CACHE RATING IN USERS TABLE
    // ══════════════════════════════════════════════════════════════════════════
    try {
        $pdo->prepare("UPDATE users SET rating = ? WHERE id = ?")->execute([$rating, $userId]);
    } catch (Throwable $e) {}
    // Also sync to match_profiles for nearby-sort queries
    try {
        $pdo->prepare("UPDATE match_profiles SET rating = ? WHERE user_id = ?")->execute([$rating, $userId]);
    } catch (Throwable $e) {}

    // ══════════════════════════════════════════════════════════════════════════
    // 16. RESPONSE
    // ══════════════════════════════════════════════════════════════════════════
    echo json_encode([
        'status'               => 'success',
        'user_id'              => $userId,
        'rating'               => $rating,
        'tier'                 => $tier,
        'age_cap'              => $ageCap,
        'decay_multiplier'     => $decayMultiplier,
        'account_age_days'     => $accountAgeDays,
        'inactive_days'        => $inactiveDays,
        'followers'            => $followersCount,
        'following'            => $followingCount,
        'post_count'           => $postCount,
        'total_engagement'     => (int)$totalLikes + (int)$totalComments,
        'total_views'          => (int)$totalViews,
        'proposals_received'   => $proposalsReceived,
        'proposals_accepted'   => $proposalsAccepted,
        'proposals_sent'       => $proposalsSent,
        'proposals_sent_acc'   => $proposalsSentAcc,
        'live_sessions'        => $liveSessions,
        'gifts_received'       => $giftsReceived,
        'gifts_value'          => (int)$giftsValue,
        'reports_received'     => $reportsReceived,
        'blocks_received'      => $blocksReceived,
        'active_days_last_30'  => $activeDaysLast30,
        'kyc_verified'         => $user['kyc_status'] === 'approved',
        'income_verified'      => $user['income_status'] === 'approved',
        'profile_complete_pct' => round($profileComplete * 100),
        'score_breakdown' => [
            'activity'        => round($s_activity,   3),
            'followers'       => round($s_followers,  3),
            'proposals'       => round($s_proposals,  3),
            'content'         => round($s_content,    3),
            'verification'    => round($s_verif,      3),
            'profile'         => round($s_profile,    3),
            'gifts'           => round($s_gifts,      3),
            'live'            => round($s_live,       3),
            'age_bonus'       => round($s_age,        3),
            'trust_penalty'   => round($s_trust,      3),
            'raw_normalised'  => round($normalised,   3),
            'after_decay'     => round($decayedScore, 3),
        ],
    ]);

} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
