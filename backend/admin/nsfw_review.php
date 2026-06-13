<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'NSFW Review';
$activeNav = 'nsfw_review';

$flash = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $uid = (int)($_POST['user_id'] ?? 0);
    $act = $_POST['act'] ?? '';
    if ($uid > 0) {
        try {
            if ($act === 'give_chance') {
                // Unblock uploads, count the chance, reset strikes, clear flags.
                $pdo->prepare('UPDATE users SET upload_blocked=0, nsfw_chances_given=nsfw_chances_given+1, nsfw_strikes=0 WHERE id=?')->execute([$uid]);
                $pdo->prepare("UPDATE nsfw_violations SET status='cleared' WHERE user_id=? AND status='flagged'")->execute([$uid]);
                $flash = 'Gave user #' . $uid . ' another chance — uploads re-enabled.';
            } elseif ($act === 'ban') {
                $pdo->prepare("UPDATE users SET is_banned=1, ban_reason='Repeated NSFW content violations', banned_at=NOW() WHERE id=?")->execute([$uid]);
                $pdo->prepare("UPDATE nsfw_violations SET status='banned' WHERE user_id=?")->execute([$uid]);
                $flash = 'Banned user #' . $uid . '.';
            } elseif ($act === 'unban') {
                $pdo->prepare('UPDATE users SET is_banned=0, ban_reason=NULL, banned_at=NULL WHERE id=?')->execute([$uid]);
                $flash = 'Unbanned user #' . $uid . '.';
            }
        } catch (Throwable $e) { $flash = 'Error: ' . $e->getMessage(); }
    }
}

