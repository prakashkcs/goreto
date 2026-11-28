<?php
/**
 * Cascade deletion helpers.
 *
 * Only three of this database's 88 tables carry a foreign key, so deleting a
 * user or a post leaves every other dependent row behind, pointing at an id
 * that no longer exists. Before this file, admin/users.php cleaned 8 tables
 * out of the 67 that reference users, and nothing at all cleaned up after a
 * deleted post.
 *
 * The lists below were generated from the live schema, not written from
 * memory. To regenerate after adding tables:
 *
 *   SELECT TABLE_NAME, COLUMN_NAME FROM information_schema.COLUMNS
 *    WHERE TABLE_SCHEMA = DATABASE()
 *      AND COLUMN_NAME IN ('user_id','sender_id','receiver_id', ...)
 *    ORDER BY TABLE_NAME;
 *
 * Everything here runs inside one transaction and lets exceptions escape.
 * The old code wrapped each statement in `catch (Throwable $_) {}`, including
 * the DELETE FROM users itself, so a failure looked exactly like a success.
 */

/**
 * Tables that must keep their rows when a user is deleted.
 *
 * Money leaves a trail that outlives the account: refunds, chargebacks,
 * payouts and tax reporting all need the record after the person is gone.
 * These rows are deliberately retained and are NOT orphans -- deleted_users
 * below keeps the id resolvable so a report can still render them.
 */
function cascade_financial_tables(): array
{
    return [
        'wallet_transactions',
        'wallet_deposits',
        'wallet_requests',
        'withdrawals',
        'iap_purchases',
        'gift_transactions',
        'gifts_received',
        'income_proofs',
        'chat_time_sessions',
        'ppm_sessions',
        'user_subscriptions',
    ];
}

/**
 * Every (table => columns) that points at users.id.
 */
function cascade_user_children(): array
{
    return [
        'app_notifications'      => ['user_id'],
        'calls'                  => ['caller_id', 'receiver_id'],
        'call_signals'           => ['sender_id'],
        'chat_group_bans'        => ['user_id'],
        'chat_group_members'     => ['user_id'],
        'chat_group_messages'    => ['sender_id'],
        'chat_group_views'       => ['user_id'],
        'chat_ppm_overrides'     => ['owner_id', 'target_id'],
        'chat_time_packages'     => ['creator_id'],
        'chat_time_sessions'     => ['buyer_id', 'seller_id'],
        'collections'            => ['user_id'],
        'comments'               => ['user_id'],
        'content_watch'          => ['user_id'],
        'follows'                => ['follower_id', 'following_id'],
        'gifts_received'         => ['sender_id', 'receiver_id'],
        'gift_transactions'      => ['sender_id', 'receiver_id'],
        'iap_purchases'          => ['user_id'],
        'income_proofs'          => ['user_id'],
        'kyc_submissions'        => ['user_id'],
        'kyc_verifications'      => ['user_id'],
        'likes'                  => ['user_id'],
        'live_streams'           => ['user_id'],
        'match_profiles'         => ['user_id'],
        'messages'               => ['sender_id', 'receiver_id'],
        'message_requests'       => ['requester_id', 'receiver_id'],
        'moderation_log'         => ['user_id'],
        'mutes'                  => ['muter_id', 'muted_id'],
        'nearby_alert_log'       => ['user_id', 'other_id'],
        'notifications'          => ['user_id', 'sender_id'],
        'nsfw_violations'        => ['user_id'],
        'password_resets'        => ['user_id'],
        'posts'                  => ['user_id'],
        'post_comments'          => ['user_id'],
        'post_engagements'       => ['user_id'],
        'post_impressions'       => ['user_id'],
        'post_likes'             => ['user_id'],
        'post_profile_visits'    => ['user_id', 'creator_id'],
        'post_reports'           => ['reporter_id'],
        'post_views'             => ['user_id'],
        'ppm_sessions'           => ['buyer_id', 'seller_id'],
        'profile_views'          => ['viewer_id', 'profile_id'],
        'proposals'              => ['sender_id', 'receiver_id'],
        'random_call_handshake'  => ['user_id'],
        'random_call_queue'      => ['user_id', 'matched_user_id'],
        'sounds'                 => ['user_id'],
        'sound_reports'          => ['reporter_id', 'post_user_id'],
        'sound_uses'             => ['user_id'],
        'stories'                => ['user_id'],
        'story_reactions'        => ['user_id'],
        'story_views'            => ['viewer_id'],
        'streak_rewards_log'     => ['user_id'],
        'subscription_plans'     => ['creator_id'],
        'twofa_otps'             => ['user_id'],
        'user_auth_tokens'       => ['user_id'],
        'user_blocks'            => ['blocker_id', 'blocked_id'],
        'user_chat_streaks'      => ['user_id'],
        'user_kyc'               => ['user_id'],
        'user_reports'           => ['reporter_id', 'reported_id'],
        'user_sessions'          => ['user_id'],
        'user_settings'          => ['user_id'],
        'user_social_links'      => ['user_id'],
        'user_streaks'           => ['user_id'],
        'user_subscriptions'     => ['subscriber_id', 'creator_id'],
        'user_wallets'           => ['user_id'],
        'wallet_deposits'        => ['user_id'],
        'wallet_requests'        => ['user_id'],
        'wallet_transactions'    => ['user_id'],
        'withdrawals'            => ['user_id'],
    ];
}

