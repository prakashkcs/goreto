<?php
session_start();
if (empty($_SESSION['admin_logged_in'])) {
    header('Location: login.php');
    exit;
}
require_once __DIR__ . '/db_connect.php';

$pageTitle = 'Analytics';
$activeNav = 'analytics';
include __DIR__ . '/_layout_header.php';

// ── helpers ──────────────────────────────────────────────────────────────────
function q($pdo, $sql, $params = [])
{
    $st = $pdo->prepare($sql);
    $st->execute($params);
    return $st;
}
function scalar($pdo, $sql, $params = [])
{
    return q($pdo, $sql, $params)->fetchColumn() ?: 0;
}

// ── period filter ─────────────────────────────────────────────────────────────
$period = $_GET['period'] ?? '30';
$days = in_array((int) $period, [7, 14, 30, 60, 90, 365]) ? (int) $period : 30;
$since = date('Y-m-d H:i:s', strtotime("-{$days} days"));

// ── KPI cards ─────────────────────────────────────────────────────────────────
$totalUsers = scalar($pdo, "SELECT COUNT(*) FROM users");
$newUsers = scalar($pdo, "SELECT COUNT(*) FROM users WHERE created_at >= ?", [$since]);
$activeUsers = scalar($pdo, "SELECT COUNT(DISTINCT user_id) FROM posts WHERE created_at >= ?", [$since]);
$totalPosts = scalar($pdo, "SELECT COUNT(*) FROM posts");
$newPosts = scalar($pdo, "SELECT COUNT(*) FROM posts WHERE created_at >= ?", [$since]);
$totalLikes = scalar($pdo, "SELECT COUNT(*) FROM likes");
$totalComments = scalar($pdo, "SELECT COUNT(*) FROM comments");
$totalGiftsSent = scalar($pdo, "SELECT COUNT(*) FROM gift_transactions WHERE created_at >= ?", [$since]);
$totalCoinsSpent = scalar($pdo, "SELECT COALESCE(SUM(coin_amount),0) FROM gift_transactions WHERE created_at >= ?", [$since]);
$kycPending = scalar($pdo, "SELECT COUNT(*) FROM kyc_submissions WHERE status='pending'");
$kycVerified = scalar($pdo, "SELECT COUNT(*) FROM kyc_submissions WHERE status='approved'");
$walletDeposits = scalar($pdo, "SELECT COALESCE(SUM(amount),0) FROM wallet_transactions WHERE type='deposit' AND status='approved' AND created_at >= ?", [$since]);
$walletWithdraws = scalar($pdo, "SELECT COALESCE(SUM(amount),0) FROM wallet_transactions WHERE type='withdraw' AND status='approved' AND created_at >= ?", [$since]);
$activeSubs = scalar($pdo, "SELECT COUNT(*) FROM user_subscriptions WHERE status='active'");
$totalFollows = scalar($pdo, "SELECT COUNT(*) FROM follows WHERE created_at >= ?", [$since]);
$totalMessages = scalar($pdo, "SELECT COUNT(*) FROM messages WHERE created_at >= ?", [$since]);
$liveStreams = scalar($pdo, "SELECT COUNT(*) FROM live_streams WHERE started_at >= ?", [$since]);

// ── daily signups (chart) ─────────────────────────────────────────────────────
$dailySignups = q(
    $pdo,
    "SELECT DATE(created_at) as d, COUNT(*) as n FROM users
     WHERE created_at >= ? GROUP BY DATE(created_at) ORDER BY d",
    [$since]
)->fetchAll(PDO::FETCH_ASSOC);

// ── daily posts (chart) ───────────────────────────────────────────────────────
$dailyPosts = q(
    $pdo,
    "SELECT DATE(created_at) as d, COUNT(*) as n FROM posts
     WHERE created_at >= ? GROUP BY DATE(created_at) ORDER BY d",
    [$since]
)->fetchAll(PDO::FETCH_ASSOC);

// ── top content creators ──────────────────────────────────────────────────────
$topCreators = q(
    $pdo,
    "SELECT u.id, u.name, u.profile_pic,
            COUNT(p.id) as post_count,
            COALESCE(SUM(p.likes_count),0) as total_likes
     FROM users u
     JOIN posts p ON p.user_id = u.id
     WHERE p.created_at >= ?
     GROUP BY u.id ORDER BY post_count DESC LIMIT 10",
    [$since]
)->fetchAll(PDO::FETCH_ASSOC);

