<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Moderation Queue';
$activeNav = 'moderation_queue';

/*
 * Unified content-moderation queue.
 *  - Merges user_reports + sound_reports into one prioritised list
 *  - Flags CSAE / child-safety reports to the top (Google Play requirement)
 *  - Shows a 24-hour SLA badge (Nepal Social Media Directives 2080)
 *  - Takedown actions: delete post, ban user, resolve, dismiss
 *  - Live-stream moderation: force-end an active stream
 */

// CSAE detection expression reused for both tables (no column dependency).
function csae_expr(string $col): string
{
    return "($col LIKE '%CSAE%' OR $col LIKE '%child%' OR $col LIKE '%exploitation%')";
}

// ── AJAX actions ───────────────────────────────────────────────────────────
if (isset($_GET['ajax'])) {
    header('Content-Type: application/json');
    $act = $_GET['ajax'];
    $rid = (int) ($_POST['report_id'] ?? 0);
    $src = $_POST['source'] ?? 'user'; // 'user' | 'sound'
    $table = $src === 'sound' ? 'sound_reports' : 'user_reports';

    try {
        if ($act === 'resolve' || $act === 'dismiss') {
            $status = $act === 'resolve' ? 'resolved' : 'dismissed';
            $pdo->prepare("UPDATE `$table` SET status=?, updated_at=NOW() WHERE id=?")->execute([$status, $rid]);
            echo json_encode(['status' => 'success']);
            exit;
        }

        if ($act === 'delete_post') {
            $postId = 0;
            if ($src === 'sound') {
                $r = $pdo->prepare("SELECT post_id FROM sound_reports WHERE id=?");
                $r->execute([$rid]);
                $postId = (int) ($r->fetchColumn() ?: 0);
            } else {
                $r = $pdo->prepare("SELECT post_id FROM user_reports WHERE id=?");
                $r->execute([$rid]);
                $postId = (int) ($r->fetchColumn() ?: 0);
            }
            if ($postId > 0) {
                $pdo->prepare("DELETE FROM posts WHERE id=?")->execute([$postId]);
            }
            $pdo->prepare("UPDATE `$table` SET status='resolved', updated_at=NOW() WHERE id=?")->execute([$rid]);
            echo json_encode(['status' => 'success', 'post_id' => $postId]);
            exit;
        }

        if ($act === 'ban_user') {
            $target = 0;
            if ($src === 'sound') {
                $r = $pdo->prepare("SELECT post_user_id FROM sound_reports WHERE id=?");
                $r->execute([$rid]);
                $target = (int) ($r->fetchColumn() ?: 0);
            } else {
                $r = $pdo->prepare("SELECT reported_id FROM user_reports WHERE id=?");
                $r->execute([$rid]);
                $target = (int) ($r->fetchColumn() ?: 0);
            }
            if ($target > 0) {
                try {
                    $pdo->prepare("UPDATE users SET is_banned=1, ban_reason=?, banned_at=NOW() WHERE id=?")
                        ->execute(['Content policy violation (moderation queue)', $target]);
                } catch (Throwable $e) {
                    // banned_at column may not exist on some installs
                    $pdo->prepare("UPDATE users SET is_banned=1 WHERE id=?")->execute([$target]);
                }
            }
            $pdo->prepare("UPDATE `$table` SET status='resolved', updated_at=NOW() WHERE id=?")->execute([$rid]);
            echo json_encode(['status' => 'success', 'banned_user' => $target]);
            exit;
        }

        if ($act === 'force_end_live') {
            $uid = (int) ($_POST['user_id'] ?? 0);
            if ($uid > 0) {
                $pdo->prepare("DELETE FROM live_streams WHERE user_id=?")->execute([$uid]);
                // Best-effort: notify the broadcaster's app to stop the stream.
                try {
                    admin_send_notification($pdo, [
                        'target'    => 'user',
                        'user_id'   => $uid,
                        'title'     => 'Live stream ended',
                        'body'      => 'Your live stream was ended by a moderator for violating our content policy.',
                        'type'      => 'force_end_live',
                        'important' => true,
                    ]);
                } catch (Throwable $e) {
                    // push optional — the DB row deletion already removes it from discovery
                }
            }
            echo json_encode(['status' => 'success']);
            exit;
        }

        echo json_encode(['status' => 'error', 'message' => 'Unknown action']);
        exit;
    } catch (Throwable $e) {
        echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
        exit;
    }
}

