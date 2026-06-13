<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Withdrawal Settings';
$activeNav = 'withdrawal_settings';

$pdo->exec("CREATE TABLE IF NOT EXISTS withdrawal_settings (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    setting_key VARCHAR(80) NOT NULL UNIQUE,
    setting_value VARCHAR(255) NOT NULL DEFAULT '',
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$defaults = [
    'min_withdraw_coins'  => '500',
    'max_withdraw_coins'  => '100000',
    'withdraw_fee_pct'    => '0',
    'coins_per_unit'      => '1',
    'currency_code'       => 'NPR',
    'allowed_methods'     => 'Bank Transfer,eSewa,Khalti',
    'withdraw_enabled'    => '1',
    'processing_days'     => '3',
];

$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    try {
        foreach ($defaults as $key => $_) {
            $val = trim($_POST[$key] ?? '');
            $pdo->prepare("INSERT INTO withdrawal_settings (setting_key,setting_value) VALUES (?,?) ON DUPLICATE KEY UPDATE setting_value=?, updated_at=NOW()")
                ->execute([$key, $val, $val]);
        }
        $msg = 'Saved!';
    } catch (Throwable $e) { $msg = 'Error: '.$e->getMessage(); }
}

$settings = [];
try {
    foreach ($pdo->query("SELECT setting_key,setting_value FROM withdrawal_settings")->fetchAll() as $r)
        $settings[$r['setting_key']] = $r['setting_value'];
} catch (Throwable $_) {}
foreach ($defaults as $k => $v) $settings[$k] ??= $v;

require __DIR__ . '/_layout_header.php';
?>
<div class="section">
  <div class="head"><b>Withdrawal Settings</b></div>
  <div class="body">
    <?php if ($msg): ?><div class="badge <?= str_starts_with($msg,'Error')?'danger':'ok' ?>" style="margin-bottom:14px"><?= htmlspecialchars($msg) ?></div><?php endif; ?>
    <form method="post" style="max-width:560px">
      <?php
      $fields = [
          'min_withdraw_coins'  => ['Min Withdrawal (coins)', 'number'],
          'max_withdraw_coins'  => ['Max Withdrawal (coins)', 'number'],
          'withdraw_fee_pct'    => ['Fee %', 'number'],
          'coins_per_unit'      => ['Coins per 1 Currency Unit', 'number'],
          'currency_code'       => ['Currency Code', 'text'],
          'allowed_methods'     => ['Allowed Methods (comma-separated)', 'text'],
          'processing_days'     => ['Processing Days', 'number'],
      ];
      foreach ($fields as $key => [$label, $type]): ?>
        <div style="margin-bottom:16px">
          <label style="display:block;margin-bottom:5px;font-weight:600"><?= $label ?></label>
          <input type="<?= $type ?>" name="<?= $key ?>" value="<?= htmlspecialchars($settings[$key]) ?>"
                 style="width:100%;padding:9px 12px;border-radius:6px;border:1px solid #334;background:#0a0a14;color:#fff;font-size:14px">
        </div>
      <?php endforeach; ?>
      <label style="display:flex;align-items:center;gap:8px;margin-bottom:20px">
        <input type="checkbox" name="withdraw_enabled" value="1" <?= !empty($settings['withdraw_enabled']) ? 'checked' : '' ?>>
        <span>Enable withdrawals</span>
      </label>
      <button type="submit" style="padding:10px 28px;background:linear-gradient(135deg,#FF007F,#D946EF);color:#fff;border:none;border-radius:8px;font-weight:700;cursor:pointer;font-size:15px">Save</button>
    </form>
  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>
