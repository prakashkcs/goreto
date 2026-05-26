<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Deep Analytics';
$activeNav = 'user_analytics';

/* ─────────────────────────────────────────────────────────────────────────────
   Helper: safe query
   $mode  'col'  → fetchColumn() scalar (default)
          'all'  → fetchAll() array of rows
          'row'  → fetch() single row
   Returns 0 / [] on any Throwable.
───────────────────────────────────────────────────────────────────────────── */
function sa(PDO $pdo, string $q, array $b = [], string $mode = 'col'): mixed
{
    try {
        $st = $pdo->prepare($q);
        $st->execute($b);
        if ($mode === 'all') return $st->fetchAll();
        if ($mode === 'row') return $st->fetch() ?: [];
        return $st->fetchColumn() ?: 0;
    } catch (Throwable $_) {
        return match ($mode) { 'all' => [], 'row' => [], default => 0 };
    }
}

/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 1 — User Growth
═══════════════════════════════════════════════════════════════════════════ */
$signupsToday = (int) sa($pdo, "SELECT COUNT(*) FROM users WHERE DATE(created_at) = CURDATE()");
$signupsWeek  = (int) sa($pdo, "SELECT COUNT(*) FROM users WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)");
$signupsMonth = (int) sa($pdo, "SELECT COUNT(*) FROM users WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)");
$totalUsers   = (int) sa($pdo, "SELECT COUNT(*) FROM users");

