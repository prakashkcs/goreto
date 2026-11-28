# Goreto — Reference Integrity Audit (read-only)

Date: 2026-11-28 · Database: MariaDB `ekloadmin_db` (production VPS) · Mode: **read-only** — only `SELECT` / `information_schema` queries, all run inside `SET SESSION TRANSACTION READ ONLY`. No code, schema or data was changed for this audit.

Legend: **[V]** verified against the live database or the live server code · **[C]** code-level finding (path exists, not observed in data) · **[R]** recommendation.

---

## 1. PROJECT-RELATIONSHIP-MAP

**Stack [V]:** Flutter app → PHP 8.3 API (`/var/www/html/ekloadmin/api/v1`, PDO, `db_connect.php`, UTC) + Node Socket.IO server (`/var/www/socket/server.js`, mysql2) → one MariaDB database. Admin panel is served from `/var/www/html/ekloadmin/admin`, which matches the repo's **`backend/admin/`** (not the root `admin/` folder — see F7).

**Schema size [V]:** 89 tables, **39 declared foreign keys**, ~130 ID-like columns. About 80 parent/child relationships exist only in application code.

**Parents and their children (only tables that hold data are listed in bold).**

| Parent | Declared FK children (ON DELETE CASCADE) | Application-only children (no FK) |
|---|---|---|
| `users.id` | calls.caller_id, collections, follows ×2, income_proofs, match_profiles, **messages ×2**, notifications.user_id, **posts**, post_comments, **post_impressions**, **post_likes**, **profile_views ×2**, stories, user_auth_tokens, user_blocks ×2, user_sessions, user_settings, user_social_links, user_streaks, user_wallets | **calls.receiver_id** (FK removed 2026-11-28, see F8), **notifications.sender_id**, **gifts_received ×2**, **gift_transactions ×2**, **wallet_transactions**, **proposals ×2**, **message_requests ×2**, **chat_groups.created_by**, **chat_group_members**, **chat_group_messages**, **post_views**, **post_engagements**, **post_profile_visits ×2**, **story_reactions/views**, **streak_rewards_log**, **user_chat_streaks**, **user_kyc**, **moderation_log**, chat_ppm_overrides ×2, nearby_alert_log ×2, mutes ×2, sounds, sound_uses, … |
| `posts.id` | collection_items, collection_posts, post_comments, post_engagements, post_impressions, post_likes, post_reports, post_trending_scores, post_views, post_virality | **posts.repost_of** (self-reference), **post_profile_visits**, **moderation_log**, comments, likes, sounds.post_id, sound_uses, sound_reports, user_reports.post_id |
| `chat_groups.id` | — | **chat_group_members**, **chat_group_messages**, chat_group_views, chat_group_bans |
| `gifts.id` | — | **gifts_received.gift_id**, **gift_transactions.gift_id** |
| `stories.id` | story_reactions, story_views | — |
| `calls.id` | call_signals | random_call_handshake.call_id, random_call_queue.call_id / broadcast_call_id |
| `sounds.id` | — | posts.sound_id, stories.sound_id, sound_uses.sound_id |

**Polymorphic references [V]:** `notifications.reference_id` (gift → gifts.id, like → posts.id, live_start / live_invite → users.id, follow / nearby / proposal / message_request → none) and `gift_transactions.context_id` (post → posts.id, live → stream/host).

**Business rules found in code [V]:**
- Users: deleted through `cascade_delete_user()` in `backend/admin/_cascade.php` (admin delete, bulk delete, and the `cron_process_deletions.php` job for user-requested deletion). It runs in one transaction, **keeps financial tables on purpose** (wallet_transactions, gift_transactions, gifts_received, withdrawals, iap_purchases, …) and writes the id to `deleted_users` so retained rows still resolve.
- Posts: deleted through `cascade_delete_post()` from every path (app `posts.php` / `api_posts.php`, admin posts, moderation queue, sound reports) — verified.
- Groups: deleted by `group_chat.php` (owner) and `admin/groups.php` — **not** through the cascade helper.
- Soft delete: none for posts/groups; users have `delete_requested_at` / `delete_scheduled_at` (scheduled hard delete) and `is_banned`.

---

## 2. REFERENCE-INTEGRITY-AUDIT