// ── top gifted users ──────────────────────────────────────────────────────────
$topGifted = q(
    $pdo,
    "SELECT u.id, u.name, COUNT(gt.id) as gifts_received,
            COALESCE(SUM(gt.coin_amount),0) as coins_received
     FROM users u
     JOIN gift_transactions gt ON gt.to_user_id = u.id
     WHERE gt.created_at >= ?
     GROUP BY u.id ORDER BY coins_received DESC LIMIT 10",
    [$since]
)->fetchAll(PDO::FETCH_ASSOC);

// ── post type breakdown ───────────────────────────────────────────────────────
$postTypes = q(
    $pdo,
    "SELECT type, COUNT(*) as n FROM posts
     WHERE created_at >= ? GROUP BY type ORDER BY n DESC",
    [$since]
)->fetchAll(PDO::FETCH_ASSOC);

// ── gender breakdown ──────────────────────────────────────────────────────────
$genderBreakdown = q(
    $pdo,
    "SELECT gender, COUNT(*) as n FROM users GROUP BY gender"
)->fetchAll(PDO::FETCH_ASSOC);

// ── subscription revenue ──────────────────────────────────────────────────────
$subRevenue = q(
    $pdo,
    "SELECT DATE_FORMAT(created_at,'%Y-%m') as mo,
            COUNT(*) as subs,
            COALESCE(SUM(price),0) as revenue
     FROM user_subscriptions
     WHERE created_at >= ?
     GROUP BY mo ORDER BY mo",
    [$since]
)->fetchAll(PDO::FETCH_ASSOC);

// ── retention: users who posted in last 7 days ────────────────────────────────
$retentionWeek = scalar(
    $pdo,
    "SELECT COUNT(DISTINCT user_id) FROM posts WHERE created_at >= ?",
    [date('Y-m-d H:i:s', strtotime('-7 days'))]
);

// ── encode for JS ─────────────────────────────────────────────────────────────
$jsSignups = json_encode(array_column($dailySignups, 'n'));
$jsSignupLabels = json_encode(array_column($dailySignups, 'd'));
$jsPosts = json_encode(array_column($dailyPosts, 'n'));
$jsPostLabels = json_encode(array_column($dailyPosts, 'd'));
$jsPostTypeLabels = json_encode(array_column($postTypes, 'type'));
$jsPostTypeData = json_encode(array_column($postTypes, 'n'));
$jsGenderLabels = json_encode(array_column($genderBreakdown, 'gender'));
$jsGenderData = json_encode(array_column($genderBreakdown, 'n'));
$jsSubMonths = json_encode(array_column($subRevenue, 'mo'));
$jsSubRevenue = json_encode(array_column($subRevenue, 'revenue'));
?>

<style>
    .analytics-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
        gap: 14px;
        margin-bottom: 28px;
    }

    .kpi {
        background: #1a1a2e;
        border: 1px solid #2a2a4a;
        border-radius: 12px;
        padding: 18px 16px;
    }

    .kpi .val {
        font-size: 2rem;
        font-weight: 700;
        color: #d946ef;
    }

    .kpi .lbl {
        font-size: .78rem;
        color: #aaa;
        margin-top: 4px;
    }

    .kpi .sub {
        font-size: .72rem;
        color: #666;
        margin-top: 2px;
    }

    .charts-row {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 18px;
        margin-bottom: 28px;
    }

    .chart-box {
        background: #1a1a2e;
        border: 1px solid #2a2a4a;
        border-radius: 12px;
        padding: 18px;
    }

    .chart-box h3 {
        margin: 0 0 14px;
        font-size: .9rem;
        color: #ccc;
    }

    .table-box {
        background: #1a1a2e;
        border: 1px solid #2a2a4a;
        border-radius: 12px;
        padding: 18px;
        margin-bottom: 18px;
    }

    .table-box h3 {
        margin: 0 0 12px;
        font-size: .9rem;
        color: #ccc;
    }

    .table-box table {
        width: 100%;
        border-collapse: collapse;
        font-size: .82rem;
    }

    .table-box th {
        color: #888;
        font-weight: 600;
        padding: 6px 8px;
        border-bottom: 1px solid #2a2a4a;
        text-align: left;
    }

    .table-box td {
        padding: 7px 8px;
        border-bottom: 1px solid #1e1e3a;
        color: #ddd;
    }

    .table-box tr:last-child td {
        border-bottom: none;
    }

    .period-bar {
        display: flex;
        gap: 8px;
        margin-bottom: 22px;
        flex-wrap: wrap;
    }

    .period-bar a {
        padding: 6px 14px;
        border-radius: 20px;
        font-size: .8rem;
        background: #1a1a2e;
        border: 1px solid #2a2a4a;
        color: #aaa;
        text-decoration: none;
    }

    .period-bar a.active {
        background: #d946ef22;
        border-color: #d946ef;
        color: #d946ef;
    }

    .two-col {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 18px;
    }

    @media(max-width:700px) {

        .charts-row,
        .two-col {
            grid-template-columns: 1fr;
        }
    }
