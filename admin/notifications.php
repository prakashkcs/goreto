<?php
require_once __DIR__ . '/_core.php';
admin_require_login();
$pageTitle = 'Push Notifications';
$activeNav = 'notifications';

$pdo->exec("CREATE TABLE IF NOT EXISTS notification_settings (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    setting_key VARCHAR(80) NOT NULL UNIQUE,
    setting_value TEXT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

$defaults = [
  'default_provider' => 'in_app',
  'fcm_push_enabled' => '1',
  'onesignal_enabled' => '0',
  'onesignal_app_id' => '',
  'onesignal_api_key' => '',
  'onesignal_target_mode' => 'segments',
];

$msg = '';
$err = '';
$settings = admin_get_settings($pdo, 'notification_settings', $defaults);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
  $formAction = $_POST['form_action'] ?? 'send_notification';

  if ($formAction === 'save_settings') {
    try {
      $values = [
        'default_provider' => $_POST['default_provider'] ?? 'in_app',
        'fcm_push_enabled' => !empty($_POST['fcm_push_enabled']) ? '1' : '0',
        'onesignal_enabled' => !empty($_POST['onesignal_enabled']) ? '1' : '0',
        'onesignal_app_id' => trim($_POST['onesignal_app_id'] ?? ''),
        'onesignal_api_key' => trim($_POST['onesignal_api_key'] ?? ''),
        'onesignal_target_mode' => $_POST['onesignal_target_mode'] ?? 'segments',
      ];
      admin_upsert_settings($pdo, 'notification_settings', $values);
      $settings = admin_get_settings($pdo, 'notification_settings', $defaults);
      $msg = 'Notification settings saved.';
    } catch (Throwable $e) {
      $err = $e->getMessage();
    }
  } else {
    $target = $_POST['target'] ?? 'all';
    $title = trim($_POST['title'] ?? '');
    $body = trim($_POST['body'] ?? '');
    $userId = (int) ($_POST['user_id'] ?? 0);
    $provider = $_POST['provider'] ?? ($settings['default_provider'] ?? 'in_app');
    $important = !empty($_POST['important']);

    try {
      $result = admin_send_notification($pdo, [
        'target' => $target,
        'title' => $title,
        'body' => $body,
        'user_id' => $userId,
        'provider' => $provider,
        'type' => 'admin',
        'important' => $important,
      ]);
      $msg = "Provider: {$result['provider']} • Sent to {$result['sent']} user(s)";
      if (!empty($result['push_sent'])) {
        $msg .= " • Push targets: {$result['push_sent']}";
      }
      if (!empty($result['failed'])) {
        $msg .= " • Failed: {$result['failed']}";
      }
    } catch (Throwable $e) {
      $err = $e->getMessage();
    }
  }
}

