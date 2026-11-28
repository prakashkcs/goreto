<?php
require_once __DIR__ . '/_core.php';
require_once __DIR__ . '/_integrity.php';
admin_require_login();
$pageTitle = 'Data Integrity';
$activeNav = 'integrity';

// Read-only: "Run check now" only counts; nothing is changed or deleted.
$result = integrity_last();
if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['action'] ?? '') === 'run') {
    try {
        $result = integrity_run($pdo);
        integrity_save($result);
    } catch (Throwable $e) {
        $err = $e->getMessage();
    }
}

require __DIR__ . '/_layout_header.php';
?>
<div class="section">
  <div class="head"><b>Data Integrity</b></div>
  <div class="body">
    <p style="opacity:.8;font-size:13px;margin-bottom:14px">
      Counts records that point at something that no longer exists (for example a group
      message whose group was deleted). This check only reads data; it never deletes or
      changes anything. It also runs automatically every day.
    </p>
    <?php if (!empty($err)): ?><div class="badge danger" style="margin-bottom:12px"><?= htmlspecialchars($err) ?></div><?php endif; ?>

    <form method="post" style="margin-bottom:18px">
      <input type="hidden" name="action" value="run">
      <button type="submit" class="btn">Run check now</button>
    </form>

    <?php if (!$result): ?>
      <div style="opacity:.6">No check has run yet.</div>
    <?php else: ?>
      <div style="display:flex;gap:14px;flex-wrap:wrap;margin-bottom:18px">
        <div style="background:rgba(15,27,51,.5);border:1px solid #223a66;border-radius:10px;padding:14px 18px">
          <div style="font-size:24px;font-weight:900;color:<?= $result['orphans_total'] > 0 ? '#f87171' : '#22c55e' ?>">
            <?= number_format((int) $result['orphans_total']) ?></div>
          <div style="font-size:12px;opacity:.7">Orphan records</div>
        </div>
        <div style="background:rgba(15,27,51,.5);border:1px solid #223a66;border-radius:10px;padding:14px 18px">
          <div style="font-size:24px;font-weight:900;color:#D946EF"><?= (int) $result['relationships'] ?></div>
          <div style="font-size:12px;opacity:.7">Relationships checked</div>
        </div>
        <div style="background:rgba(15,27,51,.5);border:1px solid #223a66;border-radius:10px;padding:14px 18px">
          <div style="font-size:14px;font-weight:700"><?= htmlspecialchars($result['checked_at']) ?></div>
          <div style="font-size:12px;opacity:.7">Last checked</div>
        </div>
      </div>

      <div class="table-wrap"><table>
        <thead><tr><th>Record field</th><th>Points at</th><th>Rows</th><th>Orphans</th></tr></thead>
        <tbody>
        <?php foreach ($result['results'] as $r): ?>
          <tr>
            <td><code><?= htmlspecialchars($r['ref']) ?></code><?= !empty($r['retained']) ? ' <span class="badge">kept history</span>' : '' ?></td>
            <td><code><?= htmlspecialchars($r['parent']) ?></code></td>
            <td><?= number_format((int) $r['total']) ?></td>
            <td><span class="badge <?= $r['orphans'] > 0 ? 'danger' : 'ok' ?>"><?= (int) $r['orphans'] ?></span></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table></div>
    <?php endif; ?>
  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>