</style>

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>

<div class="period-bar">
    <?php foreach ([7, 14, 30, 60, 90, 365] as $p): ?>
        <a href="?period=<?= $p ?>" class="<?= $days == $p ? 'active' : '' ?>"><?= $p ?> days</a>
    <?php endforeach; ?>
</div>

<!-- KPI Grid -->
<div class="analytics-grid">
    <div class="kpi">
        <div class="val"><?= number_format($totalUsers) ?></div>
        <div class="lbl">Total Users</div>
        <div class="sub">+<?= number_format($newUsers) ?> in period</div>
    </div>
    <div class="kpi">
        <div class="val"><?= number_format($activeUsers) ?></div>
        <div class="lbl">Active Users</div>
        <div class="sub">Posted in period</div>
    </div>
    <div class="kpi">
        <div class="val"><?= number_format($retentionWeek) ?></div>
        <div class="lbl">7-day Retention</div>
        <div class="sub">Posted last 7 days</div>
    </div>
    <div class="kpi">
        <div class="val"><?= number_format($totalPosts) ?></div>
        <div class="lbl">Total Posts</div>
        <div class="sub">+<?= number_format($newPosts) ?> in period</div>
    </div>
    <div class="kpi">
        <div class="val"><?= number_format($totalLikes) ?></div>
        <div class="lbl">Total Likes</div>
    </div>
    <div class="kpi">
        <div class="val"><?= number_format($totalComments) ?></div>
        <div class="lbl">Total Comments</div>
    </div>
    <div class="kpi">
        <div class="val"><?= number_format($totalFollows) ?></div>
        <div class="lbl">New Follows</div>
        <div class="sub">In period</div>
    </div>
    <div class="kpi">
        <div class="val"><?= number_format($totalMessages) ?></div>
        <div class="lbl">Messages Sent</div>
        <div class="sub">In period</div>
    </div>
    <div class="kpi">
        <div class="val"><?= number_format($liveStreams) ?></div>
        <div class="lbl">Live Streams</div>
        <div class="sub">In period</div>
    </div>
    <div class="kpi">
        <div class="val"><?= number_format($totalGiftsSent) ?></div>
        <div class="lbl">Gifts Sent</div>
        <div class="sub"><?= number_format($totalCoinsSpent) ?> coins</div>
    </div>
    <div class="kpi">
        <div class="val"><?= number_format($walletDeposits, 2) ?></div>
        <div class="lbl">Deposits</div>
        <div class="sub">Approved in period</div>
    </div>
    <div class="kpi">
        <div class="val"><?= number_format($walletWithdraws, 2) ?></div>
        <div class="lbl">Withdrawals</div>
        <div class="sub">Approved in period</div>
    </div>
    <div class="kpi">
        <div class="val"><?= number_format($activeSubs) ?></div>
        <div class="lbl">Active Subs</div>
    </div>
    <div class="kpi">
        <div class="val"><?= number_format($kycVerified) ?></div>
        <div class="lbl">KYC Verified</div>
        <div class="sub"><?= number_format($kycPending) ?> pending</div>
    </div>
</div>

<!-- Charts row 1 -->
<div class="charts-row">
    <div class="chart-box">
        <h3>Daily Signups</h3>
        <canvas id="signupChart" height="120"></canvas>
    </div>
    <div class="chart-box">
        <h3>Daily Posts</h3>
        <canvas id="postsChart" height="120"></canvas>
    </div>
</div>

<!-- Charts row 2 -->
<div class="charts-row">
    <div class="chart-box">
        <h3>Post Type Breakdown</h3>
        <canvas id="postTypeChart" height="140"></canvas>
    </div>
    <div class="chart-box">
        <h3>Gender Breakdown</h3>
        <canvas id="genderChart" height="140"></canvas>
    </div>
</div>

<!-- Subscription Revenue -->
<?php if (!empty($subRevenue)): ?>
    <div class="chart-box" style="margin-bottom:18px">
        <h3>Subscription Revenue by Month</h3>
        <canvas id="subRevenueChart" height="90"></canvas>
    </div>