// Recent notifications
$recent = [];
try {
  $recent = $pdo->query("
        SELECT n.*, u.name AS u_name FROM notifications n
        LEFT JOIN users u ON u.id = n.user_id
        WHERE n.type = 'admin'
        ORDER BY n.id DESC LIMIT 50
    ")->fetchAll();
} catch (Throwable $_) {
}

require __DIR__ . '/_layout_header.php';
?>
<div class="section">
  <div class="head"><b>Push Notifications</b></div>
  <div class="body">
    <?php if ($msg): ?>
      <div class="badge ok" style="margin-bottom:14px"><?= htmlspecialchars($msg) ?></div><?php endif; ?>
    <?php if ($err): ?>
      <div class="badge danger" style="margin-bottom:14px"><?= htmlspecialchars($err) ?></div><?php endif; ?>

    <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:18px;margin-bottom:28px">
      <div style="background:rgba(15,27,51,.5);border:1px solid #223a66;border-radius:10px;padding:20px;">
        <h3 style="margin-top:0">Send App Notification</h3>
        <form method="post">
          <input type="hidden" name="form_action" value="send_notification">
          <div style="margin-bottom:14px">
            <label style="display:block;margin-bottom:5px;font-weight:600">Delivery Mode</label>
            <select name="provider"
              style="width:100%;padding:8px 12px;border-radius:6px;border:1px solid #334;background:#0a0a14;color:#fff">
              <option value="in_app" <?= ($settings['default_provider'] ?? 'in_app') === 'in_app' ? 'selected' : '' ?>>
                In-app only</option>
              <option value="server_push" <?= ($settings['default_provider'] ?? 'in_app') === 'server_push' ? 'selected' : '' ?>>In-app + server push</option>
              <option value="onesignal" <?= ($settings['default_provider'] ?? 'in_app') === 'onesignal' ? 'selected' : '' ?>>OneSignal API</option>
            </select>
            <small style="opacity:.7">In-app only stays inside app. Use server push or OneSignal for outside app
              notifications.</small>
          </div>
          <div style="margin-bottom:14px">
            <label style="display:block;margin-bottom:5px;font-weight:600">Send To</label>
            <select name="target"
              onchange="document.getElementById('uid-row').style.display=this.value==='user'?'block':'none'"
              style="width:100%;padding:8px 12px;border-radius:6px;border:1px solid #334;background:#0a0a14;color:#fff">
              <option value="all">All Users</option>
              <option value="user">Specific User</option>
            </select>
          </div>
          <div id="uid-row" style="display:none;margin-bottom:14px">
            <label style="display:block;margin-bottom:5px;font-weight:600">User ID</label>
            <input type="number" name="user_id" placeholder="Enter User ID"
              style="width:100%;padding:8px 12px;border-radius:6px;border:1px solid #334;background:#0a0a14;color:#fff">
          </div>
          <div style="margin-bottom:14px">
            <label style="display:block;margin-bottom:5px;font-weight:600">Title</label>
            <input type="text" name="title" required maxlength="80"
              style="width:100%;padding:8px 12px;border-radius:6px;border:1px solid #334;background:#0a0a14;color:#fff">
          </div>
          <div style="margin-bottom:14px">
            <label style="display:block;margin-bottom:5px;font-weight:600">Message</label>
            <textarea name="body" rows="3" required maxlength="300"
              style="width:100%;padding:8px 12px;border-radius:6px;border:1px solid #334;background:#0a0a14;color:#fff;resize:vertical"></textarea>
          </div>
          <label style="display:flex;align-items:center;gap:8px;margin-bottom:20px">
            <input type="checkbox" name="important" value="1">
            <span>Important notification (allow push/tray behavior)</span>
          </label>
          <button type="submit" onclick="return confirm('Send this notification?')"
            style="padding:10px 28px;background:linear-gradient(135deg,#FF007F,#D946EF);color:#fff;border:none;border-radius:8px;font-weight:700;cursor:pointer;font-size:15px">
            📣 Send Notification
          </button>
        </form>
      </div>

      <div style="background:rgba(15,27,51,.5);border:1px solid #223a66;border-radius:10px;padding:20px;">
        <h3 style="margin-top:0">Notification Provider Settings</h3>
        <form method="post">
          <input type="hidden" name="form_action" value="save_settings">
          <div style="margin-bottom:14px">
            <label style="display:block;margin-bottom:5px;font-weight:600">Default Provider</label>
            <select name="default_provider"
              style="width:100%;padding:8px 12px;border-radius:6px;border:1px solid #334;background:#0a0a14;color:#fff">
              <option value="in_app" <?= ($settings['default_provider'] ?? 'in_app') === 'in_app' ? 'selected' : '' ?>>
                In-app only</option>
              <option value="server_push" <?= ($settings['default_provider'] ?? 'in_app') === 'server_push' ? 'selected' : '' ?>>In-app + server push</option>
              <option value="onesignal" <?= ($settings['default_provider'] ?? 'in_app') === 'onesignal' ? 'selected' : '' ?>>OneSignal API</option>
            </select>
          </div>
          <label style="display:flex;align-items:center;gap:8px;margin-bottom:10px">
            <input type="checkbox" name="fcm_push_enabled" value="1" <?= !empty($settings['fcm_push_enabled']) ? 'checked' : '' ?>>
            <span>Enable server-side FCM push</span>
          </label>
          <label style="display:flex;align-items:center;gap:8px;margin-bottom:14px">
            <input type="checkbox" name="onesignal_enabled" value="1" <?= !empty($settings['onesignal_enabled']) ? 'checked' : '' ?>>
            <span>Enable OneSignal provider</span>
          </label>
          <div style="margin-bottom:14px">
            <label style="display:block;margin-bottom:5px;font-weight:600">OneSignal App ID</label>
            <input type="text" name="onesignal_app_id"
              value="<?= htmlspecialchars($settings['onesignal_app_id'] ?? '') ?>"
              style="width:100%;padding:8px 12px;border-radius:6px;border:1px solid #334;background:#0a0a14;color:#fff">
          </div>
          <div style="margin-bottom:14px">
            <label style="display:block;margin-bottom:5px;font-weight:600">OneSignal REST API Key</label>
            <input type="text" name="onesignal_api_key"
              value="<?= htmlspecialchars($settings['onesignal_api_key'] ?? '') ?>"
              style="width:100%;padding:8px 12px;border-radius:6px;border:1px solid #334;background:#0a0a14;color:#fff">
          </div>
          <div style="margin-bottom:20px">
            <label style="display:block;margin-bottom:5px;font-weight:600">OneSignal Target Mode</label>
            <select name="onesignal_target_mode"
              style="width:100%;padding:8px 12px;border-radius:6px;border:1px solid #334;background:#0a0a14;color:#fff">
              <option value="segments" <?= ($settings['onesignal_target_mode'] ?? 'segments') === 'segments' ? 'selected' : '' ?>>All segment</option>
              <option value="player_ids" <?= ($settings['onesignal_target_mode'] ?? 'segments') === 'player_ids' ? 'selected' : '' ?>>Player IDs from database</option>
            </select>
          </div>
          <button type="submit"
            style="padding:10px 28px;background:linear-gradient(135deg,#2563eb,#7c3aed);color:#fff;border:none;border-radius:8px;font-weight:700;cursor:pointer;font-size:15px">
            Save Provider Settings
          </button>
        </form>
      </div>
    </div>

    <?php if ($recent): ?>
      <h3 style="margin-bottom:12px">Recent Admin Notifications</h3>
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>ID</th>
              <th>User</th>
              <th>Title</th>
              <th>Body</th>
              <th>Sent</th>
            </tr>
          </thead>
          <tbody>
            <?php foreach ($recent as $n): ?>
              <tr>
                <td>#
                  <?= (int) $n['id'] ?>
                </td>
                <td>
                  <?= htmlspecialchars($n['u_name'] ?? 'User ' . $n['user_id']) ?>
                </td>
                <td>
                  <?= htmlspecialchars($n['title'] ?? '') ?>
                </td>
                <td>
                  <?= htmlspecialchars($n['body'] ?? '') ?>
                </td>
                <td><small>
                    <?= htmlspecialchars($n['created_at'] ?? '') ?>
                  </small></td>
              </tr>
            <?php endforeach; ?>
          </tbody>
        </table>
      </div>
    <?php endif; ?>
  </div>
</div>
<?php require __DIR__ . '/_layout_footer.php'; ?>