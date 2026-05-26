<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Audio Reports';
$activeNav = 'sound_reports';

$pdo->exec("CREATE TABLE IF NOT EXISTS sound_reports (
  id INT AUTO_INCREMENT PRIMARY KEY,
  reporter_id INT NOT NULL,
  post_id INT NOT NULL,
  post_user_id INT NULL,
  sound_name VARCHAR(255) DEFAULT '',
  reason VARCHAR(120) NOT NULL,
  details TEXT NULL,
  status ENUM('pending','reviewed','resolved','dismissed') NOT NULL DEFAULT 'pending',
  admin_notes TEXT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_sound_reports_status (status),
  INDEX idx_sound_reports_post_id (post_id),
  INDEX idx_sound_reports_reporter_id (reporter_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

if (isset($_GET['ajax'])) {
    header('Content-Type: application/json');
    if ($_GET['ajax'] === 'delete_report') {
        $rid = (int) ($_POST['report_id'] ?? 0);
        if ($rid > 0) {
            $pdo->prepare("DELETE FROM sound_reports WHERE id=?")->execute([$rid]);
        }
        echo json_encode(['status' => 'success']);
        exit;
    }
    if ($_GET['ajax'] === 'remove_sound') {
        $rid = (int) ($_POST['report_id'] ?? 0);
        if ($rid > 0) {
            $row = $pdo->prepare("SELECT post_id FROM sound_reports WHERE id=?");
            $row->execute([$rid]);
            $sr = $row->fetch(PDO::FETCH_ASSOC);
            if ($sr) {
                $pdo->prepare("UPDATE posts SET sound_name=NULL, sound_url=NULL WHERE id=?")->execute([$sr['post_id']]);
                $pdo->prepare("UPDATE sound_reports SET status='resolved', admin_notes=CONCAT(IFNULL(admin_notes,''),' [Sound removed by admin]'), updated_at=NOW() WHERE id=?")->execute([$rid]);
            }
        }
        echo json_encode(['status' => 'success']);
        exit;
    }
    if ($_GET['ajax'] === 'delete_post') {
        $rid = (int) ($_POST['report_id'] ?? 0);
        if ($rid > 0) {
            $row = $pdo->prepare("SELECT post_id FROM sound_reports WHERE id=?");
            $row->execute([$rid]);
            $sr = $row->fetch(PDO::FETCH_ASSOC);
            if ($sr) {
                $pdo->prepare("DELETE FROM posts WHERE id=?")->execute([$sr['post_id']]);
                $pdo->prepare("UPDATE sound_reports SET status='resolved', admin_notes=CONCAT(IFNULL(admin_notes,''),' [Post deleted by admin]'), updated_at=NOW() WHERE id=?")->execute([$rid]);
            }
        }
        echo json_encode(['status' => 'success']);
        exit;
    }
    echo json_encode(['status' => 'error', 'message' => 'Unknown action']);
    exit;
}

$msg = '';
$err = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['report_id'])) {
    $rid = (int) $_POST['report_id'];
    $status = $_POST['status'] ?? '';
    $notes = trim($_POST['admin_notes'] ?? '');
    if (in_array($status, ['pending', 'reviewed', 'resolved', 'dismissed'], true)) {
        try {
            $pdo->prepare("UPDATE sound_reports SET status=?, admin_notes=?, updated_at=NOW() WHERE id=?")
                ->execute([$status, $notes, $rid]);
            $msg = "Audio report #{$rid} updated.";
        } catch (Throwable $e) {
            $err = $e->getMessage();
        }
    }
}

$filter = in_array($_GET['filter'] ?? '', ['pending', 'reviewed', 'resolved', 'dismissed', 'all'], true)
    ? $_GET['filter']
    : 'pending';
$where = $filter !== 'all' ? "WHERE sr.status=" . $pdo->quote($filter) : '';

