<?php
/**
 * Admin Reports Management Page
 * Lists user reports with filtering and status management
 */
require_once __DIR__ . '/_core.php';
admin_require_login();

// Handle AJAX actions
if (isset($_GET['ajax'])) {
    header('Content-Type: application/json');
    
    if ($_GET['ajax'] === 'update_status') {
        $reportId = (int)($_POST['report_id'] ?? 0);
        $newStatus = $_POST['status'] ?? '';
        $adminNotes = trim($_POST['admin_notes'] ?? '');
        
        if (!$reportId || !in_array($newStatus, ['pending','reviewed','resolved','dismissed'])) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid parameters']);
            exit;
        }
        
        $stmt = $pdo->prepare("UPDATE user_reports SET status = ?, admin_notes = ?, updated_at = NOW() WHERE id = ?");
        $stmt->execute([$newStatus, $adminNotes, $reportId]);
        echo json_encode(['status' => 'success', 'message' => 'Report updated']);
        exit;
    }
    
    if ($_GET['ajax'] === 'delete_report') {
        $reportId = (int)($_POST['report_id'] ?? 0);
        if (!$reportId) {
            echo json_encode(['status' => 'error', 'message' => 'Invalid report ID']);
            exit;
        }
        $pdo->prepare("DELETE FROM user_reports WHERE id = ?")->execute([$reportId]);
        echo json_encode(['status' => 'success', 'message' => 'Report deleted']);
        exit;
    }
    exit;
}

