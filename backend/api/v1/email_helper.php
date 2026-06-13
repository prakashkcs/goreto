<?php
/**
 * email_helper.php — Outbound email via the server's local Postfix MTA.
 *
 * The external submission host (mail.goreto.org:587) is not reachable from the
 * app server, but a local Postfix relay listens on 127.0.0.1:25 and PHP mail()
 * (sendmail) delivers through it. This helper wraps mail() with proper MIME +
 * From headers pulled from config.php's `smtp` block.
 *
 * Used by:
 *   - api_password_reset.php  -> sendPasswordReset()
 *   - auth.php / account.php   -> sendOtp()  (2FA login codes)
 */

class EmailHelper
{
    private string $fromEmail;
    private string $fromName;

    public function __construct()
    {
        $cfg = [];
        $path = '/var/www/html/ekloadmin/config/config.php';
        if (is_file($path)) {
            $loaded = require $path;
            if (is_array($loaded)) {
                $cfg = $loaded['smtp'] ?? [];
            }
        }
        $this->fromEmail = (string) ($cfg['from_email'] ?? 'help@goreto.org');
        $this->fromName = (string) ($cfg['from_name'] ?? 'GORETO');
    }

    /**
     * Low-level send. Returns true if the MTA accepted the message.
     * Sends multipart/alternative (plain + HTML) for good deliverability.
     */
    public function send(string $toEmail, string $subject, string $htmlBody, string $textBody = ''): bool
    {
        $toEmail = trim($toEmail);
        if ($toEmail === '' || !filter_var($toEmail, FILTER_VALIDATE_EMAIL)) {
            return false;
        }
        if ($textBody === '') {
            $textBody = trim(preg_replace('/\s+/', ' ', strip_tags($htmlBody)));
        }

        $boundary = 'b_' . bin2hex(random_bytes(12));
        $fromName = $this->encodeHeader($this->fromName);
        $from = "{$fromName} <{$this->fromEmail}>";

        $headers = [];
        $headers[] = 'MIME-Version: 1.0';
        $headers[] = "From: {$from}";
        $headers[] = "Reply-To: {$this->fromEmail}";
        $headers[] = 'X-Mailer: GoretoMailer';
        $headers[] = "Content-Type: multipart/alternative; boundary=\"{$boundary}\"";

        $eol = "\r\n";
        $body = '';
        $body .= "--{$boundary}{$eol}";
        $body .= "Content-Type: text/plain; charset=UTF-8{$eol}";
        $body .= "Content-Transfer-Encoding: 8bit{$eol}{$eol}";
        $body .= $textBody . $eol . $eol;
        $body .= "--{$boundary}{$eol}";
        $body .= "Content-Type: text/html; charset=UTF-8{$eol}";
        $body .= "Content-Transfer-Encoding: 8bit{$eol}{$eol}";
        $body .= $htmlBody . $eol . $eol;
        $body .= "--{$boundary}--{$eol}";

        // -f sets the envelope sender so Postfix uses our domain.
        $params = '-f' . $this->fromEmail;

        try {
            return @mail($toEmail, $this->encodeHeader($subject), $body, implode("\r\n", $headers), $params);
        } catch (\Throwable $e) {
            error_log('EmailHelper send error: ' . $e->getMessage());
            return false;
        }
    }

    /** Password-reset code email (used by api_password_reset.php). */
    public function sendPasswordReset(string $toEmail, string $code, string $name = ''): bool
    {
        $subject = 'Your Goreto password reset code';
        $html = $this->codeTemplate(
            $name,
            'Reset your password',
            'Use this code to reset your Goreto password. It expires in 15 minutes.',
            $code
        );
        return $this->send($toEmail, $subject, $html);
    }

    /** Generic OTP email (used for 2FA login). */
    public function sendOtp(string $toEmail, string $code, string $name = '', string $purpose = 'sign in'): bool
    {
        $subject = 'Your Goreto verification code';
        $html = $this->codeTemplate(
            $name,
            'Verification code',
            'Use this code to ' . htmlspecialchars($purpose) . '. It expires in 10 minutes. If this wasn\'t you, change your password.',
            $code
        );
        return $this->send($toEmail, $subject, $html);
    }

    private function codeTemplate(string $name, string $heading, string $intro, string $code): string
    {
        $greeting = trim($name) !== '' ? 'Hi ' . htmlspecialchars($name) . ',' : 'Hi,';
        $code = htmlspecialchars($code);
        $heading = htmlspecialchars($heading);
        $intro = $intro; // already escaped by callers where needed
        return <<<HTML
<!doctype html><html><body style="margin:0;background:#f5f5f7;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
  <div style="max-width:480px;margin:0 auto;padding:32px 24px;">
    <div style="background:#ffffff;border-radius:16px;padding:32px;border-top:4px solid #FF007F;">
      <h1 style="color:#FF007F;font-size:22px;margin:0 0 16px;">{$heading}</h1>
      <p style="color:#333;font-size:15px;line-height:1.5;margin:0 0 8px;">{$greeting}</p>
      <p style="color:#555;font-size:14px;line-height:1.6;margin:0 0 24px;">{$intro}</p>
      <div style="text-align:center;margin:24px 0;">
        <span style="display:inline-block;font-size:32px;font-weight:700;letter-spacing:8px;color:#111;background:#f0f0f3;border-radius:12px;padding:16px 24px;">{$code}</span>
      </div>
      <p style="color:#999;font-size:12px;line-height:1.5;margin:16px 0 0;">If you didn't request this, you can safely ignore this email.</p>
    </div>
    <p style="color:#aaa;font-size:11px;text-align:center;margin:16px 0 0;">GORETO · help@goreto.org</p>
  </div>
</body></html>
HTML;
    }

    private function encodeHeader(string $text): string
    {
        if (preg_match('/[^\x20-\x7E]/', $text)) {
            return '=?UTF-8?B?' . base64_encode($text) . '?=';
        }
        return $text;
    }
}