/**
 * Every (table => columns) that points at posts.id.
 */
function cascade_post_children(): array
{
    return [
        'collection_items'     => ['post_id'],
        'collection_posts'     => ['post_id'],
        'comments'             => ['post_id'],
        'likes'                => ['post_id'],
        'moderation_log'       => ['post_id'],
        'post_comments'        => ['post_id'],
        'post_engagements'     => ['post_id'],
        'post_impressions'     => ['post_id'],
        'post_likes'           => ['post_id'],
        'post_profile_visits'  => ['post_id'],
        'post_reports'         => ['post_id'],
        'post_trending_scores' => ['post_id'],
        'post_views'           => ['post_id'],
        'post_virality'        => ['post_id'],
        'sound_reports'        => ['post_id'],
        'sound_uses'           => ['post_id'],
        'user_reports'         => ['post_id'],
    ];
}

/**
 * Tables that exist right now, so a list entry for a table dropped later
 * skips instead of aborting the whole deletion.
 */
function cascade_existing_tables(PDO $pdo): array
{
    static $cache = null;
    if ($cache !== null) {
        return $cache;
    }
    $rows = $pdo->query(
        'SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()'
    )->fetchAll(PDO::FETCH_COLUMN);
    $cache = array_flip($rows);
    return $cache;
}

/**
 * Counts what a deletion would remove, touching nothing.
 *
 * @return array<string,int> "table.column" => rows, only where rows > 0
 */
function cascade_preview(PDO $pdo, string $kind, int $id): array
{
    $children = $kind === 'user' ? cascade_user_children() : cascade_post_children();
    $keep     = $kind === 'user' ? array_flip(cascade_financial_tables()) : [];
    $present  = cascade_existing_tables($pdo);

    $out = [];
    foreach ($children as $table => $columns) {
        if (!isset($present[$table]) || isset($keep[$table])) {
            continue;
        }
        foreach ($columns as $column) {
            $st = $pdo->prepare("SELECT COUNT(*) FROM `$table` WHERE `$column` = ?");
            $st->execute([$id]);
            $n = (int) $st->fetchColumn();
            if ($n > 0) {
                $out["$table.$column"] = $n;
            }
        }
    }
    return $out;
}

/**
 * Groups owned by a user who is being deleted (integrity audit F2).
 *
 * The owner lives in chat_groups.created_by (creator_id is a legacy column
 * that is always NULL). Each group is handed to another admin of that group
 * when one exists; otherwise the group and all of its rows are removed, so no
 * member/message/view/ban row is left pointing at a deleted group.
 *
 * @return array<string,int>
 */
