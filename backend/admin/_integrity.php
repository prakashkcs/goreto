<?php
/**
 * Read-only reference-integrity check (integrity audit item G).
 *
 * Counts rows whose parent record no longer exists, for every relationship
 * that has no foreign key (and the ones that do, in case checks were ever
 * disabled). It only runs SELECTs and never changes data.
 *
 * Values that mean "none" by design are not orphans: NULL, and 0 (e.g.
 * calls.receiver_id = 0 is a random call anyone may answer).
 *
 * Used by admin/integrity.php (on demand) and cron_integrity_check.php
 * (daily). The last result is stored in INTEGRITY_RESULT_FILE.
 */

const INTEGRITY_RESULT_FILE = '/var/www/private/integrity_last.json';

/** child "table.column" => parent "table.column" */
function integrity_relationships(): array
{
    return [
        'app_notifications.user_id' => 'users.id',
        'calls.caller_id' => 'users.id',
        'calls.receiver_id' => 'users.id',
        'call_signals.call_id' => 'calls.id',
        'call_signals.sender_id' => 'users.id',
        'chat_groups.created_by' => 'users.id',
        'chat_group_bans.group_id' => 'chat_groups.id',
        'chat_group_bans.user_id' => 'users.id',
        'chat_group_members.group_id' => 'chat_groups.id',
        'chat_group_members.user_id' => 'users.id',
        'chat_group_messages.group_id' => 'chat_groups.id',
        'chat_group_messages.sender_id' => 'users.id',
        'chat_group_views.group_id' => 'chat_groups.id',
        'chat_group_views.user_id' => 'users.id',
        'chat_ppm_overrides.owner_id' => 'users.id',
        'chat_ppm_overrides.target_id' => 'users.id',
        'chat_time_packages.creator_id' => 'users.id',
        'comments.post_id' => 'posts.id',
        'comments.user_id' => 'users.id',
        'follows.follower_id' => 'users.id',
        'follows.following_id' => 'users.id',
        'gifts_received.gift_id' => 'gifts.id',
        'gift_transactions.gift_id' => 'gifts.id',
        'likes.post_id' => 'posts.id',
        'likes.user_id' => 'users.id',
        'live_streams.user_id' => 'users.id',
        'match_profiles.user_id' => 'users.id',
        'messages.sender_id' => 'users.id',
        'messages.receiver_id' => 'users.id',
        'messages.reaction_by' => 'users.id',
        'message_requests.requester_id' => 'users.id',
        'message_requests.receiver_id' => 'users.id',
        'moderation_log.post_id' => 'posts.id',
        'mutes.muter_id' => 'users.id',
        'mutes.muted_id' => 'users.id',
        'nearby_alert_log.user_id' => 'users.id',
        'nearby_alert_log.other_id' => 'users.id',
        'notifications.user_id' => 'users.id',
        'notifications.sender_id' => 'users.id',
        'posts.user_id' => 'users.id',
        'posts.repost_of' => 'posts.id',
        'posts.sound_id' => 'sounds.id',
        'post_comments.post_id' => 'posts.id',
        'post_engagements.post_id' => 'posts.id',
        'post_impressions.post_id' => 'posts.id',
        'post_likes.post_id' => 'posts.id',
        'post_likes.user_id' => 'users.id',
        'post_profile_visits.post_id' => 'posts.id',
        'post_profile_visits.user_id' => 'users.id',
        'post_reports.post_id' => 'posts.id',
        'post_views.post_id' => 'posts.id',
        'profile_views.profile_id' => 'users.id',
        'profile_views.viewer_id' => 'users.id',
        'proposals.sender_id' => 'users.id',
        'proposals.receiver_id' => 'users.id',
        'random_call_handshake.call_id' => 'calls.id',
        'random_call_queue.user_id' => 'users.id',
        'sounds.post_id' => 'posts.id',
        'sound_uses.post_id' => 'posts.id',
        'sound_uses.sound_id' => 'sounds.id',
        'stories.user_id' => 'users.id',
        'story_reactions.story_id' => 'stories.id',
        'story_views.story_id' => 'stories.id',
        'streak_rewards_log.user_id' => 'users.id',
        'subscription_plans.creator_id' => 'users.id',
        'user_auth_tokens.user_id' => 'users.id',
        'user_blocks.blocker_id' => 'users.id',
        'user_blocks.blocked_id' => 'users.id',
        'user_chat_streaks.user_id' => 'users.id',
        'user_kyc.user_id' => 'users.id',
        'user_reports.reporter_id' => 'users.id',
        'user_reports.reported_id' => 'users.id',
        'user_streaks.user_id' => 'users.id',
        'user_subscriptions.plan_id' => 'subscription_plans.id',
        'user_wallets.user_id' => 'users.id',
    ];
}

