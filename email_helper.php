<?php
/**
 * Email Helper for GORETO
 * Sends emails via SMTP using help@goreto.org
 * Includes attractive HTML templates with logo
 */

class EmailHelper
{
  private string $smtpHost = 'mail.goreto.org';
  private int $smtpPort = 587;
  private string $smtpUser = 'help@goreto.org';
  private string $smtpPass = '';
  private string $fromEmail = 'help@goreto.org';
  private string $fromName = 'GORETO Support';
  private string $logoUrl = '';

  public function __construct()
  {
    // Load SMTP settings from config/config.php
    $configFile = __DIR__ . '/config/config.php';
    if (file_exists($configFile)) {
      $config = include $configFile;
      if (is_array($config) && isset($config['smtp'])) {
        $smtp = $config['smtp'];
        if (!empty($smtp['host']))
          $this->smtpHost = $smtp['host'];
        if (!empty($smtp['port']))
          $this->smtpPort = (int) $smtp['port'];
        if (!empty($smtp['username']))
          $this->smtpUser = $smtp['username'];
        if (!empty($smtp['password']))
          $this->smtpPass = $smtp['password'];
        if (!empty($smtp['from_email']))
          $this->fromEmail = $smtp['from_email'];
        if (!empty($smtp['from_name']))
          $this->fromName = $smtp['from_name'];
      }
    }
  }

  /**
   * Send email via system mail() (Postfix/sendmail) or SMTP fallback
   */
  public function send(string $to, string $subject, string $htmlBody, string $textBody = ''): bool
  {
    $boundary = md5(time());
    $headers = "MIME-Version: 1.0\r\n";
    $headers .= "Content-Type: multipart/alternative; boundary=\"{$boundary}\"\r\n";
    $headers .= "From: {$this->fromName} <{$this->fromEmail}>\r\n";
    $headers .= "Reply-To: {$this->fromEmail}\r\n";
    $headers .= "X-Mailer: GORETO/1.0\r\n";

    $message = "--{$boundary}\r\n";
    $message .= "Content-Type: text/plain; charset=UTF-8\r\n";
    $message .= "Content-Transfer-Encoding: 7bit\r\n\r\n";
    $message .= ($textBody ?: strip_tags($htmlBody)) . "\r\n\r\n";
    $message .= "--{$boundary}\r\n";
    $message .= "Content-Type: text/html; charset=UTF-8\r\n";
    $message .= "Content-Transfer-Encoding: 7bit\r\n\r\n";
    $message .= $htmlBody . "\r\n\r\n";
    $message .= "--{$boundary}--\r\n";

    // First try system mail() which uses local Postfix/sendmail
    $result = @mail($to, $subject, $message, $headers);
    if ($result) {
      return true;
    }

    // Fallback to SMTP if mail() fails and credentials are configured
    if (!empty($this->smtpPass) && function_exists('fsockopen')) {
      return $this->sendViaSmtp($to, $subject, $headers, $message);
    }

    error_log("EmailHelper: mail() failed and no SMTP fallback configured");
    return false;
  }

  private function sendViaSmtp(string $to, string $subject, string $headers, string $message): bool
  {
    $socket = @fsockopen($this->smtpHost, $this->smtpPort, $errno, $errstr, 10);
    if (!$socket) {
      error_log("SMTP Connection failed: $errstr ($errno)");
      return false;
    }

    stream_set_timeout($socket, 10);

    $this->smtpRead($socket);
    $this->smtpCmd($socket, "EHLO " . gethostname());
    $this->smtpCmd($socket, "STARTTLS");

    // Enable TLS
    if (!stream_socket_enable_crypto($socket, true, STREAM_CRYPTO_METHOD_TLS_CLIENT)) {
      fclose($socket);
      error_log("SMTP TLS failed");
      return false;
    }

    $this->smtpCmd($socket, "EHLO " . gethostname());
    $this->smtpCmd($socket, "AUTH LOGIN");
    $this->smtpCmd($socket, base64_encode($this->smtpUser));
    $this->smtpCmd($socket, base64_encode($this->smtpPass));
    $this->smtpCmd($socket, "MAIL FROM:<{$this->fromEmail}>");
    $this->smtpCmd($socket, "RCPT TO:<{$to}>");
    $this->smtpCmd($socket, "DATA");

    $data = "Subject: {$subject}\r\n" . $headers . "\r\n" . $message . "\r\n.\r\n";
    fwrite($socket, $data);
    $this->smtpRead($socket);

    $this->smtpCmd($socket, "QUIT");
    fclose($socket);
    return true;
  }

  private function smtpCmd($socket, string $cmd): void
  {
    fwrite($socket, $cmd . "\r\n");
    $this->smtpRead($socket);
  }

  private function smtpRead($socket): string
  {
    $response = '';
    while ($line = fgets($socket, 512)) {
      $response .= $line;
      if (preg_match('/^\d{3} /', $line))
        break;
    }
    return $response;
  }