$rows = [];
try {
    $rows = $pdo->query("
    SELECT sr.*, 
           reporter.name AS reporter_name,
           reporter.username AS reporter_username,
           owner.name AS owner_name,
           owner.username AS owner_username,
           p.caption AS post_caption,
           p.file_url AS post_file_url,
           NULL AS post_thumb
    FROM sound_reports sr
    LEFT JOIN users reporter ON reporter.id = sr.reporter_id
    LEFT JOIN users owner ON owner.id = sr.post_user_id
    LEFT JOIN posts p ON p.id = sr.post_id
    $where
    ORDER BY sr.id DESC
    LIMIT 300
  ")->fetchAll();
} catch (Throwable $e) {
    $err = $e->getMessage();
}

$stats = [
    'all' => 0,
    'pending' => 0,
    'reviewed' => 0,
    'resolved' => 0,
    'dismissed' => 0,
];

try {
    $summary = $pdo->query("SELECT status, COUNT(*) AS total FROM sound_reports GROUP BY status")->fetchAll(PDO::FETCH_ASSOC);
    foreach ($summary as $item) {
        $statusKey = (string) ($item['status'] ?? '');
        $total = (int) ($item['total'] ?? 0);
        if (isset($stats[$statusKey])) {
            $stats[$statusKey] = $total;
        }
        $stats['all'] += $total;
    }
} catch (Throwable $_) {
    $stats['all'] = count($rows);
}

function hsr($value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8');
}

function sound_status_meta(string $status): array
{
    return match ($status) {
        'pending' => ['class' => 'warn', 'label' => 'Pending Review'],
        'reviewed' => ['class' => '', 'label' => 'Reviewed'],
        'resolved' => ['class' => 'ok', 'label' => 'Resolved'],
        'dismissed' => ['class' => 'danger', 'label' => 'Dismissed'],
        default => ['class' => '', 'label' => ucfirst($status)],
    };
}

require __DIR__ . '/_layout_header.php';
?>
<style>
    .audio-hero {
        display: grid;
        grid-template-columns: 1.4fr .9fr;
        gap: 18px;
        margin-bottom: 18px;
    }

    .audio-hero-card,
    .audio-stat-card,
    .audio-report-card {
        background: linear-gradient(180deg, rgba(15, 27, 51, .92), rgba(10, 17, 34, .96));
        border: 1px solid #223a66;
        border-radius: 18px;
        box-shadow: 0 18px 40px rgba(0, 0, 0, .22);
    }

    .audio-hero-card {
        padding: 20px;
    }

    .audio-hero-card h2 {
        margin: 0 0 8px;
        font-size: 26px;
        color: #fff;
    }

    .audio-hero-card p {
        margin: 0;
        color: #9fb4d1;
        line-height: 1.55;
        max-width: 760px;
    }

    .audio-hero-actions {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
        margin-top: 16px;
    }

    .audio-stat-grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 12px;
    }

    .audio-stat-card {
        padding: 16px;
    }

    .audio-stat-card .k {
        color: #91a8c7;
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: .08em;
        margin-bottom: 8px;
    }

    .audio-stat-card .v {
        color: #fff;
        font-size: 28px;
        font-weight: 800;
    }

    .audio-tab-bar {
        display: flex;
        gap: 0;
        margin: 18px 0 22px;
        background: rgba(8, 14, 28, .85);
        border: 1px solid #1e3460;
        border-radius: 16px;
        padding: 5px;
        overflow-x: auto;
        scrollbar-width: none;
    }

    .audio-tab-bar::-webkit-scrollbar {
        display: none;
    }

    .audio-tab {
        display: inline-flex;
        flex-direction: column;
        align-items: center;
        gap: 4px;
        padding: 10px 20px;
        border-radius: 12px;
        text-decoration: none;
        font-weight: 700;
        font-size: 13px;
        color: #7a93b8;
        transition: background .18s, color .18s, box-shadow .18s;
        white-space: nowrap;
        flex: 1;
        min-width: 90px;
        position: relative;
    }

    .audio-tab:hover {
        background: rgba(255, 255, 255, .05);
        color: #c8d8f0;
    }

    .audio-tab .tab-icon {
        font-size: 18px;
        line-height: 1;
    }

    .audio-tab .tab-label {
        font-size: 12px;
        letter-spacing: .04em;
    }

    .audio-tab .tab-count {
        font-size: 18px;
        font-weight: 900;
        line-height: 1;
        color: #fff;
    }

    .audio-tab .tab-bar-line {
        position: absolute;
        bottom: 0;
        left: 20%;
        right: 20%;
        height: 3px;
        border-radius: 3px;
        background: transparent;
        transition: background .18s;
    }

    .audio-tab.tab-pending.active {
        background: rgba(251, 191, 36, .10);
        color: #fde68a;
        box-shadow: 0 2px 18px rgba(251, 191, 36, .12);
    }

    .audio-tab.tab-pending .tab-count {
        color: #fbbf24;
    }

    .audio-tab.tab-pending.active .tab-bar-line {
        background: #fbbf24;
    }

    .audio-tab.tab-reviewed.active {
        background: rgba(99, 179, 237, .10);
        color: #bfdbfe;
        box-shadow: 0 2px 18px rgba(99, 179, 237, .12);
    }

    .audio-tab.tab-reviewed .tab-count {
        color: #60a5fa;
    }

    .audio-tab.tab-reviewed.active .tab-bar-line {
        background: #60a5fa;
    }

    .audio-tab.tab-resolved.active {
        background: rgba(34, 197, 94, .10);
        color: #bbf7d0;
        box-shadow: 0 2px 18px rgba(34, 197, 94, .12);
    }

    .audio-tab.tab-resolved .tab-count {
        color: #4ade80;
    }

    .audio-tab.tab-resolved.active .tab-bar-line {
        background: #4ade80;
    }

    .audio-tab.tab-dismissed.active {
        background: rgba(248, 113, 113, .10);
        color: #fecaca;
        box-shadow: 0 2px 18px rgba(248, 113, 113, .12);
    }

    .audio-tab.tab-dismissed .tab-count {
        color: #f87171;
    }

    .audio-tab.tab-dismissed.active .tab-bar-line {
        background: #f87171;
    }

    .audio-tab.tab-all.active {
        background: rgba(167, 139, 250, .10);
        color: #e9d5ff;
        box-shadow: 0 2px 18px rgba(167, 139, 250, .12);
    }

    .audio-tab.tab-all .tab-count {
        color: #a78bfa;
    }

    .audio-tab.tab-all.active .tab-bar-line {
        background: #a78bfa;
    }

    .audio-card-list {
        display: grid;
        gap: 16px;
    }

    .audio-report-card {
        padding: 18px;
    }

    .audio-report-head {
        display: flex;
        justify-content: space-between;
        gap: 14px;
        align-items: flex-start;
        margin-bottom: 14px;
    }

    .audio-report-title {
        color: #fff;
        font-size: 18px;
        font-weight: 800;
        margin: 0 0 6px;
    }

    .audio-muted {
        color: #95a9c7;
        font-size: 13px;
        line-height: 1.5;
    }

    .audio-pill-row {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
        margin-top: 8px;
    }

    .audio-pill {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 6px 10px;
        border-radius: 999px;
        background: rgba(148, 163, 184, .12);
        color: #dbeafe;
        font-size: 12px;
        border: 1px solid rgba(148, 163, 184, .22);
    }

    .audio-report-grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 14px;
        margin: 14px 0;
    }

    .audio-info-box {
        padding: 12px;
        border-radius: 14px;
        background: rgba(8, 14, 28, .75);
        border: 1px solid rgba(34, 58, 102, .75);
    }

    .audio-info-box b {
        display: block;
        color: #fff;
        margin-bottom: 5px;
    }

    .audio-preview {
        margin-top: 12px;
        padding: 12px;
        border-radius: 14px;
        background: rgba(10, 16, 30, .88);
        border: 1px dashed rgba(89, 117, 166, .55);
    }

    .audio-preview a {
        color: #8ec5ff;
        text-decoration: none;
    }

    .audio-form {
        margin-top: 16px;
        display: grid;
        grid-template-columns: 180px minmax(220px, 1fr) auto auto auto auto;
        gap: 10px;
        align-items: center;
    }

    .audio-form select,
    .audio-form input {
        width: 100%;
        padding: 10px 12px;
        border-radius: 12px;
        border: 1px solid #2b4678;
        background: #0b1324;
        color: #fff;
    }

    .audio-empty {
        padding: 34px 20px;
        text-align: center;
        color: #8ea4c4;
        border: 1px dashed #294571;
        border-radius: 18px;
        background: rgba(9, 16, 32, .66);
    }

    @media (max-width: 980px) {

        .audio-hero,
        .audio-report-grid,
        .audio-form {
            grid-template-columns: 1fr;
        }
    }