$rows = [];
try {
    $rows = $pdo->query("
        SELECT u.id, u.name, u.username, u.nsfw_strikes, u.is_banned,
               COALESCE(u.upload_blocked,0) AS upload_blocked,
               COALESCE(u.nsfw_chances_given,0) AS chances,
               COUNT(v.id) AS vcount, MAX(v.created_at) AS last_at,
               SUBSTRING_INDEX(GROUP_CONCAT(v.content_type ORDER BY v.created_at DESC SEPARATOR '|'), '|', 1) AS last_type
        FROM users u
        JOIN nsfw_violations v ON v.user_id = u.id
        GROUP BY u.id, u.name, u.username, u.nsfw_strikes, u.is_banned, u.upload_blocked, u.nsfw_chances_given
        ORDER BY COALESCE(u.upload_blocked,0) DESC, u.is_banned ASC, u.nsfw_strikes DESC, last_at DESC
    ")->fetchAll(PDO::FETCH_ASSOC);
} catch (Throwable $e) { $rows = []; }

$history = [];
try {
    $history = $pdo->query("
        SELECT v.id, v.user_id, COALESCE(u.username, u.name, CONCAT('#', v.user_id)) AS uname,
               v.content_type, v.reason, v.status, v.created_at
        FROM nsfw_violations v
        LEFT JOIN users u ON u.id = v.user_id
        ORDER BY v.created_at DESC
        LIMIT 200
    ")->fetchAll(PDO::FETCH_ASSOC);
} catch (Throwable $e) { $history = []; }

include __DIR__ . '/_layout_header.php';
?>
<div class="card">
  <h2 style="margin-top:0">NSFW Violations &mdash; Users</h2>
  <p style="color:#94a3b8">Users whose uploads were auto-removed for adult content. A violation <strong>pauses all their uploads</strong> until you <strong>Give chance</strong>. "Chances" shows how many times this user has been forgiven.</p>
  <?php if ($flash): ?><div style="background:#1e293b;padding:10px 14px;border-radius:8px;margin-bottom:12px;color:#a7f3d0"><?= htmlspecialchars($flash) ?></div><?php endif; ?>
  <?php if (!$rows): ?>
    <p style="color:#64748b">No violations recorded.</p>
  <?php else: ?>
  <table class="log-table">
    <thead><tr><th>User</th><th>Uploads</th><th>Strikes</th><th>Chances given</th><th>Violations</th><th>Last</th><th>Status</th><th>Actions</th></tr></thead>
    <tbody>
    <?php foreach ($rows as $r): ?>
      <tr>
        <td><strong><?= htmlspecialchars($r['name'] ?: 'User') ?></strong><br><span style="color:#64748b">@<?= htmlspecialchars($r['username'] ?: '') ?> &middot; #<?= (int)$r['id'] ?></span></td>
        <td><?= ((int)$r['upload_blocked'] === 1) ? '<span style="color:#ef4444;font-weight:700">PAUSED</span>' : '<span style="color:#22c55e">allowed</span>' ?></td>
        <td style="font-weight:800;color:<?= ((int)$r['nsfw_strikes'])>=3?'#ef4444':'#f59e0b' ?>"><?= (int)$r['nsfw_strikes'] ?></td>
        <td style="text-align:center;font-weight:700"><?= (int)$r['chances'] ?></td>
        <td><?= (int)$r['vcount'] ?> <span style="color:#64748b">(<?= htmlspecialchars($r['last_type'] ?: '') ?>)</span></td>
        <td style="color:#94a3b8"><?= htmlspecialchars($r['last_at'] ?: '') ?></td>
        <td><?= $r['is_banned'] ? '<span style="color:#ef4444;font-weight:700">BANNED</span>' : '<span style="color:#22c55e">active</span>' ?></td>
        <td>
          <?php if (!$r['is_banned']): ?>
          <form method="post" style="display:inline" onsubmit="return confirm('Give this user another chance? Uploads will be re-enabled.')">
            <input type="hidden" name="user_id" value="<?= (int)$r['id'] ?>"><input type="hidden" name="act" value="give_chance">
            <button class="btn" type="submit">Give chance</button>
          </form>
          <form method="post" style="display:inline" onsubmit="return confirm('Ban this user permanently?')">
            <input type="hidden" name="user_id" value="<?= (int)$r['id'] ?>"><input type="hidden" name="act" value="ban">
            <button class="btn danger" type="submit">Ban</button>
          </form>
          <?php else: ?>
          <form method="post" style="display:inline" onsubmit="return confirm('Unban this user?')">
            <input type="hidden" name="user_id" value="<?= (int)$r['id'] ?>"><input type="hidden" name="act" value="unban">
            <button class="btn" type="submit">Unban</button>
          </form>
          <?php endif; ?>
        </td>
      </tr>
    <?php endforeach; ?>
    </tbody>
  </table>
  <?php endif; ?>
</div>

<div class="card" style="margin-top:18px">
  <h2 style="margin-top:0">Full Violation History</h2>
  <p style="color:#94a3b8">Every blocked upload attempt (newest first).</p>
  <?php if (!$history): ?>
    <p style="color:#64748b">No history yet.</p>
  <?php else: ?>
  <table class="log-table">
    <thead><tr><th>When</th><th>User</th><th>Type</th><th>Reason</th><th>Status</th></tr></thead>
    <tbody>
    <?php foreach ($history as $h): ?>
      <tr>
        <td style="color:#94a3b8;white-space:nowrap"><?= htmlspecialchars($h['created_at']) ?></td>
        <td>@<?= htmlspecialchars($h['uname']) ?> <span style="color:#64748b">#<?= (int)$h['user_id'] ?></span></td>
        <td><?= htmlspecialchars($h['content_type'] ?: '') ?></td>
        <td style="color:#fca5a5"><?= htmlspecialchars($h['reason'] ?: '') ?></td>
        <td><?= htmlspecialchars($h['status'] ?: '') ?></td>
      </tr>
    <?php endforeach; ?>
    </tbody>
  </table>
  <?php endif; ?>
</div>
<?php include __DIR__ . '/_layout_footer.php'; ?>