// ── Filter ──────────────────────────────────────────────────────────────────
$filter = in_array($_GET['filter'] ?? '', ['pending', 'csae', 'all'], true) ? $_GET['filter'] : 'pending';

$statusCond = $filter === 'all' ? "status <> 'x'" : "status = 'pending'";

$userCsae = csae_expr('ur.reason');
$soundCsae = csae_expr('sr.reason');

$sql = "
  SELECT * FROM (
    SELECT CONVERT('user' USING utf8mb4) AS source, ur.id AS rid, ur.reporter_id, ur.reported_id AS target_user_id,
           ur.post_id, CONVERT(ur.reason USING utf8mb4) AS reason, CONVERT(ur.details USING utf8mb4) AS details,
           CONVERT(ur.status USING utf8mb4) AS status, ur.created_at,
           $userCsae AS is_csae,
           CONVERT(rep.username USING utf8mb4) AS reporter_name, CONVERT(tgt.username USING utf8mb4) AS target_name,
           CONVERT(ur.report_type USING utf8mb4) AS rtype
    FROM user_reports ur
    LEFT JOIN users rep ON rep.id = ur.reporter_id
    LEFT JOIN users tgt ON tgt.id = ur.reported_id
    WHERE ur.$statusCond
    UNION ALL
    SELECT CONVERT('sound' USING utf8mb4) AS source, sr.id AS rid, sr.reporter_id, sr.post_user_id AS target_user_id,
           sr.post_id, CONVERT(sr.reason USING utf8mb4) AS reason, CONVERT(sr.details USING utf8mb4) AS details,
           CONVERT(sr.status USING utf8mb4) AS status, sr.created_at,
           $soundCsae AS is_csae,
           CONVERT(rep.username USING utf8mb4) AS reporter_name, CONVERT(own.username USING utf8mb4) AS target_name,
           CONVERT('sound' USING utf8mb4) AS rtype
    FROM sound_reports sr
    LEFT JOIN users rep ON rep.id = sr.reporter_id
    LEFT JOIN users own ON own.id = sr.post_user_id
    WHERE sr.$statusCond
  ) q
";
if ($filter === 'csae') {
    $sql .= " WHERE q.is_csae = 1 ";
}
$sql .= " ORDER BY q.is_csae DESC, q.created_at ASC LIMIT 500";

$rows = [];
$err = '';
try {
    $rows = $pdo->query($sql)->fetchAll(PDO::FETCH_ASSOC);
} catch (Throwable $e) {
    $err = $e->getMessage();
}