</style>

<div class="audio-hero">
    <div class="audio-hero-card">
        <h2>Audio / Sound Reports</h2>
        <p>Review reels and posts reported for copyrighted audio, offensive sound, fake audio attribution, or broken
            sound uploads. This page is now available directly in the admin navigation and redesigned for faster
            moderation.</p>
        <div class="audio-hero-actions">
            <a class="btn" href="dashboard.php">Back to Dashboard</a>
            <a class="btn" href="reports.php">Open User Reports</a>
            <a class="btn ok" href="?filter=pending">Review Pending</a>
        </div>
    </div>
    <div class="audio-stat-grid">
        <div class="audio-stat-card">
            <div class="k">Total Reports</div>
            <div class="v"><?= (int) $stats['all'] ?></div>
        </div>
        <div class="audio-stat-card">
            <div class="k">Pending</div>
            <div class="v"><?= (int) $stats['pending'] ?></div>
        </div>
        <div class="audio-stat-card">
            <div class="k">Resolved</div>
            <div class="v"><?= (int) $stats['resolved'] ?></div>
        </div>
        <div class="audio-stat-card">
            <div class="k">Dismissed</div>
            <div class="v"><?= (int) $stats['dismissed'] ?></div>
        </div>
    </div>
</div>

<div class="section">
    <div class="head">
        <b>Moderation Queue</b>
        <small><?= count($rows) ?> visible reports</small>
    </div>
    <div class="body">
        <?php if ($msg): ?>
            <div class="badge ok" style="margin-bottom:14px"><?= hsr($msg) ?></div>
        <?php endif; ?>
        <?php if ($err): ?>
            <div class="badge danger" style="margin-bottom:14px"><?= hsr($err) ?></div>
        <?php endif; ?>

        <?php
        $tabMeta = [
            'pending' => ['icon' => '⏳', 'label' => 'Pending'],
            'reviewed' => ['icon' => '🔍', 'label' => 'Reviewed'],
            'resolved' => ['icon' => '✅', 'label' => 'Resolved'],
            'dismissed' => ['icon' => '🚫', 'label' => 'Dismissed'],
            'all' => ['icon' => '📋', 'label' => 'All'],
        ];
        ?>
        <div class="audio-tab-bar">
            <?php foreach ($tabMeta as $f => $tm): ?>
                <a class="audio-tab tab-<?= $f ?> <?= $filter === $f ? 'active' : '' ?>" href="?filter=<?= hsr($f) ?>">
                    <span class="tab-icon"><?= $tm['icon'] ?></span>
                    <span class="tab-count"><?= (int) ($stats[$f] ?? 0) ?></span>
                    <span class="tab-label"><?= $tm['label'] ?></span>
                    <span class="tab-bar-line"></span>
                </a>
            <?php endforeach; ?>
        </div>

        <?php if (empty($rows)): ?>
            <div class="audio-empty">
                No <?= hsr($filter) ?> audio reports found right now.
            </div>
        <?php else: ?>
            <div class="audio-card-list">
                <?php foreach ($rows as $r): ?>
                    <?php $meta = sound_status_meta((string) ($r['status'] ?? 'pending')); ?>
                    <div class="audio-report-card">
                        <div class="audio-report-head">
                            <div>
                                <div class="audio-report-title"><?= hsr($r['sound_name'] ?: 'Original Audio') ?></div>
                                <div class="audio-muted">Report #<?= (int) $r['id'] ?> · Created
                                    <?= hsr(substr((string) ($r['created_at'] ?? ''), 0, 16)) ?> · Updated
                                    <?= hsr(substr((string) ($r['updated_at'] ?? ''), 0, 16)) ?>
                                </div>
                                <div class="audio-pill-row">
                                    <span class="badge <?= hsr($meta['class']) ?>"><?= hsr($meta['label']) ?></span>
                                    <span class="audio-pill">Reason: <?= hsr($r['reason'] ?? '—') ?></span>
                                    <span class="audio-pill">Post ID: <?= (int) $r['post_id'] ?></span>
                                </div>
                            </div>
                            <div class="audio-muted" style="text-align:right;min-width:150px;">
                                <div><b style="color:#fff;display:block;margin-bottom:4px;">Quick Links</b></div>
                                <a href="posts.php?edit=<?= (int) $r['post_id'] ?>"
                                    style="color:#8ec5ff;text-decoration:none;">Open Post</a>
                            </div>
                        </div>

                        <div class="audio-report-grid">
                            <div class="audio-info-box">
                                <b>Reporter</b>
                                <div><?= hsr($r['reporter_name'] ?? ('User ' . (int) $r['reporter_id'])) ?></div>
                                <div class="audio-muted">ID:
                                    <?= (int) $r['reporter_id'] ?>         <?php if (!empty($r['reporter_username'])): ?> ·
                                        @<?= hsr($r['reporter_username']) ?><?php endif; ?>
                                </div>
                            </div>
                            <div class="audio-info-box">
                                <b>Reel / Post Owner</b>
                                <div><?= hsr($r['owner_name'] ?? ('User ' . (int) ($r['post_user_id'] ?? 0))) ?></div>
                                <div class="audio-muted">ID:
                                    <?= (int) ($r['post_user_id'] ?? 0) ?>         <?php if (!empty($r['owner_username'])): ?> ·
                                        @<?= hsr($r['owner_username']) ?><?php endif; ?>
                                </div>
                            </div>
                            <div class="audio-info-box">
                                <b>Admin Notes</b>
                                <div class="audio-muted">
                                    <?= !empty($r['admin_notes']) ? nl2br(hsr($r['admin_notes'])) : 'No admin notes yet.' ?>
                                </div>
                            </div>
                        </div>

                        <?php if (!empty($r['details']) || !empty($r['post_caption']) || !empty($r['post_file_url'])): ?>
                            <div class="audio-preview">
                                <?php if (!empty($r['details'])): ?>
                                    <div style="margin-bottom:8px;"><b style="color:#fff;display:block;margin-bottom:4px;">Reporter
                                            Details</b><span class="audio-muted"><?= nl2br(hsr($r['details'])) ?></span></div>
                                <?php endif; ?>
                                <?php if (!empty($r['post_caption'])): ?>
                                    <div style="margin-bottom:8px;"><b style="color:#fff;display:block;margin-bottom:4px;">Post
                                            Caption</b><span class="audio-muted"><?= hsr($r['post_caption']) ?></span></div>
                                <?php endif; ?>
                                <?php if (!empty($r['post_file_url'])): ?>
                                    <div>
                                        <b style="color:#fff;display:block;margin-bottom:6px;">Media</b>
                                        <?php
                                        $thumb = $r['post_thumb'] ?? '';
                                        $media = $r['post_file_url'];
                                        $ext = strtolower(pathinfo(parse_url($media, PHP_URL_PATH), PATHINFO_EXTENSION));
                                        $isVideo = in_array($ext, ['mp4', 'mov', 'webm', 'm4v']);
                                        ?>
                                        <?php if ($thumb): ?>
                                            <a href="<?= hsr($media) ?>" target="_blank" rel="noopener">
                                                <img src="<?= hsr($thumb) ?>"
                                                    style="max-width:160px;max-height:100px;border-radius:8px;object-fit:cover;display:block;margin-bottom:6px;"
                                                    onerror="this.style.display='none'">
                                            </a>
                                        <?php elseif ($isVideo): ?>
                                            <video src="<?= hsr($media) ?>"
                                                style="max-width:160px;max-height:100px;border-radius:8px;display:block;margin-bottom:6px;"
                                                muted preload="metadata"></video>
                                        <?php else: ?>
                                            <a href="<?= hsr($media) ?>" target="_blank" rel="noopener">
                                                <img src="<?= hsr($media) ?>"
                                                    style="max-width:160px;max-height:100px;border-radius:8px;object-fit:cover;display:block;margin-bottom:6px;"
                                                    onerror="this.style.display='none'">
                                            </a>
                                        <?php endif; ?>
                                        <a href="<?= hsr($media) ?>" target="_blank" rel="noopener"
                                            style="color:#8ec5ff;font-size:12px;">Open media ↗</a>
                                    </div>
                                <?php endif; ?>
                            </div>
                        <?php endif; ?>

                        <form method="post" class="audio-form">
                            <input type="hidden" name="report_id" value="<?= (int) $r['id'] ?>">
                            <select name="status">
                                <?php foreach (['pending', 'reviewed', 'resolved', 'dismissed'] as $s): ?>
                                    <option value="<?= hsr($s) ?>" <?= ($r['status'] ?? '') === $s ? 'selected' : '' ?>>
                                        <?= ucfirst($s) ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                            <input name="admin_notes" value="<?= hsr($r['admin_notes'] ?? '') ?>"
                                placeholder="Add moderation note or decision summary">
                            <button class="btn ok" type="submit">Save Update</button>
                            <button class="btn warn" type="submit" formaction="?ajax=remove_sound"
                                onclick="return confirm('Remove sound from post #<?= (int) $r['post_id'] ?>? This clears the audio but keeps the post.')">Remove
                                Sound</button>
                            <button class="btn danger" type="submit" formaction="?ajax=delete_post"
                                onclick="return confirm('Permanently DELETE post #<?= (int) $r['post_id'] ?>? This cannot be undone.')">Delete
                                Post</button>
                            <button class="btn danger" type="submit" formaction="?ajax=delete_report"
                                onclick="return confirm('Delete audio report #<?= (int) $r['id'] ?>?')">Delete Report</button>
                        </form>
                    </div>
                <?php endforeach; ?>
            </div>
        <?php endif; ?>
    </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>