| Check | Scope | Result |
|---|---|---|
| Direct references (child → parent existence) | **118** relationships (57 currently hold rows) | **0 orphans** [V] |
| Polymorphic references | notifications.reference_id (by type), gift_transactions.context_id (by context) | **0 missing parents** [V] |
| Uniqueness | follows, post_likes, user_wallets, match_profiles, user_kyc, message_requests, chat_group_members, proposals, self-follow/gift/message | **0 duplicates** [V]; protected by UNIQUE/PRIMARY keys on follows, post_likes, proposals, user_wallets, match_profiles, user_kyc, user_settings, user_streaks, user_chat_streaks |
| Sentinel / nullable values | calls.receiver_id = 0 (1 row), nullable optional refs | Valid by design [V] |

Totals:
1. Relationships inspected: **118 direct + 2 polymorphic + 11 uniqueness checks**
2. Confirmed orphan records: **0**
3. Potential integrity issues (code paths that can create orphans or destroy data): **7** (F1–F7)
4. Valid historical / sentinel references: retained financial rows (by design, currently none belong to a deleted user) and 1 broadcast call row with receiver_id = 0
5. Highest-risk entities: **chat_groups** (+ members/messages), **users** deletion, **gifts** sending
6. Missing constraints: most relationships rely on application code only (see section 1). Adding FKs broadly is **not** recommended (sentinel zeros and deliberate financial retention would break) — see section 7.

---

## 3. ORPHAN-RECORD-REPORT

**No orphan records exist today.** Every reference in every table that holds data points at an existing parent.

Reasons this is true *today*, not guaranteed for the future: very little data (4 users, 7 posts, 1 group), and **no user has ever been deleted** (`deleted_users` is empty), so the deletion gaps below have never run.

---

## 4. ROOT-CAUSE-ANALYSIS (findings)

| ID | Severity | Entity | Evidence | Root cause | Impact | Recommendation |
|---|---|---|---|---|---|---|
| **F1** | **Critical** | chat_groups + all group data | Live `api/v1/group_chat.php` line 694 `delete_all_groups`: `DELETE FROM chat_group_messages / views / members / bans / chat_groups`; only check is `requireUser()` (line 138) [V] | Debug/compat action left in the public API with no admin check | **Any logged-in user can wipe every group, member and group message for everyone** in one request | Remove the action from the API (or restrict to admin panel) |
| **F2** | **High** | chat_groups (owner) | `_cascade.php` maps `chat_groups => ['creator_id']`; live schema: `created_by` INT NOT NULL is the real owner, `creator_id` is a legacy column, NULL for group #1 (created_by = a valid user) [V] | Cascade list generated from a column name that the app never fills | Deleting a user leaves their groups owned by a non-existent user; and if the column ever matched, the group's members/messages/views/bans would be orphaned (no FK, not deleted) | Cascade groups by `created_by` (and `creator_id`), deleting each group's children first, inside the existing transaction — **or** transfer ownership to an admin member (business decision) |
| **F3** | Medium | message_requests, chat_ppm_overrides, nearby_alert_log, messages.reaction_by | Not in `cascade_user_children()` [V]; tables exist [V] | List incomplete | Deleting a user leaves rows pointing at them (message request inbox entries, pay-per-minute overrides, nearby log rows, a reaction "by" a missing user) | Add the tables; set `messages.reaction_by` to NULL instead of deleting messages |
| **F4** | Medium | posts.repost_of, notifications.reference_id (like) | Not in `cascade_post_children()` [V]; 1 repost exists today, parent present [V] | Self-reference and polymorphic ref not considered | Deleting a post leaves its reposts pointing at nothing ("View original post" → "not found"), and like-notifications pointing at a missing post | Decide: keep reposts and show "original removed" (clear the reference), or delete reposts with the original |
| **F5** | Medium | gifts_received, gift_transactions | `gifts.php` `send`: checks only `to_user_id > 0` and not self; no existence check; no FK on either table; `credit_coins()` swallows errors [C] | Missing API validation + missing constraint | A gift to a non-existent id: sender is charged, nobody is credited (wallet FK rejects it silently), orphan gift rows are written | Verify the recipient exists (and is not banned) **before** charging |
| **F6** | Low | chat_group_views; admin group delete | Live `delete_group` deletes messages/members/bans/group but not `chat_group_views` [V]; `backend/admin/groups.php` deletes children one by one, no transaction, every error swallowed [V] | Incomplete cleanup; no transaction | Leftover view rows; a failure mid-way can leave a group without members or members without a group | Add views to the owner delete; wrap the admin delete in one transaction |
| **F7** | Medium (deploy risk) | group_chat.php, admin/gifts.php | Repo `backend/api/v1/group_chat.php` (1,250 lines) ≠ live (707 lines); repo version references 3 tables that do not exist (`chat_group_invites`, `chat_group_join_requests`, `chat_group_message_hidden`) [V]. Two admin trees: live = `backend/admin/`; root `admin/` is stale — **my own change on 2026-11-28 (gift selling settings) was made in root `admin/gifts.php` and deployed from there**, so `backend/admin/gifts.php` no longer matches the server [V] | Repo and server drifted | Deploying the repo's group_chat.php would break group deletion (missing tables → rollback → 500); the next deploy of `backend/admin/gifts.php` would silently remove the gift-selling settings | Copy the live admin/gifts.php into `backend/admin/`; do not deploy repo group_chat.php until its tables exist; retire the stale root `admin/` |
| **F8** | Info | calls.receiver_id | `fk_calls_receiver` was **dropped by me on 2026-11-28** (random calls store receiver_id = 0 for "anyone can answer"; the FK rejected it, so random calls never worked) [V] | Sentinel value incompatible with FK | User deletion still cleans `calls.receiver_id` through the cascade helper; 1 row with 0 (valid) | Keep as is; optional check constraint later |
| **F9** | Info | chat_groups.creator_id | Always NULL; real owner is `created_by` [V] | Legacy column | Not an orphan; only matters through F2 | Fix together with F2 |