  /**
   * Generate attractive HTML email template with logo
   */
  public function getTemplate(string $title, string $content, string $ctaText = '', string $ctaUrl = ''): string
  {
    $year = date('Y');
    $ctaButton = '';
    if ($ctaText && $ctaUrl) {
      $ctaButton = <<<HTML
            <tr>
              <td style="padding:20px 30px 30px;text-align:center;">
                <a href="{$ctaUrl}" style="display:inline-block;padding:14px 32px;background:linear-gradient(135deg,#FF6B6B 0%,#FF8E53 100%);color:#fff;text-decoration:none;border-radius:30px;font-weight:600;font-size:15px;box-shadow:0 4px 15px rgba(255,107,107,0.3);">{$ctaText}</a>
              </td>
            </tr>
HTML;
    }

    return <<<HTML
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{$title}</title>
</head>
<body style="margin:0;padding:0;background:#f5f5f5;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f5f5f5;">
  <tr>
    <td align="center" style="padding:30px 15px;">
      <table width="600" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;width:100%;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 10px 40px rgba(0,0,0,0.08);">
        <!-- Header with gradient -->
        <tr>
          <td style="background:linear-gradient(135deg,#FF6B6B 0%,#FF8E53 50%,#FF6B9D 100%);padding:40px 30px;text-align:center;">
            <img src="https://goreto.org/ekloadmin/assets/images/goreto_logo.png" alt="GORETO" width="80" height="80" style="border-radius:50%;display:block;margin:0 auto 15px;border:3px solid rgba(255,255,255,0.25);object-fit:cover;">
            <h1 style="margin:0;color:#fff;font-size:26px;font-weight:700;letter-spacing:-0.5px;">GORETO</h1>
            <p style="margin:8px 0 0;color:rgba(255,255,255,0.85);font-size:13px;">GORETO SUPPORT</p>
          </td>
        </tr>
        <!-- Title -->
        <tr>
          <td style="padding:35px 30px 10px;text-align:center;">
            <h2 style="margin:0;color:#1a1a2e;font-size:22px;font-weight:700;">{$title}</h2>
            <div style="width:50px;height:3px;background:linear-gradient(135deg,#FF6B6B,#FF8E53);margin:12px auto 0;border-radius:2px;"></div>
          </td>
        </tr>
        <!-- Content -->
        <tr>
          <td style="padding:20px 30px;color:#4a4a6a;font-size:15px;line-height:1.7;">
            {$content}
          </td>
        </tr>
        {$ctaButton}
        <!-- Footer -->
        <tr>
          <td style="background:#f8f9fa;padding:25px 30px;text-align:center;border-top:1px solid #eee;">
            <p style="margin:0 0 8px;color:#888;font-size:12px;">Need help? Contact us at <a href="mailto:help@goreto.org" style="color:#FF6B6B;text-decoration:none;">help@goreto.org</a></p>
            <p style="margin:0;color:#aaa;font-size:11px;">GORETO &copy; {$year}. All rights reserved.</p>
            <p style="margin:8px 0 0;color:#ccc;font-size:10px;">Goreto Organization</p>
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>
</body>
</html>
HTML;
  }

  /**
   * Send password reset code email
   */
  public function sendPasswordReset(string $to, string $code, string $userName = ''): bool
  {
    $greeting = $userName ? "Hi {$userName}," : "Hi there,";
    $content = <<<HTML
<p>{$greeting}</p>
<p>We received a request to reset your GORETO password. Use the verification code below to proceed:</p>
<div style="text-align:center;margin:30px 0;">
  <div style="display:inline-block;background:linear-gradient(135deg,#1a1a2e 0%,#16213e 100%);padding:20px 40px;border-radius:12px;">
    <span style="font-family:'Courier New',monospace;font-size:32px;font-weight:700;color:#FF6B6B;letter-spacing:8px;">{$code}</span>
  </div>
</div>
<p style="text-align:center;color:#888;font-size:13px;">This code expires in <strong>15 minutes</strong></p>
<p style="margin-top:25px;">If you didn't request this, you can safely ignore this email. Your account remains secure.</p>
HTML;

    $html = $this->getTemplate('Password Reset Request', $content);
    return $this->send($to, 'GORETO - Password Reset Code', $html, "Your password reset code is: {$code}. Expires in 15 minutes.");
  }

  /**
   * Send welcome email
   */
  public function sendWelcome(string $to, string $userName): bool
  {
    $content = <<<HTML
<p>Hi {$userName},</p>
<p>Welcome to <strong>GORETO</strong>! We're thrilled to have you join our community of people looking for meaningful connections.</p>
<p>Here's what you can do next:</p>
<ul style="color:#4a4a6a;">
  <li>Complete your profile to attract more matches</li>
  <li>Upload your best photos</li>
  <li>Start exploring and connecting with amazing people</li>
</ul>
<p>Need help getting started? Our support team is always here for you.</p>
HTML;

    $html = $this->getTemplate('Welcome to GORETO!', $content, 'Complete Profile', 'https://goreto.org/ekloadmin/app');
    return $this->send($to, 'Welcome to GORETO!', $html, "Welcome to GORETO, {$userName}! Complete your profile to get started.");
  }

  /**
   * Send important notification email
   */
  public function sendImportant(string $to, string $subject, string $message, string $userName = ''): bool
  {
    $greeting = $userName ? "Hi {$userName}," : "Hi there,";
    $content = <<<HTML
<p>{$greeting}</p>
<div style="background:#fff3f3;border-left:4px solid #FF6B6B;padding:15px 20px;margin:15px 0;border-radius:0 8px 8px 0;">
  <p style="margin:0;color:#1a1a2e;font-size:15px;">{$message}</p>
</div>
<p style="margin-top:20px;">If you have any questions, please don't hesitate to reach out to our support team.</p>
HTML;

    $html = $this->getTemplate($subject, $content);
    return $this->send($to, "GORETO - {$subject}", $html, strip_tags($message));
  }
}
