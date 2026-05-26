<?php
// Suppress all PHP errors/warnings from polluting JSON output
error_reporting(0);
ini_set('display_errors', 0);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(200);
  exit;
}

function json_out($code, $arr)
{
  http_response_code($code);
  echo json_encode($arr, JSON_UNESCAPED_UNICODE);
  exit;
}

$action = $_GET['action'] ?? $_POST['action'] ?? '';

// Try DB — but fall back to hardcoded if anything fails
$row = null;
if (in_array($action, ['terms', 'privacy'])) {
  try {
    require_once __DIR__ . '/db_connect.php';
    // Ensure table exists
    $pdo->exec("CREATE TABLE IF NOT EXISTS legal_pages (
      id INT AUTO_INCREMENT PRIMARY KEY,
      page_key VARCHAR(50) NOT NULL UNIQUE,
      title VARCHAR(255) NOT NULL,
      content LONGTEXT NOT NULL,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    // Version tag — bump this whenever default content changes to force a DB refresh.
    $contentVersion = 'v3';
    $storedVersion  = $pdo->query("SELECT content FROM legal_pages WHERE page_key='_version'")->fetchColumn();
    if ($storedVersion !== $contentVersion) {
      $ins = $pdo->prepare("INSERT INTO legal_pages (page_key, title, content) VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE title=VALUES(title), content=VALUES(content), updated_at=NOW()");
      $ins->execute(['terms',    'Terms & Conditions', default_terms()]);
      $ins->execute(['privacy',  'Privacy Policy',     default_privacy()]);
      $ins->execute(['_version', 'Content Version',    $contentVersion]);
    }

    $stmt = $pdo->prepare("SELECT title, content, updated_at FROM legal_pages WHERE page_key = ?");
    $stmt->execute([$action]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
  } catch (Throwable $e) {
    $row = null; // fall through to hardcoded
  }
}

// GET — public fetch
if ($_SERVER['REQUEST_METHOD'] === 'GET' && in_array($action, ['terms', 'privacy'])) {
  if (!$row) {
    $row = [
      'title' => $action === 'terms' ? 'Terms & Conditions' : 'Privacy Policy',
      'content' => $action === 'terms' ? default_terms() : default_privacy(),
      'updated_at' => date('Y-m-d H:i:s'),
    ];
  }
  json_out(200, ['status' => 'success', 'page' => $row]);
}

// POST — admin update
if ($_SERVER['REQUEST_METHOD'] === 'POST' && $action === 'update') {
  try {
    require_once __DIR__ . '/db_connect.php';
    require_once __DIR__ . '/auth_middleware.php';
    $viewer = requireUser($pdo);
    if (($viewer['role'] ?? '') !== 'admin')
      json_out(403, ['status' => 'error', 'message' => 'Forbidden']);
  } catch (Throwable $e) {
    json_out(401, ['status' => 'error', 'message' => 'Unauthorized']);
  }

  $raw = json_decode(file_get_contents('php://input'), true) ?? $_POST;
  $key = $raw['page_key'] ?? '';
  $title = trim($raw['title'] ?? '');
  $content = trim($raw['content'] ?? '');

  if (!in_array($key, ['terms', 'privacy']) || !$title || !$content)
    json_out(400, ['status' => 'error', 'message' => 'page_key, title and content required']);

  try {
    $pdo->prepare("INSERT INTO legal_pages (page_key, title, content) VALUES (?,?,?)
      ON DUPLICATE KEY UPDATE title=VALUES(title), content=VALUES(content), updated_at=NOW()")
      ->execute([$key, $title, $content]);
    json_out(200, ['status' => 'success', 'message' => 'Saved']);
  } catch (Throwable $e) {
    json_out(500, ['status' => 'error', 'message' => 'DB error: ' . $e->getMessage()]);
  }
}

json_out(400, ['status' => 'error', 'message' => 'Invalid request']);

// ── DEFAULT CONTENT ──────────────────────────────────────────────────────────
function default_terms(): string
{
  return <<<HTML
<h2>Terms &amp; Conditions</h2>
<p>Effective Date: April 27, 2025 | Last Updated: April 27, 2025</p>
<p>Welcome to <strong>GORETO</strong> ("App", "Platform", "we", "us", or "our"), a social entertainment and live streaming application operated under the laws of Nepal. By downloading, installing, registering, or using this App, you ("User", "you") agree to be legally bound by these Terms &amp; Conditions ("Terms"). If you do not agree, do not use the App.</p>

<h3>1. Eligibility &amp; Age Requirement</h3>
<p>You must be at least <strong>18 years of age</strong> to register and use GORETO. By creating an account, you confirm that you are 18 or older. We do not knowingly permit minors to use the App. If we discover a user is under 18, their account will be permanently terminated and any wallet balance forfeited. Parents or guardians who discover their minor child has registered must contact us immediately at <strong>help@goreto.org</strong>.</p>

<h3>2. Account Registration &amp; Security</h3>
<p>You agree to provide accurate, truthful, and complete information during registration. You are solely responsible for maintaining the confidentiality of your login credentials. You must notify us immediately of any unauthorized access to your account. We are not liable for any loss resulting from unauthorized use of your account. One person may hold only one account; duplicate accounts will be removed.</p>

<h3>3. User Conduct &amp; Acceptable Use</h3>
<p>You agree NOT to:</p>
<ul>
  <li>Post, share, or transmit content that is illegal, harmful, threatening, abusive, harassing, defamatory, obscene, pornographic, or otherwise objectionable under Nepali law or international standards</li>
  <li>Upload, share, or distribute Child Sexual Abuse Material (CSAM) — this is a serious criminal offense and will be immediately reported to Nepal Police Cyber Bureau and relevant international authorities</li>
  <li>Impersonate any person, entity, or misrepresent your identity or affiliation</li>
  <li>Harass, stalk, threaten, intimidate, or harm other users</li>
  <li>Use the App for any purpose that violates Nepal's Electronic Transactions Act 2063, Individual Privacy Act 2075, or any other applicable law</li>
  <li>Engage in fraud, scams, phishing, or any deceptive practices</li>
  <li>Use automated bots, scrapers, or unauthorized scripts to access the App</li>
  <li>Sell, rent, or transfer your account to any third party</li>
  <li>Attempt to reverse-engineer, hack, or compromise the App's security</li>
  <li>Spread misinformation, fake news, or content that incites violence or communal disharmony</li>
  <li>Use the App for gambling, illegal betting, or any activity prohibited under Nepali law</li>
  <li>Solicit money from other users under false pretenses</li>
</ul>

<h3>4. User-Generated Content</h3>
<p>You retain ownership of content you create and post. By posting content on GORETO, you grant us a non-exclusive, worldwide, royalty-free, sublicensable license to use, display, reproduce, distribute, and promote your content within the App and for marketing purposes. You are solely responsible for your content. We reserve the right to remove any content that violates these Terms, our Community Guidelines, or applicable law — without prior notice.</p>

<h3>5. Virtual Coins &amp; In-App Currency</h3>
<p>GORETO offers virtual coins ("Coins") that can be purchased within the App. Coins are used to send virtual gifts, access premium features, and support creators. Important terms:</p>
<ul>
  <li>All Coin purchases are <strong>final and non-refundable</strong> except as required by applicable law</li>
  <li>Coins have <strong>no real-world monetary value</strong> and cannot be exchanged for cash by regular users</li>
  <li>Unused Coins do not expire but may be forfeited if your account is terminated for violations</li>
  <li>We reserve the right to modify Coin pricing, exchange rates, and availability at any time</li>
  <li>Coins obtained through fraudulent means will be revoked and the account banned</li>
  <li>Coin transactions are processed through secure payment gateways compliant with applicable regulations</li>
</ul>

<h3>6. Payments &amp; Wallet</h3>
<p>The App provides an in-app wallet for managing Coins and earnings. Payment methods available include eSewa, Khalti, bank transfer, and other Nepal-approved payment gateways. By making a payment, you agree to the terms of the respective payment provider. We are not responsible for payment failures caused by third-party payment processors. All transactions are recorded and may be subject to review for fraud prevention. Disputed transactions must be reported within 7 days.</p>

<h3>7. Creator Earnings &amp; Withdrawals</h3>
<p>Verified creators may earn from virtual gifts received during live streams and other interactions. Earnings are subject to platform commission rates as displayed in the App. Withdrawal requests are processed within 3-7 business days. Minimum withdrawal amounts apply as specified in the App. We reserve the right to withhold earnings pending KYC verification or fraud investigation. Earnings may be subject to applicable Nepali tax laws; users are responsible for their own tax compliance.</p>

<h3>8. KYC (Know Your Customer) &amp; Identity Verification</h3>
<p>To access withdrawal features and certain premium functions, you must complete KYC verification. KYC requires submission of:</p>
<ul>
  <li>Government-issued photo ID (Citizenship Certificate, Passport, or National ID Card)</li>
  <li>A clear selfie holding your ID</li>
  <li>Bank account or mobile wallet details for withdrawals</li>
</ul>
<p>KYC documents are reviewed by our team and stored securely. Submitting false or forged documents is a criminal offense under Nepali law. We reserve the right to reject KYC applications and suspend accounts pending verification. KYC data is handled in accordance with our Privacy Policy and Nepal's Individual Privacy Act 2075.</p>

<h3>9. Subscriptions &amp; Premium Plans</h3>
<p>GORETO offers optional subscription plans that unlock premium features. Subscriptions are billed on a recurring basis (weekly, monthly, or as specified). Subscriptions auto-renew unless cancelled at least 24 hours before the renewal date. You can manage or cancel subscriptions through your device's app store (Google Play Store / Apple App Store). Refunds for subscriptions are governed by the respective app store's refund policy. We do not offer direct refunds for subscription fees except as required by law.</p>

<h3>10. Live Streaming Rules</h3>
<p>Live streaming is subject to our Community Guidelines. You must not broadcast:</p>
<ul>
  <li>Nudity, sexual content, or adult material of any kind</li>
  <li>Violence, self-harm, or dangerous activities</li>
  <li>Content that promotes illegal activities, drugs, or weapons</li>
  <li>Hate speech, discrimination, or content targeting individuals</li>
  <li>Copyrighted music, movies, or content without proper licensing</li>
  <li>Political propaganda or content that could incite civil unrest</li>
</ul>
<p>Violations may result in immediate stream termination, temporary suspension, or permanent ban. Repeated violations will result in permanent account termination.</p>

<h3>11. Intellectual Property &amp; Copyright</h3>
<p>All App content, design, logos, trademarks, software, and features (excluding user-generated content) are the exclusive property of GORETO and are protected under Nepal's Copyright Act 2059 and international intellectual property laws. You may not copy, modify, distribute, sell, or create derivative works from our proprietary content without express written permission. If you believe your copyright has been infringed, contact us at <strong>help@goreto.org</strong> with details of the alleged infringement.</p>

<h3>12. Privacy &amp; Data Protection</h3>
<p>Your use of the App is governed by our Privacy Policy, which is incorporated into these Terms by reference. We comply with Nepal's Individual Privacy Act 2075 (Byaktigat Gupta ta Sambandhi Ain). By using the App, you consent to the collection and processing of your data as described in our Privacy Policy.</p>

<h3>13. Location Services</h3>
<p>The App uses your device's location to show nearby users and enable proximity-based features. Location data is stored securely and shown to other users only as approximate distance. You can disable location access in your device settings at any time, though this will limit certain features.</p>

<h3>14. Third-Party Services &amp; Links</h3>
<p>The App integrates with third-party services including Firebase (Google), payment gateways, and CDN providers. We are not responsible for the practices of third-party services. Links to external websites are provided for convenience; we do not endorse or control their content.</p>

<h3>15. Disclaimers &amp; Limitation of Liability</h3>
<p>THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED. WE DO NOT GUARANTEE UNINTERRUPTED, ERROR-FREE, OR VIRUS-FREE SERVICE. WE ARE NOT RESPONSIBLE FOR ANY INTERACTIONS, MEETINGS, OR TRANSACTIONS BETWEEN USERS. TO THE MAXIMUM EXTENT PERMITTED BY NEPALI LAW, GORETO SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES ARISING FROM YOUR USE OF THE APP.</p>

<h3>16. Account Suspension &amp; Termination</h3>
<p>We reserve the right to suspend, restrict, or permanently terminate your account at any time, with or without notice, for:</p>
<ul>
  <li>Violation of these Terms or Community Guidelines</li>
  <li>Fraudulent activity or abuse of the platform</li>
  <li>Requests from law enforcement or regulatory authorities</li>
  <li>Extended inactivity (accounts inactive for 12+ months may be deleted)</li>
</ul>
<p>Upon termination, your right to use the App ceases immediately. Any remaining Coin balance may be forfeited if termination is due to violations.</p>

<h3>17. Dispute Resolution</h3>
<p>Any disputes arising from these Terms or your use of the App shall first be attempted to be resolved through good-faith negotiation. If unresolved, disputes shall be subject to the jurisdiction of the courts of Nepal. These Terms are governed by the laws of Nepal.</p>

<h3>18. Compliance with App Store Policies</h3>
<p>This App is distributed through Google Play Store and Apple App Store. Your use of the App is also subject to the respective app store's Terms of Service. In case of conflict between these Terms and app store policies, the more restrictive terms apply.</p>

<h3>19. Changes to These Terms</h3>
<p>We may update these Terms from time to time. We will notify you of significant changes via in-app notification or email. Your continued use of the App after changes are posted constitutes your acceptance of the revised Terms. We recommend reviewing these Terms periodically.</p>

<h3>20. Contact Us</h3>
<p>For questions, complaints, or legal notices regarding these Terms, contact us:</p>
<ul>
  <li>Email: <strong>help@goreto.org</strong></li>
  <li>Legal notices: <strong>prakashchandrakarki007@gmail.com</strong></li>
  <li>Address: Kathmandu, Nepal</li>
</ul>
HTML;
}

function default_privacy(): string
{
  return <<<HTML
<h2>Privacy Policy</h2>
<p>Effective Date: April 27, 2025 | Last Updated: April 27, 2025</p>
<p><strong>GORETO</strong> ("we", "us", or "our") is committed to protecting your personal information. This Privacy Policy explains how we collect, use, store, share, and protect your data when you use our App. We comply with Nepal's <strong>Individual Privacy Act 2075 (Byaktigat Gupta ta Sambandhi Ain 2075)</strong> and applicable international data protection standards.</p>

<h3>1. Information We Collect</h3>
<h4>Information You Provide Directly</h4>
<ul>
  <li>Account details: full name, email address, phone number, date of birth, gender</li>
  <li>Profile information: profile photo, bio, interests, location (city/district)</li>
  <li>KYC documents: government-issued ID (Citizenship Certificate, Passport, National ID), selfie with ID</li>
  <li>Financial information: wallet transaction history, bank account or mobile wallet details for withdrawals</li>
  <li>Communications: messages, chat content, live stream interactions, support requests</li>
  <li>User-generated content: photos, videos, audio, posts, reels, stories</li>
</ul>
<h4>Information Collected Automatically</h4>
<ul>
  <li>Device information: device model, operating system version, unique device identifiers</li>
  <li>Usage data: features accessed, time spent, interactions, content viewed</li>
  <li>Location data: GPS coordinates (only when you grant permission)</li>
  <li>Network information: IP address, mobile network, Wi-Fi connection details</li>
  <li>Log data: access times, error logs, crash reports</li>
  <li>Push notification tokens (Firebase Cloud Messaging / FCM)</li>
  <li>Analytics data: session duration, screen views, user flow</li>
</ul>

<h3>2. How We Use Your Information</h3>
<ul>
  <li>To create and manage your account and provide App services</li>
  <li>To match you with nearby users and facilitate social connections</li>
  <li>To process payments, manage your wallet, and handle withdrawal requests</li>
  <li>To verify your identity through KYC for financial features</li>
  <li>To send push notifications, in-app alerts, and important updates</li>
  <li>To detect, prevent, and investigate fraud, abuse, and violations of our Terms</li>
  <li>To comply with legal obligations under Nepali law and court orders</li>
  <li>To improve App performance, features, and user experience</li>
  <li>To communicate with you about support, updates, and promotions</li>
  <li>To enforce our Terms &amp; Conditions and Community Guidelines</li>
</ul>

<h3>3. Location Data</h3>
<p>We collect your precise GPS location to power nearby user discovery and proximity features. Your exact location is never shared with other users — only an approximate distance (e.g., "2 km away") is displayed. Location data is encrypted in transit and at rest. You can revoke location permission at any time in your device settings; this will disable nearby features but will not affect other App functionality.</p>

<h3>4. KYC Data Handling</h3>
<p>KYC documents (ID cards, selfies) are collected solely for identity verification and fraud prevention. KYC data is:</p>
<ul>
  <li>Stored on secure, encrypted servers</li>
  <li>Accessible only to authorized verification staff</li>
  <li>Never sold or shared with third parties except as required by law</li>
  <li>Retained for the duration of your account and for up to 5 years after account closure for legal compliance</li>
  <li>Handled in accordance with Nepal's Individual Privacy Act 2075</li>
</ul>

<h3>5. Payment &amp; Financial Data</h3>
<p>Payment transactions are processed through secure, PCI-compliant payment gateways (eSewa, Khalti, bank transfer, etc.). We do not store your full payment card details. Transaction records are maintained for accounting, fraud prevention, and legal compliance purposes. Financial data may be shared with payment processors and, when required, with tax or regulatory authorities in Nepal.</p>

<h3>6. How We Share Your Information</h3>
<p>We do <strong>NOT</strong> sell your personal data to any third party. We may share information only in the following circumstances:</p>
<ul>
  <li><strong>Service providers:</strong> hosting providers, payment processors, push notification services (Firebase/FCM), CDN providers, analytics tools — strictly for operating the App</li>
  <li><strong>Law enforcement &amp; legal authorities:</strong> when required by Nepali law, court order, or to protect the safety of users or the public</li>
  <li><strong>Nepal Police Cyber Bureau:</strong> in cases involving CSAM, cybercrime, or serious criminal activity</li>
  <li><strong>Business transfers:</strong> in the event of a merger, acquisition, or sale of company assets, with appropriate data protection safeguards</li>
  <li><strong>With your consent:</strong> for any other purpose with your explicit consent</li>
</ul>

<h3>7. Data Retention</h3>
<p>We retain your personal data for as long as your account is active or as needed to provide services. Upon account deletion:</p>
<ul>
  <li>Profile data and user-generated content are deleted within 30 days</li>
  <li>Chat messages are deleted within 30 days</li>
  <li>Financial transaction records are retained for 5 years for legal and accounting compliance</li>
  <li>KYC documents are retained for 5 years as required by financial regulations</li>
  <li>Log data is retained for 90 days for security purposes</li>
</ul>

<h3>8. Data Security</h3>
<p>We implement industry-standard security measures to protect your data:</p>
<ul>
  <li>All data transmitted between the App and our servers is encrypted using HTTPS/TLS</li>
  <li>Passwords are hashed using bcrypt — we never store plain-text passwords</li>
  <li>Database access is restricted to authorized personnel only</li>
  <li>Regular security audits and vulnerability assessments</li>
  <li>Two-factor authentication available for account security</li>
</ul>
<p>Despite these measures, no internet transmission is 100% secure. We cannot guarantee absolute security and are not liable for unauthorized access beyond our reasonable control.</p>

<h3>9. Children's Privacy</h3>
<p>GORETO is strictly for users aged <strong>18 and older</strong>. We do not knowingly collect personal information from anyone under 18. If we become aware that a minor has created an account, we will immediately delete all their data and terminate the account. If you believe a minor is using the App, please report it to <strong>help@goreto.org</strong> immediately.</p>

<h3>10. Your Rights Under Nepal's Privacy Act 2075</h3>
<p>Under Nepal's Individual Privacy Act 2075, you have the following rights regarding your personal data:</p>
<ul>
  <li><strong>Right to Access:</strong> Request a copy of the personal data we hold about you</li>
  <li><strong>Right to Correction:</strong> Request correction of inaccurate or incomplete data</li>
  <li><strong>Right to Deletion:</strong> Request deletion of your personal data ("right to be forgotten")</li>
  <li><strong>Right to Restriction:</strong> Request that we limit how we process your data</li>
  <li><strong>Right to Data Portability:</strong> Receive your data in a structured, machine-readable format</li>
  <li><strong>Right to Object:</strong> Object to processing of your data for certain purposes</li>
  <li><strong>Right to Withdraw Consent:</strong> Withdraw consent at any time without affecting prior processing</li>
</ul>
<p>To exercise any of these rights, contact us at <strong>help@goreto.org</strong>. We will respond within 30 days.</p>

<h3>11. Push Notifications</h3>
<p>We use Firebase Cloud Messaging (FCM) to send push notifications about matches, messages, gifts, and App updates. You can disable push notifications at any time in your device settings or within the App's notification preferences. Disabling notifications will not affect your ability to use the App.</p>

<h3>12. Analytics &amp; Tracking</h3>
<p>We use Firebase Analytics to understand how users interact with the App. This helps us improve features and fix issues. Analytics data is aggregated and anonymized where possible. You can opt out of analytics tracking in your device settings.</p>

<h3>13. Third-Party Services</h3>
<p>The App integrates with the following third-party services, each with their own privacy policies:</p>
<ul>
  <li><strong>Firebase (Google):</strong> Push notifications, analytics, crash reporting</li>
  <li><strong>eSewa / Khalti:</strong> Payment processing for Nepal users</li>
  <li><strong>CDN Providers:</strong> Media delivery and storage</li>
  <li><strong>OneSignal:</strong> Push notification delivery</li>
</ul>
<p>We encourage you to review the privacy policies of these third-party services.</p>

<h3>14. International Data Transfers</h3>
<p>Some of our service providers (e.g., Firebase/Google) may process your data outside Nepal. We ensure appropriate safeguards are in place for such transfers, including data processing agreements that require equivalent data protection standards.</p>

<h3>15. Cookies &amp; Local Storage</h3>
<p>The App uses local device storage (not browser cookies) to store session tokens, preferences, and cached data for performance. This data is stored only on your device and is cleared when you log out or uninstall the App.</p>

<h3>16. Compliance with App Store Privacy Requirements</h3>
<p>This App complies with Google Play Store's Data Safety requirements and Apple App Store's App Privacy requirements. Our data collection and usage practices are disclosed in the respective app store listings.</p>

<h3>17. Changes to This Privacy Policy</h3>
<p>We may update this Privacy Policy periodically to reflect changes in our practices or legal requirements. We will notify you of material changes via in-app notification or email at least 7 days before the changes take effect. Your continued use of the App after the effective date constitutes acceptance of the updated policy.</p>

<h3>18. Contact &amp; Grievance Officer</h3>
<p>For privacy-related questions, requests, or complaints, contact our Privacy Officer:</p>
<ul>
  <li>Email: <strong>help@goreto.org</strong></li>
  <li>Support: <strong>help@goreto.org</strong></li>
  <li>Legal notices: <strong>prakashchandrakarki007@gmail.com</strong></li>
  <li>Address: Kathmandu, Nepal</li>
</ul>
<p>We are committed to resolving privacy concerns promptly and in accordance with Nepal's Individual Privacy Act 2075.</p>
HTML;
}