<?php endif; ?>

<!-- Tables -->
<div class="two-col">
    <div class="table-box">
        <h3>🏆 Top Content Creators (<?= $days ?> days)</h3>
        <table>
            <tr>
                <th>#</th>
                <th>Name</th>
                <th>Posts</th>
                <th>Likes</th>
            </tr>
            <?php foreach ($topCreators as $i => $r): ?>
                <tr>
                    <td><?= $i + 1 ?></td>
                    <td><?= htmlspecialchars($r['name']) ?></td>
                    <td><?= number_format($r['post_count']) ?></td>
                    <td><?= number_format($r['total_likes']) ?></td>
                </tr>
            <?php endforeach; ?>
            <?php if (empty($topCreators)): ?>
                <tr>
                    <td colspan="4" style="color:#555;text-align:center">No data</td>
                </tr><?php endif; ?>
        </table>
    </div>

    <div class="table-box">
        <h3>🎁 Top Gifted Users (<?= $days ?> days)</h3>
        <table>
            <tr>
                <th>#</th>
                <th>Name</th>
                <th>Gifts</th>
                <th>Coins</th>
            </tr>
            <?php foreach ($topGifted as $i => $r): ?>
                <tr>
                    <td><?= $i + 1 ?></td>
                    <td><?= htmlspecialchars($r['name']) ?></td>
                    <td><?= number_format($r['gifts_received']) ?></td>
                    <td><?= number_format($r['coins_received']) ?></td>
                </tr>
            <?php endforeach; ?>
            <?php if (empty($topGifted)): ?>
                <tr>
                    <td colspan="4" style="color:#555;text-align:center">No data</td>
                </tr><?php endif; ?>
        </table>
    </div>
</div>

<script>
    const chartDefaults = {
        responsive: true,
        plugins: { legend: { labels: { color: '#ccc', font: { size: 11 } } } },
        scales: {
            x: { ticks: { color: '#888', font: { size: 10 } }, grid: { color: '#2a2a4a' } },
            y: { ticks: { color: '#888', font: { size: 10 } }, grid: { color: '#2a2a4a' }, beginAtZero: true }
        }
    };

    new Chart(document.getElementById('signupChart'), {
        type: 'line',
        data: {
            labels: <?= $jsSignupLabels ?>, datasets: [{
                label: 'Signups', data: <?= $jsSignups ?>,
                borderColor: '#d946ef', backgroundColor: '#d946ef22', tension: .4, fill: true, pointRadius: 2
            }]
        },
        options: chartDefaults
    });

    new Chart(document.getElementById('postsChart'), {
        type: 'bar',
        data: {
            labels: <?= $jsPostLabels ?>, datasets: [{
                label: 'Posts', data: <?= $jsPosts ?>,
                backgroundColor: '#06b6d4aa', borderColor: '#06b6d4', borderWidth: 1
            }]
        },
        options: chartDefaults
    });

    new Chart(document.getElementById('postTypeChart'), {
        type: 'doughnut',
        data: {
            labels: <?= $jsPostTypeLabels ?>, datasets: [{
                data: <?= $jsPostTypeData ?>,
                backgroundColor: ['#d946ef', '#06b6d4', '#f97316', '#22c55e', '#eab308', '#ef4444']
            }]
        },
        options: { responsive: true, plugins: { legend: { labels: { color: '#ccc', font: { size: 11 } } } } }
    });

    new Chart(document.getElementById('genderChart'), {
        type: 'pie',
        data: {
            labels: <?= $jsGenderLabels ?>, datasets: [{
                data: <?= $jsGenderData ?>,
                backgroundColor: ['#d946ef', '#06b6d4', '#f97316', '#22c55e']
            }]
        },
        options: { responsive: true, plugins: { legend: { labels: { color: '#ccc', font: { size: 11 } } } } }
    });

    <?php if (!empty($subRevenue)): ?>
        new Chart(document.getElementById('subRevenueChart'), {
            type: 'bar',
            data: {
                labels: <?= $jsSubMonths ?>, datasets: [{
                    label: 'Revenue', data: <?= $jsSubRevenue ?>,
                    backgroundColor: '#22c55eaa', borderColor: '#22c55e', borderWidth: 1
                }]
            },
            options: chartDefaults
        });
    <?php endif; ?>
</script>

<?php include __DIR__ . '/_layout_footer.php'; ?>