---

## 5. REMEDIATION-PLAN (nothing applied — awaiting approval)

Every change below is small, touches one place, keeps the API contract, and is deployed with the existing script (automatic backup to `/root/deploy_backups/<timestamp>`, `php -l` before install). **Rollback** = restore that backup file and reload php-fpm. No data is deleted by any item; F2–F4 only change what *future* deletions clean up.

| Item | Change | Files / entities | Side effects | Migration |
|---|---|---|---|---|
| **A (F1)** | Remove `delete_all_groups` from the public API (return "Unknown action") | live `api/v1/group_chat.php` | None for the app (it never calls it — to be confirmed by grep before editing) | None |
| **B (F2, F6)** | Cascade user → groups via `created_by` (+ `creator_id`), deleting each group's messages/members/views/bans first; owner `delete_group` also clears views; admin group delete in one transaction | `backend/admin/_cascade.php`, live `group_chat.php`, `backend/admin/groups.php` | A deleted user's groups disappear with them (alternative: hand ownership to an admin member — **your choice**) | None |
| **C (F3)** | Add message_requests, chat_ppm_overrides, nearby_alert_log.other_id to the user cascade; `UPDATE messages SET reaction_by = NULL` for the deleted user | `backend/admin/_cascade.php` | None | None |
| **D (F4)** | On post delete: **either** clear `repost_of` on reposts (repost stays, shows "original removed") **or** delete reposts too — **your choice**; delete like-notifications for that post | `backend/admin/_cascade.php`; app shows "original removed" if cleared | Depends on choice | None |
| **E (F5)** | In `gifts.php send`, check the recipient exists and is not banned before charging | `backend/api/v1/gifts.php` | Gifts to invalid ids now fail with a message instead of losing coins | None |
| **F (F7)** | Copy live `admin/gifts.php` into `backend/admin/gifts.php` (repo only, no server change); mark root `admin/` as stale | repo only | None | None |
| **G (prevention)** | Read-only integrity check (the audit's orphan query) as a daily cron that logs counts and shows them in the admin dashboard; alerts when > 0 | new script + admin widget | None (read-only) | None |

Adding foreign keys is **not** proposed: sentinel values (receiver_id = 0, sounds.user_id = 0 for seeded sounds) and deliberate retention of financial rows after user deletion would be broken by blanket FKs.

---

## 6. REGRESSION-TEST-REPORT

Not applicable yet — no changes have been made. After approved changes, the plan is: re-run the full orphan/duplicate queries (expect 0), run each changed endpoint against a throw-away test user/group/post created for the test and removed afterwards (with your OK), and confirm the existing group/post/user flows still work.

---

## 7. PREVENTION-RECOMMENDATIONS

1. Keep **all** deletions going through `_cascade.php` (groups too) — one place to keep complete.
2. Regenerate the cascade lists from the live schema whenever a table is added (the header of `_cascade.php` already documents the query); include self-references and polymorphic columns.
3. Validate referenced ids in write endpoints that have no FK (gifts, proposals, message requests, group joins).
4. Daily read-only integrity check (item G) with alerting.
5. Keep the repo and server in sync (F7): deploy only from `backend/`, retire root `admin/`.
6. Use FKs only where the relationship is mandatory, has no sentinel values and no retention rule (e.g. chat_group_members.group_id → chat_groups.id with ON DELETE CASCADE would be safe after B).