$growthRows = sa($pdo, "
    SELECT DATE(created_at) AS d, COUNT(*) AS c
    FROM users
    WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
    GROUP BY DATE(created_at)
    ORDER BY d ASC
", [], 'all');

$growthMap    = [];
foreach ($growthRows as $r) $growthMap[$r['d']] = (int)$r['c'];
$growthLabels = [];
$growthData   = [];
for ($i = 29; $i >= 0; $i--) {
    $date           = date('Y-m-d', strtotime("-{$i} days"));
    $growthLabels[] = date('M j', strtotime($date));
    $growthData[]   = $growthMap[$date] ?? 0;
}

/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 2 — User Breakdown
═══════════════════════════════════════════════════════════════════════════ */
$genderRows = sa($pdo, "
    SELECT COALESCE(NULLIF(TRIM(gender), ''), 'Unknown') AS g, COUNT(*) AS c
    FROM users GROUP BY g ORDER BY c DESC
", [], 'all');

$subStatusRows = sa($pdo, "
    SELECT COALESCE(NULLIF(subscription_status, ''), 'none') AS s, COUNT(*) AS c
    FROM users GROUP BY s ORDER BY c DESC
", [], 'all');

$kycStatusRows = sa($pdo, "
    SELECT COALESCE(NULLIF(kyc_status, ''), 'none') AS s, COUNT(*) AS c
    FROM users GROUP BY s ORDER BY c DESC
", [], 'all');

$bannedCount = (int) sa($pdo, "SELECT COUNT(*) FROM users WHERE is_banned = 1");

/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 3 — Content Stats
═══════════════════════════════════════════════════════════════════════════ */
$totalPosts  = (int) sa($pdo, "SELECT COUNT(*) FROM posts");
$postsMonth  = (int) sa($pdo, "SELECT COUNT(*) FROM posts WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)");
$photoCount  = (int) sa($pdo, "SELECT COUNT(*) FROM posts WHERE type = 'photo'");
$videoCount  = (int) sa($pdo, "SELECT COUNT(*) FROM posts WHERE type = 'video'");

$postDailyRows = sa($pdo, "
    SELECT DATE(created_at) AS d, COUNT(*) AS c
    FROM posts
    WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
    GROUP BY DATE(created_at)
    ORDER BY d ASC
", [], 'all');
$postMap = [];
foreach ($postDailyRows as $r) $postMap[$r['d']] = (int)$r['c'];
$postDailyData = [];
for ($i = 29; $i >= 0; $i--) {
    $date            = date('Y-m-d', strtotime("-{$i} days"));
    $postDailyData[] = $postMap[$date] ?? 0;
}

$topViewedPosts = sa($pdo, "
    SELECT p.id, u.username, u.name, p.type, p.view_count, p.like_count, p.created_at
    FROM posts p
    LEFT JOIN users u ON u.id = p.user_id
    ORDER BY p.view_count DESC
    LIMIT 10
", [], 'all');

/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 4 — Engagement
═══════════════════════════════════════════════════════════════════════════ */
$totalFollows   = (int) sa($pdo, "SELECT COUNT(*) FROM follows");
$totalLikes     = (int) sa($pdo, "SELECT COUNT(*) FROM likes");
$totalComments  = (int) sa($pdo, "SELECT COUNT(*) FROM comments");
$totalPostViews = (int) sa($pdo, "SELECT COALESCE(SUM(view_count), 0) FROM posts");

$engRows = sa($pdo, "
    SELECT d, SUM(lk) AS lk, SUM(cm) AS cm FROM (
        SELECT DATE(created_at) AS d, COUNT(*) AS lk, 0 AS cm
        FROM likes
        WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 14 DAY)
        GROUP BY DATE(created_at)
        UNION ALL
        SELECT DATE(created_at) AS d, 0 AS lk, COUNT(*) AS cm
        FROM comments
        WHERE created_at >= DATE_SUB(CURDATE(), INTERVAL 14 DAY)
        GROUP BY DATE(created_at)
    ) t
    GROUP BY d ORDER BY d ASC
", [], 'all');
$engMap = [];
foreach ($engRows as $r) $engMap[$r['d']] = ['lk' => (int)$r['lk'], 'cm' => (int)$r['cm']];
$engLabels = [];
$engLikes  = [];
$engCmts   = [];
for ($i = 13; $i >= 0; $i--) {
    $date        = date('Y-m-d', strtotime("-{$i} days"));
    $engLabels[] = date('M j', strtotime($date));
    $engLikes[]  = $engMap[$date]['lk'] ?? 0;
    $engCmts[]   = $engMap[$date]['cm'] ?? 0;
}

/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 5 — Wallet & Revenue
═══════════════════════════════════════════════════════════════════════════ */
$totalCoins   = (int) sa($pdo, "SELECT COALESCE(SUM(balance_coins + locked_coins), 0) FROM user_wallets");
$totalBalance = (int) sa($pdo, "SELECT COALESCE(SUM(balance_coins), 0) FROM user_wallets");
$subRevenue   = (int) sa($pdo, "
    SELECT COALESCE(SUM(coins), 0) FROM wallet_transactions
    WHERE type = 'subscription' AND direction = 'credit' AND status = 'approved'
");

$topEarners = sa($pdo, "
    SELECT u.name, u.username,
           w.balance_coins, w.locked_coins,
           (w.balance_coins + w.locked_coins) AS total_coins
    FROM user_wallets w
    LEFT JOIN users u ON u.id = w.user_id
    ORDER BY total_coins DESC
    LIMIT 10
", [], 'all');

$txTypeRows = sa($pdo, "
    SELECT type, direction, COUNT(*) AS c,
           COALESCE(SUM(coins), 0) AS total_coins
    FROM wallet_transactions
    GROUP BY type, direction
    ORDER BY c DESC
", [], 'all');

/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 6 — Top Creators (combined table)
═══════════════════════════════════════════════════════════════════════════ */
$topCreators = sa($pdo, "
    SELECT
        u.id, u.name, u.username,
        u.created_at                   AS joined,
        COUNT(DISTINCT p.id)           AS post_count,
        COUNT(DISTINCT f.id)           AS follower_count,
        COALESCE(w.balance_coins, 0)   AS balance_coins
    FROM users u
    LEFT JOIN posts p        ON p.user_id      = u.id
    LEFT JOIN follows f      ON f.following_id = u.id
    LEFT JOIN user_wallets w ON w.user_id      = u.id
    GROUP BY u.id
    ORDER BY (COUNT(DISTINCT p.id) + COUNT(DISTINCT f.id)) DESC
    LIMIT 15
", [], 'all');

/* ═══════════════════════════════════════════════════════════════════════════
   SECTION 7 — Platform Activity Heatmap (signups by hour of day)
═══════════════════════════════════════════════════════════════════════════ */
$hourRows = sa($pdo, "
    SELECT HOUR(created_at) AS h, COUNT(*) AS c
    FROM users
    GROUP BY HOUR(created_at)
    ORDER BY h ASC
", [], 'all');
$hourMap = array_fill(0, 24, 0);
foreach ($hourRows as $r) $hourMap[(int)$r['h']] = (int)$r['c'];
$maxHour = max($hourMap) ?: 1;

/* ── formatting helpers ──────────────────────────────────────────────────── */
function fmt(int|float $n): string { return number_format((int)$n); }
function pct(int|float $part, int|float $total): string {
    if ($total <= 0) return '0%';
    return round($part / $total * 100, 1) . '%';
}

require __DIR__ . '/_layout_header.php';
?>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js"></script>
<style>
/* ── Section cards ──────────────────────────────────────────────────────── */
.ua-section {
    margin-bottom: 28px;
    background: rgba(15,27,51,.5);
    border: 1px solid #223a66;
    border-radius: 14px;
    overflow: hidden;
}
.ua-head {
    padding: 15px 22px;
    border-bottom: 1px solid #223a66;
    display: flex;
    align-items: center;
    gap: 10px;
}
.ua-head h2 {
    margin: 0;
    font-size: 15px;
    font-weight: 700;
    color: #fff;
}
.ua-badge {
    background: linear-gradient(135deg, #FF007F, #D946EF);
    color: #fff;
    font-size: 11px;
    font-weight: 800;
    border-radius: 999px;
    padding: 2px 10px;
    flex-shrink: 0;
}
.ua-body { padding: 20px 22px; }

/* ── KPI grid ───────────────────────────────────────────────────────────── */
.kpi-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
    gap: 14px;
    margin-bottom: 22px;
}
.kpi-card {
    background: rgba(255,255,255,.03);
    border: 1px solid #223a66;
    border-radius: 10px;
    padding: 16px 14px;
    text-align: center;
}
.kpi-card .kv {
    font-size: 26px;
    font-weight: 900;
    background: linear-gradient(135deg, #FF007F, #D946EF);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
}
.kpi-card .kl {
    font-size: 11px;
    color: rgba(255,255,255,.5);
    margin-top: 4px;
    line-height: 1.3;
}

/* ── Two-column layout ──────────────────────────────────────────────────── */
.ua-two-col {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 20px;
}
@media (max-width: 720px) { .ua-two-col { grid-template-columns: 1fr; } }

/* ── Sub-headings inside body ───────────────────────────────────────────── */
.ua-sub {
    font-size: 11px;
    font-weight: 700;
    color: rgba(255,255,255,.4);
    text-transform: uppercase;
    letter-spacing: .07em;
    margin: 18px 0 10px;
}
.ua-sub:first-child { margin-top: 0; }

/* ── Breakdown list ─────────────────────────────────────────────────────── */
.bk-list { list-style: none; padding: 0; margin: 0; }
.bk-list li {
    display: flex;
    align-items: center;
    gap: 9px;
    padding: 7px 0;
    border-bottom: 1px solid rgba(34,58,102,.45);
    font-size: 13px;
}
.bk-list li:last-child { border-bottom: none; }
.bk-dot   { width: 9px; height: 9px; border-radius: 50%; flex-shrink: 0; }
.bk-label { flex: 1; color: rgba(255,255,255,.7); }
.bk-val   { font-weight: 700; color: #fff; min-width: 40px; text-align: right; }
.bk-pct   { font-size: 11px; color: rgba(255,255,255,.35); min-width: 36px; text-align: right; }

/* ── Data tables ────────────────────────────────────────────────────────── */
.ua-tbl-wrap { overflow-x: auto; }
.ua-tbl { width: 100%; border-collapse: collapse; font-size: 13px; }
.ua-tbl th {
    padding: 8px 12px;
    text-align: left;
    color: rgba(255,255,255,.4);
    font-weight: 600;
    font-size: 11px;
    border-bottom: 1px solid #223a66;
    white-space: nowrap;
}
.ua-tbl td {
    padding: 8px 12px;
    border-bottom: 1px solid rgba(34,58,102,.35);
    color: rgba(255,255,255,.82);
    vertical-align: middle;
}
.ua-tbl tr:last-child td { border-bottom: none; }
.ua-tbl tr:hover td { background: rgba(255,255,255,.022); }
.ua-rank { color: rgba(255,255,255,.28); font-size: 12px; }
.ua-user-name { font-weight: 600; }
.ua-username  { color: rgba(255,0,127,.75); font-size: 11px; }
.ua-pill {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 999px;
    font-size: 10px;
    font-weight: 700;
}
.pill-photo { background: rgba(217,70,239,.15); color: #D946EF; }
.pill-video { background: rgba(255,0,127,.15);  color: #FF007F; }

/* ── Heatmap ────────────────────────────────────────────────────────────── */
.hour-grid {
    display: grid;
    grid-template-columns: repeat(24, 1fr);
    gap: 3px;
    align-items: flex-end;
    height: 80px;
}
.hour-bar-wrap {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: flex-end;
    height: 100%;
}
.hour-bar-fill {
    width: 100%;
    border-radius: 3px 3px 0 0;
    min-height: 3px;
    transition: opacity .15s;
}
.hour-bar-fill:hover { opacity: .65; cursor: default; }
.hour-label {
    font-size: 8px;
    color: rgba(255,255,255,.28);
    margin-top: 4px;
    writing-mode: vertical-lr;
    transform: rotate(180deg);
    user-select: none;
}
</style>

<?php /* ===================================================================
   SECTION 1 — USER GROWTH
=================================================================== */ ?>
<div class="ua-section">
    <div class="ua-head">
        <h2>User Growth</h2>
        <span class="ua-badge">Last 30 Days</span>
    </div>
    <div class="ua-body">
        <div class="kpi-grid">
            <div class="kpi-card"><div class="kv"><?= fmt($signupsToday) ?></div><div class="kl">Signups Today</div></div>
            <div class="kpi-card"><div class="kv"><?= fmt($signupsWeek)  ?></div><div class="kl">This Week</div></div>
            <div class="kpi-card"><div class="kv"><?= fmt($signupsMonth) ?></div><div class="kl">This Month</div></div>
            <div class="kpi-card"><div class="kv"><?= fmt($totalUsers)   ?></div><div class="kl">Total Users</div></div>
        </div>
        <div style="position:relative;height:180px">
            <canvas id="chartGrowth"></canvas>
        </div>
    </div>
</div>

<?php /* ===================================================================
   SECTION 2 — USER BREAKDOWN
=================================================================== */ ?>
<div class="ua-section">
    <div class="ua-head"><h2>User Breakdown</h2></div>
    <div class="ua-body">
        <div class="ua-two-col">
            <div>
                <div class="ua-sub">Gender Distribution</div>
                <?php $gc = ['#FF007F','#D946EF','#7c3aed','#3b82f6','#22d3ee','#34d399','#fbbf24']; $gi = 0; ?>
                <ul class="bk-list">
                    <?php foreach ($genderRows as $r): ?>
                    <li>
                        <span class="bk-dot" style="background:<?= $gc[$gi % count($gc)] ?>"></span>
                        <span class="bk-label"><?= htmlspecialchars(ucfirst($r['g'])) ?></span>
                        <span class="bk-val"><?= fmt((int)$r['c']) ?></span>
                        <span class="bk-pct"><?= pct((int)$r['c'], $totalUsers) ?></span>
                    </li>
                    <?php $gi++; endforeach; ?>
                    <li>
                        <span class="bk-dot" style="background:#ef4444"></span>
                        <span class="bk-label">Banned</span>
                        <span class="bk-val"><?= fmt($bannedCount) ?></span>
                        <span class="bk-pct"><?= pct($bannedCount, $totalUsers) ?></span>
                    </li>
                </ul>
            </div>
            <div>
                <div class="ua-sub">Subscription Status</div>
                <?php $sc = ['#FF007F','#D946EF','#7c3aed','#3b82f6','#22d3ee','#34d399','#fbbf24']; $si = 0; ?>
                <ul class="bk-list">
                    <?php foreach ($subStatusRows as $r): ?>
                    <li>
                        <span class="bk-dot" style="background:<?= $sc[$si % count($sc)] ?>"></span>
                        <span class="bk-label"><?= htmlspecialchars(ucfirst((string)$r['s'])) ?></span>
                        <span class="bk-val"><?= fmt((int)$r['c']) ?></span>
                        <span class="bk-pct"><?= pct((int)$r['c'], $totalUsers) ?></span>
                    </li>
                    <?php $si++; endforeach; ?>
                </ul>

                <div class="ua-sub" style="margin-top:18px">KYC Status</div>
                <?php $kc = ['#34d399','#fbbf24','#ef4444','#7c3aed','#3b82f6']; $ki = 0; ?>
                <ul class="bk-list">
                    <?php foreach ($kycStatusRows as $r): ?>
                    <li>
                        <span class="bk-dot" style="background:<?= $kc[$ki % count($kc)] ?>"></span>
                        <span class="bk-label"><?= htmlspecialchars(ucfirst((string)$r['s'])) ?></span>
                        <span class="bk-val"><?= fmt((int)$r['c']) ?></span>
                        <span class="bk-pct"><?= pct((int)$r['c'], $totalUsers) ?></span>
                    </li>
                    <?php $ki++; endforeach; ?>
                </ul>
            </div>
        </div>
    </div>
</div>

<?php /* ===================================================================
   SECTION 3 — CONTENT STATS
=================================================================== */ ?>
<div class="ua-section">
    <div class="ua-head">
        <h2>Content Stats</h2>
        <span class="ua-badge">Posts</span>
    </div>
    <div class="ua-body">
        <div class="kpi-grid">
            <div class="kpi-card"><div class="kv"><?= fmt($totalPosts)  ?></div><div class="kl">Total Posts</div></div>
            <div class="kpi-card"><div class="kv"><?= fmt($postsMonth)  ?></div><div class="kl">Posts This Month</div></div>
            <div class="kpi-card"><div class="kv"><?= fmt($photoCount)  ?></div><div class="kl">Photo Posts</div></div>
            <div class="kpi-card"><div class="kv"><?= fmt($videoCount)  ?></div><div class="kl">Video Posts</div></div>
        </div>
        <div style="position:relative;height:160px;margin-bottom:24px">
            <canvas id="chartPosts"></canvas>
        </div>
        <div class="ua-sub">Top 10 Most Viewed Posts</div>
        <div class="ua-tbl-wrap">
            <table class="ua-tbl">
                <thead>
                    <tr><th>#</th><th>Creator</th><th>Type</th><th>Views</th><th>Likes</th><th>Created</th></tr>
                </thead>
                <tbody>
                    <?php foreach ($topViewedPosts as $i => $p): ?>
                    <tr>
                        <td class="ua-rank"><?= $i + 1 ?></td>
                        <td>
                            <div class="ua-user-name"><?= htmlspecialchars($p['name'] ?? '—') ?></div>
                            <div class="ua-username">@<?= htmlspecialchars($p['username'] ?? '') ?></div>
                        </td>
                        <td>
                            <span class="ua-pill pill-<?= htmlspecialchars($p['type'] ?? 'photo') ?>">
                                <?= htmlspecialchars(strtoupper($p['type'] ?? 'PHOTO')) ?>
                            </span>
                        </td>
                        <td><?= fmt((int)$p['view_count']) ?></td>
                        <td><?= fmt((int)$p['like_count']) ?></td>
                        <td style="color:rgba(255,255,255,.38);font-size:11px">
                            <?= $p['created_at'] ? date('M j, Y', strtotime($p['created_at'])) : '—' ?>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                    <?php if (empty($topViewedPosts)): ?>
                    <tr><td colspan="6" style="text-align:center;color:rgba(255,255,255,.3)">No data</td></tr>
                    <?php endif; ?>
                </tbody>
            </table>
        </div>
    </div>
</div>

<?php /* ===================================================================
   SECTION 4 — ENGAGEMENT
=================================================================== */ ?>
<div class="ua-section">
    <div class="ua-head">
        <h2>Engagement</h2>
        <span class="ua-badge">Last 14 Days</span>
    </div>
    <div class="ua-body">
        <div class="kpi-grid">
            <div class="kpi-card"><div class="kv"><?= fmt($totalFollows)   ?></div><div class="kl">Total Follows</div></div>
            <div class="kpi-card"><div class="kv"><?= fmt($totalLikes)     ?></div><div class="kl">Total Likes</div></div>
            <div class="kpi-card"><div class="kv"><?= fmt($totalComments)  ?></div><div class="kl">Total Comments</div></div>
            <div class="kpi-card"><div class="kv"><?= fmt($totalPostViews) ?></div><div class="kl">Total Post Views</div></div>
        </div>
        <div style="position:relative;height:180px">
            <canvas id="chartEngagement"></canvas>
        </div>
    </div>
</div>

<?php /* ===================================================================
   SECTION 5 — WALLET & REVENUE
=================================================================== */ ?>
<div class="ua-section">
    <div class="ua-head"><h2>Wallet &amp; Revenue</h2></div>
    <div class="ua-body">
        <div class="kpi-grid">
            <div class="kpi-card"><div class="kv"><?= fmt($totalCoins)   ?></div><div class="kl">Coins in Circulation</div></div>
            <div class="kpi-card"><div class="kv"><?= fmt($totalBalance) ?></div><div class="kl">Total Wallet Balance</div></div>
            <div class="kpi-card"><div class="kv"><?= fmt($subRevenue)   ?></div><div class="kl">Subscription Revenue (coins)</div></div>
        </div>
        <div class="ua-two-col">
            <div>
                <div class="ua-sub">Top 10 Earners by Wallet Balance</div>
                <div class="ua-tbl-wrap">
                    <table class="ua-tbl">
                        <thead>
                            <tr><th>#</th><th>User</th><th>Available</th><th>Locked</th><th>Total</th></tr>
                        </thead>
                        <tbody>
                            <?php foreach ($topEarners as $i => $e): ?>
                            <tr>
                                <td class="ua-rank"><?= $i + 1 ?></td>
                                <td>
                                    <div class="ua-user-name"><?= htmlspecialchars($e['name'] ?? '—') ?></div>
                                    <div class="ua-username">@<?= htmlspecialchars($e['username'] ?? '') ?></div>
                                </td>
                                <td><?= fmt((int)$e['balance_coins']) ?></td>
                                <td style="color:rgba(255,255,255,.4)"><?= fmt((int)$e['locked_coins']) ?></td>
                                <td style="color:#D946EF;font-weight:700"><?= fmt((int)$e['total_coins']) ?></td>
                            </tr>
                            <?php endforeach; ?>
                            <?php if (empty($topEarners)): ?>
                            <tr><td colspan="5" style="text-align:center;color:rgba(255,255,255,.3)">No data</td></tr>
                            <?php endif; ?>
                        </tbody>
                    </table>
                </div>
            </div>
            <div>
                <div class="ua-sub">Transaction Types Breakdown</div>
                <?php $tc = ['#FF007F','#D946EF','#7c3aed','#3b82f6','#22d3ee','#34d399','#fbbf24','#f97316']; $ti = 0; ?>
                <ul class="bk-list">
                    <?php foreach ($txTypeRows as $tx):
                        $lbl = ucfirst((string)($tx['type'] ?? 'unknown')) . ' (' . ($tx['direction'] ?? '?') . ')';
                    ?>
                    <li>
                        <span class="bk-dot" style="background:<?= $tc[$ti % count($tc)] ?>"></span>
                        <span class="bk-label"><?= htmlspecialchars($lbl) ?></span>
                        <span class="bk-val"><?= fmt((int)$tx['c']) ?></span>
                        <span class="bk-pct" style="color:rgba(217,70,239,.75);min-width:68px">
                            <?= fmt((int)$tx['total_coins']) ?>c
                        </span>
                    </li>
                    <?php $ti++; endforeach; ?>
                    <?php if (empty($txTypeRows)): ?>
                    <li style="color:rgba(255,255,255,.3)">No transaction data</li>
                    <?php endif; ?>
                </ul>
            </div>
        </div>
    </div>
</div>

<?php /* ===================================================================
   SECTION 6 — TOP CREATORS
=================================================================== */ ?>
<div class="ua-section">
    <div class="ua-head">
        <h2>Top Creators</h2>
        <span class="ua-badge">Top 15</span>
    </div>
    <div class="ua-body">
        <div class="ua-tbl-wrap">
            <table class="ua-tbl">
                <thead>
                    <tr>
                        <th>#</th>
                        <th>Creator</th>
                        <th>Posts</th>
                        <th>Followers</th>
                        <th>Wallet Balance</th>
                        <th>Joined</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($topCreators as $i => $c): ?>
                    <tr>
                        <td class="ua-rank"><?= $i + 1 ?></td>
                        <td>
                            <div class="ua-user-name"><?= htmlspecialchars($c['name'] ?? '—') ?></div>
                            <div class="ua-username">@<?= htmlspecialchars($c['username'] ?? '') ?></div>
                        </td>
                        <td><?= fmt((int)$c['post_count']) ?></td>
                        <td><?= fmt((int)$c['follower_count']) ?></td>
                        <td style="color:#D946EF;font-weight:700"><?= fmt((int)$c['balance_coins']) ?></td>
                        <td style="color:rgba(255,255,255,.35);font-size:11px">
                            <?= $c['joined'] ? date('M j, Y', strtotime($c['joined'])) : '—' ?>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                    <?php if (empty($topCreators)): ?>
                    <tr><td colspan="6" style="text-align:center;color:rgba(255,255,255,.3)">No data</td></tr>
                    <?php endif; ?>
                </tbody>
            </table>
        </div>
    </div>
</div>

<?php /* ===================================================================
   SECTION 7 — PLATFORM ACTIVITY HEATMAP (signups by hour of day)
=================================================================== */ ?>
<div class="ua-section">
    <div class="ua-head">
        <h2>Signup Activity — Hour of Day</h2>
        <span class="ua-badge">All Time</span>
    </div>
    <div class="ua-body">
        <p style="font-size:12px;color:rgba(255,255,255,.38);margin:0 0 14px">
            Shows which hours users typically sign up. Use this to time campaigns and push notifications.
        </p>
        <div class="hour-grid">
            <?php foreach ($hourMap as $h => $count):
                $heightPct = round($count / $maxHour * 100);
                $alpha     = 0.2 + 0.8 * ($count / $maxHour);
                $bg        = 'rgba(' . (int)(255 * ($count / $maxHour)) . ',0,' . (int)(127 + 128 * (1 - $count / $maxHour)) . ',' . round($alpha, 2) . ')';
            ?>
            <div class="hour-bar-wrap"
                 title="<?= str_pad($h, 2, '0', STR_PAD_LEFT) ?>:00 — <?= fmt($count) ?> signups">
                <div class="hour-bar-fill"
                     style="height:<?= max(3, $heightPct) ?>%;background:<?= $bg ?>">
                </div>
                <div class="hour-label"><?= $h ?>h</div>
            </div>
            <?php endforeach; ?>
        </div>
        <div style="display:flex;justify-content:space-between;margin-top:8px;
                    font-size:11px;color:rgba(255,255,255,.28)">
            <span>12 AM</span><span>6 AM</span><span>12 PM</span><span>6 PM</span><span>11 PM</span>
        </div>
    </div>
</div>

<?php /* ═══ CHART.JS ════════════════════════════════════════════════════════ */ ?>
<script>
(function () {
    /* shared theme */
    const gridColor = 'rgba(255,255,255,0.05)';
    const tickColor = 'rgba(255,255,255,0.40)';
    const baseScales = {
        x: {
            grid:  { color: gridColor },
            ticks: { color: tickColor, font: { size: 11 }, maxRotation: 45 }
        },
        y: {
            grid:  { color: gridColor },
            ticks: { color: tickColor, font: { size: 11 } },
            beginAtZero: true
        }
    };
    const baseOptions = {
        responsive: true,
        maintainAspectRatio: false,
        animation: { duration: 600 },
        plugins: {
            legend: { display: false },
            tooltip: { mode: 'index', intersect: false }
        },
        scales: baseScales
    };

    /* gradient factory */
    function grad(ctx, h, c1, c2) {
        const g = ctx.createLinearGradient(0, 0, 0, h);
        g.addColorStop(0, c1);
        g.addColorStop(1, c2);
        return g;
    }

    /* ── Chart 1: User Growth (line) ──────────────────────────────────── */
    (function () {
        const el = document.getElementById('chartGrowth');
        if (!el) return;
        const ctx = el.getContext('2d');
        const fill = grad(ctx, 180, 'rgba(255,0,127,0.55)', 'rgba(217,70,239,0.03)');
        new Chart(ctx, {
            type: 'line',
            data: {
                labels: <?= json_encode($growthLabels) ?>,
                datasets: [{
                    label: 'New Signups',
                    data: <?= json_encode($growthData) ?>,
                    borderColor: '#FF007F',
                    backgroundColor: fill,
                    borderWidth: 2,
                    pointRadius: 3,
                    pointBackgroundColor: '#FF007F',
                    fill: true,
                    tension: 0.4
                }]
            },
            options: {
                ...baseOptions,
                plugins: {
                    legend: {
                        display: true,
                        labels: { color: tickColor, font: { size: 11 } }
                    },
                    tooltip: { mode: 'index', intersect: false }
                }
            }
        });
    })();

    /* ── Chart 2: Posts per Day (bar) ─────────────────────────────────── */
    (function () {
        const el = document.getElementById('chartPosts');
        if (!el) return;
        const ctx = el.getContext('2d');
        const fill = grad(ctx, 160, 'rgba(217,70,239,0.75)', 'rgba(124,58,237,0.05)');
        new Chart(ctx, {
            type: 'bar',
            data: {
                labels: <?= json_encode($growthLabels) ?>,
                datasets: [{
                    label: 'New Posts',
                    data: <?= json_encode($postDailyData) ?>,
                    backgroundColor: fill,
                    borderColor: '#D946EF',
                    borderWidth: 1,
                    borderRadius: 4
                }]
            },
            options: baseOptions
        });
    })();

    /* ── Chart 3: Engagement stacked bar (14 days) ────────────────────── */
    (function () {
        const el = document.getElementById('chartEngagement');
        if (!el) return;
        const ctx = el.getContext('2d');
        new Chart(ctx, {
            type: 'bar',
            data: {
                labels: <?= json_encode($engLabels) ?>,
                datasets: [
                    {
                        label: 'Likes',
                        data: <?= json_encode($engLikes) ?>,
                        backgroundColor: 'rgba(255,0,127,0.75)',
                        borderRadius: 3,
                        stack: 'eng'
                    },
                    {
                        label: 'Comments',
                        data: <?= json_encode($engCmts) ?>,
                        backgroundColor: 'rgba(217,70,239,0.75)',
                        borderRadius: 3,
                        stack: 'eng'
                    }
                ]
            },
            options: {
                ...baseOptions,
                plugins: {
                    legend: {
                        display: true,
                        labels: { color: tickColor, font: { size: 11 } }
                    },
                    tooltip: { mode: 'index', intersect: false }
                },
                scales: {
                    x: baseScales.x,
                    y: { ...baseScales.y, stacked: true }
                }
            }
        });
    })();
})();
</script>

<?php require __DIR__ . '/_layout_footer.php'; ?>