/**
 * Financial rows are kept on purpose after a user is deleted (see
 * cascade_financial_tables()); their user is listed in deleted_users, so a
 * missing user there is "retained history", not an orphan.
 */
function integrity_retained(): array
{
    return [
        'gifts_received.sender_id', 'gifts_received.receiver_id',
        'gift_transactions.sender_id', 'gift_transactions.receiver_id',
        'wallet_transactions.user_id', 'withdrawals.user_id',
        'iap_purchases.user_id', 'wallet_deposits.user_id', 'wallet_requests.user_id',
    ];
}

/** Runs every check. Read-only. */
function integrity_run(PDO $pdo): array
{
    $cols = [];
    foreach ($pdo->query("SELECT TABLE_NAME, COLUMN_NAME FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE()") as $r) {
        $cols[$r['TABLE_NAME'] . '.' . $r['COLUMN_NAME']] = true;
    }
    $results = [];
    $orphansTotal = 0;
    $checks = integrity_relationships();
    foreach (integrity_retained() as $ref) {
        $checks[$ref] = 'users.id';
    }
    foreach ($checks as $child => $parent) {
        if (empty($cols[$child]) || empty($cols[$parent])) {
            continue; // table or column not present on this database
        }
        [$ct, $cc] = explode('.', $child);
        [$pt, $pc] = explode('.', $parent);
        $sql = "SELECT COUNT(*) AS total,
                       SUM(c.`$cc` IS NOT NULL AND c.`$cc` <> 0 AND p.`$pc` IS NULL) AS orphans
                  FROM `$ct` c LEFT JOIN `$pt` p ON p.`$pc` = c.`$cc`";
        $row = $pdo->query($sql)->fetch(PDO::FETCH_ASSOC);
        $orphans = (int) ($row['orphans'] ?? 0);
        $retained = in_array($child, integrity_retained(), true);
        if ($retained && $orphans > 0 && !empty($cols['deleted_users.id'])) {
            // Missing users that are recorded in deleted_users are expected.
            $u = $pdo->query("SELECT COUNT(*) FROM `$ct` c LEFT JOIN users p ON p.id = c.`$cc`
                              LEFT JOIN deleted_users d ON d.id = c.`$cc`
                              WHERE c.`$cc` IS NOT NULL AND c.`$cc` <> 0 AND p.id IS NULL AND d.id IS NULL")
                     ->fetchColumn();
            $orphans = (int) $u;
        }
        $results[] = [
            'ref'      => $child,
            'parent'   => $parent,
            'total'    => (int) ($row['total'] ?? 0),
            'orphans'  => $orphans,
            'retained' => $retained,
        ];
        $orphansTotal += $orphans;
    }
    usort($results, fn($a, $b) => $b['orphans'] <=> $a['orphans'] ?: strcmp($a['ref'], $b['ref']));
    return [
        'checked_at'    => gmdate('Y-m-d H:i:s') . ' UTC',
        'relationships' => count($results),
        'orphans_total' => $orphansTotal,
        'results'       => $results,
    ];
}

function integrity_save(array $result): void
{
    @file_put_contents(INTEGRITY_RESULT_FILE, json_encode($result, JSON_PRETTY_PRINT));
}

function integrity_last(): ?array
{
    if (!is_readable(INTEGRITY_RESULT_FILE)) return null;
    $j = json_decode((string) file_get_contents(INTEGRITY_RESULT_FILE), true);
    return is_array($j) ? $j : null;
}