// Ensure table exists
try {
    $pdo->exec("CREATE TABLE IF NOT EXISTS user_reports (
        id INT AUTO_INCREMENT PRIMARY KEY,
        reporter_id INT NOT NULL,
        reported_id INT NOT NULL,
        reason VARCHAR(100) NOT NULL,
        details TEXT,
        status ENUM('pending','reviewed','resolved','dismissed') DEFAULT 'pending',
        admin_notes TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX (reporter_id),
        INDEX (reported_id),
        INDEX (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;");
} catch(PDOException $e) {}

// Filter
$statusFilter = $_GET['status'] ?? 'all';
$where = '';
$params = [];
if ($statusFilter !== 'all' && in_array($statusFilter, ['pending','reviewed','resolved','dismissed'])) {
    $where = 'WHERE r.status = ?';
    $params[] = $statusFilter;
}

// Fetch reports
$sql = "SELECT r.*, 
        reporter.name as reporter_name, reporter.email as reporter_email,
        reported.name as reported_name, reported.email as reported_email
        FROM user_reports r
        LEFT JOIN users reporter ON reporter.id = r.reporter_id
        LEFT JOIN users reported ON reported.id = r.reported_id
        $where
        ORDER BY r.created_at DESC
        LIMIT 200";
$stmt = $pdo->prepare($sql);
$stmt->execute($params);
$reports = $stmt->fetchAll(PDO::FETCH_ASSOC);

// Count by status
$countSt = $pdo->query("SELECT status, COUNT(*) as cnt FROM user_reports GROUP BY status");
$counts = [];
$totalCount = 0;
while ($row = $countSt->fetch(PDO::FETCH_ASSOC)) {
    $counts[$row['status']] = (int)$row['cnt'];
    $totalCount += (int)$row['cnt'];
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>User Reports - Admin Panel</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
    <style>
        body { background: #0a0a0f; color: #e0e0e0; font-family: 'Segoe UI', sans-serif; }
        .sidebar { background: #111118; min-height: 100vh; padding: 20px; border-right: 1px solid #222; }
        .sidebar a { color: #aaa; text-decoration: none; display: block; padding: 10px 15px; border-radius: 8px; margin-bottom: 5px; }
        .sidebar a:hover, .sidebar a.active { background: #1a1a2e; color: #ff007f; }
        .card-stat { background: #1a1a2e; border: 1px solid #333; border-radius: 12px; padding: 20px; text-align: center; }
        .card-stat .count { font-size: 2rem; font-weight: bold; }
        .card-stat.pending .count { color: #fbbf24; }
        .card-stat.reviewed .count { color: #60a5fa; }
        .card-stat.resolved .count { color: #34d399; }
        .card-stat.dismissed .count { color: #f87171; }
        .table-dark-custom { background: #111118; border-radius: 12px; overflow: hidden; }
        .table-dark-custom th { background: #1a1a2e; color: #ff007f; border-bottom: 2px solid #333; padding: 12px; }
        .table-dark-custom td { padding: 12px; border-bottom: 1px solid #222; vertical-align: middle; }
        .badge-pending { background: #fbbf24; color: #000; }
        .badge-reviewed { background: #60a5fa; color: #000; }
        .badge-resolved { background: #34d399; color: #000; }
        .badge-dismissed { background: #f87171; color: #fff; }
        .btn-action { border: none; padding: 5px 12px; border-radius: 6px; font-size: 12px; cursor: pointer; margin: 2px; }
        .filter-tab { display: inline-block; padding: 8px 16px; border-radius: 20px; margin: 0 5px 10px 0; text-decoration: none; color: #aaa; background: #1a1a2e; border: 1px solid #333; }
        .filter-tab:hover, .filter-tab.active { background: #ff007f; color: #fff; border-color: #ff007f; }
        .modal-content { background: #1a1a2e; border: 1px solid #333; color: #e0e0e0; }
        .modal-header { border-bottom: 1px solid #333; }
        .modal-footer { border-top: 1px solid #333; }
        .form-control, .form-select { background: #0a0a0f; border: 1px solid #333; color: #e0e0e0; }
        .form-control:focus, .form-select:focus { background: #0a0a0f; border-color: #ff007f; color: #e0e0e0; box-shadow: 0 0 0 0.2rem rgba(255,0,127,0.25); }
    </style>
</head>
<body>
<div class="container-fluid">
    <div class="row">
        <!-- Sidebar -->
        <div class="col-md-2 sidebar">
            <h4 class="text-white mb-4"><i class="fas fa-shield-halved"></i> Admin</h4>
            <a href="dashboard.php" class="mb-3 text-info"><i class="fas fa-arrow-left me-2"></i>Back to Dashboard</a>
            <hr class="border-secondary">
            <a href="users.php"><i class="fas fa-users me-2"></i>Users</a>
            <a href="kyc_review.php"><i class="fas fa-id-card me-2"></i>KYC Review</a>
            <a href="income_review.php"><i class="fas fa-money-bill me-2"></i>Income Review</a>
            <a href="wallet_requests.php"><i class="fas fa-wallet me-2"></i>Wallet</a>
            <a href="reports.php" class="active"><i class="fas fa-flag me-2"></i>Reports</a>
        </div>

        <!-- Main Content -->
        <div class="col-md-10 p-4">
            <h2 class="mb-4"><i class="fas fa-flag text-danger"></i> User Reports</h2>

            <!-- Stats -->
            <div class="row mb-4">
                <div class="col-md-3">
                    <div class="card-stat">
                        <div class="count" style="color:#e0e0e0"><?= $totalCount ?></div>
                        <div>Total Reports</div>
                    </div>
                </div>
                <div class="col-md-2">
                    <div class="card-stat pending">
                        <div class="count"><?= $counts['pending'] ?? 0 ?></div>
                        <div>Pending</div>
                    </div>
                </div>
                <div class="col-md-2">
                    <div class="card-stat reviewed">
                        <div class="count"><?= $counts['reviewed'] ?? 0 ?></div>
                        <div>Reviewed</div>
                    </div>
                </div>
                <div class="col-md-2">
                    <div class="card-stat resolved">
                        <div class="count"><?= $counts['resolved'] ?? 0 ?></div>
                        <div>Resolved</div>
                    </div>
                </div>
                <div class="col-md-3">
                    <div class="card-stat dismissed">
                        <div class="count"><?= $counts['dismissed'] ?? 0 ?></div>
                        <div>Dismissed</div>
                    </div>
                </div>
            </div>

            <!-- Filters -->
            <div class="mb-3">
                <a href="?status=all" class="filter-tab <?= $statusFilter === 'all' ? 'active' : '' ?>">All</a>
                <a href="?status=pending" class="filter-tab <?= $statusFilter === 'pending' ? 'active' : '' ?>">🟡 Pending</a>
                <a href="?status=reviewed" class="filter-tab <?= $statusFilter === 'reviewed' ? 'active' : '' ?>">🔵 Reviewed</a>
                <a href="?status=resolved" class="filter-tab <?= $statusFilter === 'resolved' ? 'active' : '' ?>">🟢 Resolved</a>
                <a href="?status=dismissed" class="filter-tab <?= $statusFilter === 'dismissed' ? 'active' : '' ?>">🔴 Dismissed</a>
            </div>

            <!-- Reports Table -->
            <?php if (empty($reports)): ?>
                <div class="text-center py-5">
                    <i class="fas fa-check-circle fa-3x text-success mb-3"></i>
                    <h4>No reports found</h4>
                    <p class="text-muted">There are no reports matching the selected filter.</p>
                </div>
            <?php else: ?>
                <div class="table-dark-custom">
                    <table class="table table-borderless mb-0">
                        <thead>
                            <tr>
                                <th>#</th>
                                <th>Reporter</th>
                                <th>Reported User</th>
                                <th>Reason</th>
                                <th>Details</th>
                                <th>Status</th>
                                <th>Date</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($reports as $r): ?>
                            <tr id="report-row-<?= $r['id'] ?>">
                                <td><?= $r['id'] ?></td>
                                <td>
                                    <strong><?= htmlspecialchars($r['reporter_name'] ?? 'Unknown') ?></strong>
                                    <br><small class="text-muted">#<?= $r['reporter_id'] ?></small>
                                </td>
                                <td>
                                    <strong><?= htmlspecialchars($r['reported_name'] ?? 'Unknown') ?></strong>
                                    <br><small class="text-muted">#<?= $r['reported_id'] ?></small>
                                </td>
                                <td><span class="badge bg-secondary"><?= htmlspecialchars($r['reason']) ?></span></td>
                                <td>
                                    <small><?= htmlspecialchars(mb_substr($r['details'] ?? '-', 0, 100)) ?></small>
                                    <?php if ($r['admin_notes']): ?>
                                        <br><small class="text-warning"><i class="fas fa-sticky-note"></i> <?= htmlspecialchars(mb_substr($r['admin_notes'], 0, 60)) ?></small>
                                    <?php endif; ?>
                                </td>
                                <td><span class="badge badge-<?= $r['status'] ?>"><?= ucfirst($r['status']) ?></span></td>
                                <td><small><?= date('M d, Y H:i', strtotime($r['created_at'])) ?></small></td>
                                <td>
                                    <button class="btn-action btn btn-sm btn-outline-primary" onclick="openEditModal(<?= htmlspecialchars(json_encode($r)) ?>)">
                                        <i class="fas fa-pen"></i>
                                    </button>
                                    <button class="btn-action btn btn-sm btn-outline-danger" onclick="deleteReport(<?= $r['id'] ?>)">
                                        <i class="fas fa-trash"></i>
                                    </button>
                                </td>
                            </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            <?php endif; ?>
        </div>
    </div>
</div>

<!-- Edit Modal -->
<div class="modal fade" id="editModal" tabindex="-1">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title"><i class="fas fa-edit"></i> Update Report</h5>
                <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body">
                <input type="hidden" id="edit-report-id">
                <div class="mb-3">
                    <label class="form-label">Reporter</label>
                    <input type="text" class="form-control" id="edit-reporter" readonly>
                </div>
                <div class="mb-3">
                    <label class="form-label">Reported User</label>
                    <input type="text" class="form-control" id="edit-reported" readonly>
                </div>
                <div class="mb-3">
                    <label class="form-label">Reason</label>
                    <input type="text" class="form-control" id="edit-reason" readonly>
                </div>
                <div class="mb-3">
                    <label class="form-label">Details</label>
                    <textarea class="form-control" id="edit-details" rows="3" readonly></textarea>
                </div>
                <div class="mb-3">
                    <label class="form-label">Status</label>
                    <select class="form-select" id="edit-status">
                        <option value="pending">Pending</option>
                        <option value="reviewed">Reviewed</option>
                        <option value="resolved">Resolved</option>
                        <option value="dismissed">Dismissed</option>
                    </select>
                </div>
                <div class="mb-3">
                    <label class="form-label">Admin Notes</label>
                    <textarea class="form-control" id="edit-admin-notes" rows="3" placeholder="Add admin notes..."></textarea>
                </div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
                <button type="button" class="btn btn-primary" onclick="saveReport()" style="background:#ff007f;border-color:#ff007f">Save Changes</button>
            </div>
        </div>
    </div>
</div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<script>
function openEditModal(report) {
    document.getElementById('edit-report-id').value = report.id;
    document.getElementById('edit-reporter').value = (report.reporter_name || 'Unknown') + ' (#' + report.reporter_id + ')';
    document.getElementById('edit-reported').value = (report.reported_name || 'Unknown') + ' (#' + report.reported_id + ')';
    document.getElementById('edit-reason').value = report.reason;
    document.getElementById('edit-details').value = report.details || '';
    document.getElementById('edit-status').value = report.status;
    document.getElementById('edit-admin-notes').value = report.admin_notes || '';
    new bootstrap.Modal(document.getElementById('editModal')).show();
}

function saveReport() {
    const id = document.getElementById('edit-report-id').value;
    const status = document.getElementById('edit-status').value;
    const notes = document.getElementById('edit-admin-notes').value;

    fetch('reports.php?ajax=update_status', {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: `report_id=${id}&status=${status}&admin_notes=${encodeURIComponent(notes)}`
    })
    .then(r => r.json())
    .then(data => {
        if (data.status === 'success') {
            location.reload();
        } else {
            alert(data.message);
        }
    });
}

function deleteReport(id) {
    if (!confirm('Are you sure you want to delete this report?')) return;
    
    fetch('reports.php?ajax=delete_report', {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: `report_id=${id}`
    })
    .then(r => r.json())
    .then(data => {
        if (data.status === 'success') {
            document.getElementById('report-row-' + id).remove();
        } else {
            alert(data.message);
        }
    });
}
</script>
</body>
</html>