// Active live streams (heartbeat within 90s)
$lives = [];
try {
    $lives = $pdo->query("SELECT user_id, user_name, avatar, viewer_count, started_at
                          FROM live_streams ORDER BY started_at DESC LIMIT 100")->fetchAll(PDO::FETCH_ASSOC);
} catch (Throwable $e) {
}

$pendingCount = 0;
$csaeCount = 0;
foreach ($rows as $r) {
    if ($r['status'] === 'pending') $pendingCount++;
    if ((int) $r['is_csae'] === 1 && $r['status'] === 'pending') $csaeCount++;
}

require __DIR__ . '/_layout_header.php';
?>
<style>
  .mq-tabs { display:flex; gap:8px; margin-bottom:16px; flex-wrap:wrap; }
  .mq-tab { padding:8px 14px; border-radius:8px; background:#1c1c28; color:#bbb; text-decoration:none; font-size:13px; border:1px solid #2a2a3a; }
  .mq-tab.active { background:#D946EF; color:#fff; border-color:#D946EF; }
  .mq-card { background:#15151f; border:1px solid #262636; border-radius:12px; padding:14px 16px; margin-bottom:12px; }
  .mq-card.csae { border-color:#ff2d55; box-shadow:0 0 0 1px #ff2d5544; }
  .mq-row { display:flex; justify-content:space-between; gap:12px; flex-wrap:wrap; }
  .mq-reason { font-weight:700; color:#fff; font-size:15px; }
  .mq-meta { color:#8a8aa0; font-size:12px; margin-top:4px; }
  .mq-details { color:#cfcfe0; font-size:13px; margin-top:8px; white-space:pre-wrap; }
  .badge { display:inline-block; padding:2px 8px; border-radius:20px; font-size:11px; font-weight:700; }
  .badge.csae { background:#ff2d55; color:#fff; }
  .badge.sla-ok { background:#1f7a3f; color:#fff; }
  .badge.sla-over { background:#b30000; color:#fff; }
  .badge.src { background:#2a2a3a; color:#aab; }
  .badge.status { background:#333; color:#ddd; }
  .mq-actions { display:flex; gap:8px; margin-top:12px; flex-wrap:wrap; }
  .mq-btn { padding:7px 12px; border:none; border-radius:8px; font-size:12.5px; cursor:pointer; font-weight:600; }
  .mq-btn.del { background:#b30000; color:#fff; }
  .mq-btn.ban { background:#ff6b00; color:#fff; }
  .mq-btn.resolve { background:#1f7a3f; color:#fff; }
  .mq-btn.dismiss { background:#3a3a4a; color:#ccc; }
  .mq-btn:disabled { opacity:.5; cursor:default; }
  .mq-section-title { color:#fff; font-size:18px; font-weight:800; margin:24px 0 12px; }
</style>

<div style="max-width:1000px;">
  <h1 style="color:#fff;font-size:24px;font-weight:800;margin-bottom:4px;">Moderation Queue</h1>
  <p style="color:#8a8aa0;font-size:13px;margin-bottom:16px;">
    Unified reports across posts, users and sounds. CSAE reports are prioritised.
    Target: action all reports within <strong>24 hours</strong>.
  </p>

  <?php if ($err): ?>
    <div style="background:#3a0000;color:#ffb3b3;padding:10px 14px;border-radius:8px;margin-bottom:12px;font-size:13px;">
      <?= htmlspecialchars($err) ?>
    </div>
  <?php endif; ?>

  <div class="mq-tabs">
    <a class="mq-tab <?= $filter === 'pending' ? 'active' : '' ?>" href="?filter=pending">Pending (<?= $pendingCount ?>)</a>
    <a class="mq-tab <?= $filter === 'csae' ? 'active' : '' ?>" href="?filter=csae">⚠ CSAE (<?= $csaeCount ?>)</a>
    <a class="mq-tab <?= $filter === 'all' ? 'active' : '' ?>" href="?filter=all">All</a>
  </div>

  <?php if (empty($rows)): ?>
    <div class="mq-card"><span style="color:#8a8aa0;">No reports in this view. 🎉</span></div>
  <?php endif; ?>

  <?php foreach ($rows as $r):
      $isCsae = (int) $r['is_csae'] === 1;
      $hoursOld = (time() - strtotime($r['created_at'])) / 3600;
      $overdue = $r['status'] === 'pending' && $hoursOld > 24;
      ?>
    <div class="mq-card <?= $isCsae ? 'csae' : '' ?>" id="rep-<?= $r['source'] ?>-<?= (int) $r['rid'] ?>">
      <div class="mq-row">
        <div>
          <div class="mq-reason">
            <?php if ($isCsae): ?><span class="badge csae">CSAE</span> <?php endif; ?>
            <?= htmlspecialchars($r['reason']) ?>
          </div>
          <div class="mq-meta">
            <span class="badge src"><?= htmlspecialchars($r['source']) ?>/<?= htmlspecialchars($r['rtype'] ?? '') ?></span>
            <span class="badge status"><?= htmlspecialchars($r['status']) ?></span>
            <?php if ($r['status'] === 'pending'): ?>
              <span class="badge <?= $overdue ? 'sla-over' : 'sla-ok' ?>">
                <?= $overdue ? 'OVERDUE' : 'SLA' ?> · <?= round($hoursOld, 1) ?>h
              </span>
            <?php endif; ?>
            &nbsp; Reporter: <strong><?= htmlspecialchars($r['reporter_name'] ?? ('#' . $r['reporter_id'])) ?></strong>
            · Target: <strong><?= htmlspecialchars($r['target_name'] ?? ('#' . $r['target_user_id'])) ?></strong>
            <?php if ($r['post_id']): ?> · Post #<?= (int) $r['post_id'] ?><?php endif; ?>
            · <?= htmlspecialchars($r['created_at']) ?>
          </div>
          <?php if (!empty($r['details'])): ?>
            <div class="mq-details"><?= htmlspecialchars($r['details']) ?></div>
          <?php endif; ?>
        </div>
      </div>
      <div class="mq-actions">
        <?php if ($r['post_id']): ?>
          <button class="mq-btn del" onclick="mqAction('delete_post','<?= $r['source'] ?>',<?= (int) $r['rid'] ?>,this,'Delete post #<?= (int) $r['post_id'] ?>? This cannot be undone.')">Delete Post</button>
        <?php endif; ?>
        <button class="mq-btn ban" onclick="mqAction('ban_user','<?= $r['source'] ?>',<?= (int) $r['rid'] ?>,this,'Ban this user?')">Ban User</button>
        <button class="mq-btn resolve" onclick="mqAction('resolve','<?= $r['source'] ?>',<?= (int) $r['rid'] ?>,this,null)">Resolve</button>
        <button class="mq-btn dismiss" onclick="mqAction('dismiss','<?= $r['source'] ?>',<?= (int) $r['rid'] ?>,this,null)">Dismiss</button>
      </div>
    </div>
  <?php endforeach; ?>

  <div class="mq-section-title">Live Streams</div>
  <?php if (empty($lives)): ?>
    <div class="mq-card"><span style="color:#8a8aa0;">No active live streams.</span></div>
  <?php endif; ?>
  <?php foreach ($lives as $lv): ?>
    <div class="mq-card" id="live-<?= (int) $lv['user_id'] ?>">
      <div class="mq-row">
        <div>
          <div class="mq-reason"><?= htmlspecialchars($lv['user_name'] ?? ('User #' . $lv['user_id'])) ?></div>
          <div class="mq-meta">User #<?= (int) $lv['user_id'] ?> · <?= (int) ($lv['viewer_count'] ?? 0) ?> viewers · started <?= htmlspecialchars($lv['started_at'] ?? '') ?></div>
        </div>
        <button class="mq-btn del" onclick="mqForceEnd(<?= (int) $lv['user_id'] ?>,this)">Force End</button>
      </div>
    </div>
  <?php endforeach; ?>
</div>

<script>
function mqAction(act, source, rid, btn, confirmMsg) {
  if (confirmMsg && !confirm(confirmMsg)) return;
  btn.disabled = true;
  var fd = new FormData();
  fd.append('report_id', rid);
  fd.append('source', source);
  fetch('?ajax=' + act, { method: 'POST', body: fd })
    .then(function (r) { return r.json(); })
    .then(function (d) {
      if (d.status === 'success') {
        var card = document.getElementById('rep-' + source + '-' + rid);
        if (card) { card.style.transition = 'opacity .3s'; card.style.opacity = '0.35'; }
        var box = btn.parentNode;
        box.innerHTML = '<span style="color:#1fd17a;font-weight:700;">✓ ' + act.replace('_', ' ') + ' done</span>';
      } else {
        btn.disabled = false;
        alert('Error: ' + (d.message || 'Unknown'));
      }
    })
    .catch(function () { btn.disabled = false; alert('Network error.'); });
}
function mqForceEnd(uid, btn) {
  if (!confirm('Force-end this live stream?')) return;
  btn.disabled = true;
  var fd = new FormData();
  fd.append('user_id', uid);
  fetch('?ajax=force_end_live', { method: 'POST', body: fd })
    .then(function (r) { return r.json(); })
    .then(function (d) {
      if (d.status === 'success') {
        var card = document.getElementById('live-' + uid);
        if (card) { card.style.opacity = '0.35'; }
        btn.outerHTML = '<span style="color:#1fd17a;font-weight:700;">✓ ended</span>';
      } else { btn.disabled = false; alert('Error: ' + (d.message || 'Unknown')); }
    })
    .catch(function () { btn.disabled = false; alert('Network error.'); });
}
</script>

<?php require __DIR__ . '/_layout_footer.php'; ?>
