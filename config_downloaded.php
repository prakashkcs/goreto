<?php
// ekloadmin/config/config.php
// Edit DB credentials if needed.
return [
  'db' => [
    'host' => 'localhost',
    'name' => 'sharexhu_dbeklo',
    'user' => 'sharexhu_dbeklo',
    'pass' => 'BMVRgNZPyUTAFP2E36bc',
    'charset' => 'utf8mb4',
  ],

  'security' => [
    // Keep false for compatibility with existing Flutter app.
    // If true, every request must include X-App-Id, X-App-Timestamp, X-App-Signature
    'enforce_app_signature' => false,
    'app_id' => 'love_vibe_pro',
    'app_secret' => 'Ib47RTmAiMO66Vg2kY5gzMYekBNpctMusB7AWAHZDR0IEA1en09r8y1ZDFYM52ni',
    'rate_limit_per_minute' => 120,
  ],

  'admin' => [
    'bootstrap_username' => 'admin',
    'bootstrap_password' => 'admin123',
    'session_name' => 'love_vibe_admin',
  ],

  'base_url' => 'https://coinzop.com/ekloadmin',
];