function cascade_user_groups(PDO $pdo, int $userId, array $present): array
{
    $out = [];
    if (!isset($present['chat_groups'])) {
        return $out;
    }
    $cols = $pdo->query("SHOW COLUMNS FROM chat_groups")->fetchAll(PDO::FETCH_COLUMN);
    $ownerCols = array_values(array_intersect(['created_by', 'creator_id'], $cols));
    if (!$ownerCols) {
        return $out;
    }
    $where = implode(' OR ', array_map(fn($c) => "`$c` = ?", $ownerCols));
    $st = $pdo->prepare("SELECT id FROM chat_groups WHERE $where");
    $st->execute(array_fill(0, count($ownerCols), $userId));
    $groupIds = $st->fetchAll(PDO::FETCH_COLUMN);

    $children = ['chat_group_messages', 'chat_group_members', 'chat_group_views', 'chat_group_bans'];
    foreach ($groupIds as $gid) {
        $gid = (int) $gid;
        $heir = false;
        if (isset($present['chat_group_members'])) {
            $h = $pdo->prepare("SELECT user_id FROM chat_group_members
                                 WHERE group_id = ? AND user_id <> ? AND role = 'admin'
                                 ORDER BY user_id LIMIT 1");
            $h->execute([$gid, $userId]);
            $heir = $h->fetchColumn();
        }
        if ($heir !== false) {
            $sets = implode(', ', array_map(fn($c) => "`$c` = ?", $ownerCols));
            $pdo->prepare("UPDATE chat_groups SET $sets WHERE id = ?")
                ->execute(array_merge(array_fill(0, count($ownerCols), (int) $heir), [$gid]));
            $out['chat_groups (owner transferred)'] = ($out['chat_groups (owner transferred)'] ?? 0) + 1;
            continue;
        }
        foreach ($children as $t) {
            if (!isset($present[$t])) continue;
            $d = $pdo->prepare("DELETE FROM `$t` WHERE group_id = ?");
            $d->execute([$gid]);
            if ($d->rowCount() > 0) {
                $out["$t.group_id"] = ($out["$t.group_id"] ?? 0) + $d->rowCount();
            }
        }
        $pdo->prepare("DELETE FROM chat_groups WHERE id = ?")->execute([$gid]);
        $out['chat_groups.id'] = ($out['chat_groups.id'] ?? 0) + 1;
    }
    return $out;
}

/**
 * Deletes a user and everything that depends on them, in one transaction.
 *
 * Financial history is kept, and the id is recorded in deleted_users so the
 * retained rows still resolve to something. Throws on failure, having rolled
 * back -- a half-deleted account is worse than one that is still there.
 *
 * @return array<string,int> what was deleted, "table.column" => rows
 */
function cascade_delete_user(PDO $pdo, int $id, string $reason = 'admin'): array
{
    if ($id <= 0) {
        throw new InvalidArgumentException('cascade_delete_user: id must be positive');
    }

    $children = cascade_user_children();
    $keep     = array_flip(cascade_financial_tables());
    $present  = cascade_existing_tables($pdo);

    $own = !$pdo->inTransaction();
    if ($own) {
        $pdo->beginTransaction();
    }

    try {
        $deleted = cascade_user_groups($pdo, $id, $present);

        // A reaction left by this user on someone else's message: keep the
        // message, drop the dangling "reacted by" (audit F3).
        if (isset($present['messages'])) {
            $r = $pdo->prepare('UPDATE messages SET reaction = NULL, reaction_by = NULL WHERE reaction_by = ?');
            $r->execute([$id]);
            if ($r->rowCount() > 0) {
                $deleted['messages.reaction_by (cleared)'] = $r->rowCount();
            }
        }

        foreach ($children as $table => $columns) {
            if (!isset($present[$table]) || isset($keep[$table])) {
                continue;
            }
            foreach ($columns as $column) {
                $st = $pdo->prepare("DELETE FROM `$table` WHERE `$column` = ?");
                $st->execute([$id]);
                if ($st->rowCount() > 0) {
                    $deleted["$table.$column"] = $st->rowCount();
                }
            }
        }

        if (isset($present['deleted_users'])) {
            $pdo->prepare(
                'INSERT INTO deleted_users (id, deleted_at, reason) VALUES (?, NOW(), ?)
                 ON DUPLICATE KEY UPDATE deleted_at = VALUES(deleted_at), reason = VALUES(reason)'
            )->execute([$id, $reason]);
        }

        $st = $pdo->prepare('DELETE FROM users WHERE id = ?');
        $st->execute([$id]);
        $deleted['users.id'] = $st->rowCount();

        if ($own) {
            $pdo->commit();
        }
        return $deleted;
    } catch (Throwable $e) {
        if ($own && $pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $e;
    }
}

/**
 * Deletes a post and everything that depends on it, in one transaction.
 *
 * @return array<string,int> what was deleted, "table.column" => rows
 */
function cascade_delete_post(PDO $pdo, int $id): array
{
    if ($id <= 0) {
        throw new InvalidArgumentException('cascade_delete_post: id must be positive');
    }

    $present = cascade_existing_tables($pdo);

    $own = !$pdo->inTransaction();
    if ($own) {
        $pdo->beginTransaction();
    }

    try {
        $deleted = [];
        foreach (cascade_post_children() as $table => $columns) {
            if (!isset($present[$table])) {
                continue;
            }
            foreach ($columns as $column) {
                $st = $pdo->prepare("DELETE FROM `$table` WHERE `$column` = ?");
                $st->execute([$id]);
                if ($st->rowCount() > 0) {
                    $deleted["$table.$column"] = $st->rowCount();
                }
            }
        }

        // Reposts of this post (audit F4): removed with it, through this same
        // function so their own likes/views/etc. go too. A post taken down
        // (often for moderation) must not live on as copies.
        $rp = $pdo->prepare('SELECT id FROM posts WHERE repost_of = ?');
        $rp->execute([$id]);
        foreach ($rp->fetchAll(PDO::FETCH_COLUMN) as $repostId) {
            if ((int) $repostId === $id) continue;
            foreach (cascade_delete_post($pdo, (int) $repostId) as $k => $n) {
                $deleted["repost: $k"] = ($deleted["repost: $k"] ?? 0) + $n;
            }
        }

        // Notifications that point at this post (like / comment / repost /
        // mention). notifications.reference_id is polymorphic, so only the
        // post-type rows are touched.
        if (isset($present['notifications'])) {
            $nt = $pdo->prepare("DELETE FROM notifications WHERE reference_id = ?
                                   AND type IN ('like','comment','repost','mention','post_like','post_comment')");
            $nt->execute([$id]);
            if ($nt->rowCount() > 0) {
                $deleted['notifications.reference_id'] = $nt->rowCount();
            }
        }

        // sounds.post_id points at the post a sound was lifted from. Clearing
        // it keeps the sound, which other posts may already use; deleting the
        // row would orphan every sound_uses entry pointing at it.
        if (isset($present['sounds'])) {
            $st = $pdo->prepare('UPDATE sounds SET post_id = NULL WHERE post_id = ?');
            $st->execute([$id]);
            if ($st->rowCount() > 0) {
                $deleted['sounds.post_id (cleared)'] = $st->rowCount();
            }
        }

        $st = $pdo->prepare('DELETE FROM posts WHERE id = ?');
        $st->execute([$id]);
        $deleted['posts.id'] = $st->rowCount();

        if ($own) {
            $pdo->commit();
        }
        return $deleted;
    } catch (Throwable $e) {
        if ($own && $pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $e;
    }
}
