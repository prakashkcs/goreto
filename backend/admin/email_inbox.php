<?php
require_once __DIR__ . '/_core.php';
admin_require_login();

$pageTitle  = 'Email Inbox';
$activeNav  = 'email_inbox';

// IMAP connection config — goreto.org mail is hosted on Google Workspace
define('IMAP_HOST',     'imap.gmail.com');
define('IMAP_PORT',     993);
define('IMAP_USER',     'help@goreto.org');
define('IMAP_PASS',     'EkloHelp2024!');
define('IMAP_MAILBOX',  '{' . IMAP_HOST . ':' . IMAP_PORT . '/imap/ssl}INBOX');

$error   = '';
$emails  = [];
$total   = 0;
$page    = max(1, (int) ($_GET['p'] ?? 1));
$perPage = 25;
$viewUid = isset($_GET['uid']) ? (int) $_GET['uid'] : 0;
$emailBody = '';
$emailMeta = [];

if (!extension_loaded('imap')) {
    $error = 'PHP IMAP extension is not available on this server.';
} else {
    $mbox = @imap_open(IMAP_MAILBOX, IMAP_USER, IMAP_PASS, 0, 1, ['DISABLE_AUTHENTICATOR' => 'GSSAPI']);
    if (!$mbox) {
        $error = 'Could not connect to mail server: ' . imap_last_error();
    } else {
        $total  = imap_num_msg($mbox);
        $start  = max(1, $total - ($page - 1) * $perPage);
        $end    = max(1, $start - $perPage + 1);
        $ids    = ($total > 0) ? range($start, $end) : [];

        foreach ($ids as $id) {
            $h = imap_headerinfo($mbox, $id);
            if (!$h) continue;
            $from    = isset($h->from[0]) ? ($h->from[0]->personal ?? '') . ' <' . ($h->from[0]->mailbox ?? '') . '@' . ($h->from[0]->host ?? '') . '>' : 'Unknown';
            $subject = isset($h->subject) ? imap_utf8($h->subject) : '(No subject)';
            $uid     = imap_uid($mbox, $id);
            $emails[] = [
                'id'      => $id,
                'uid'     => $uid,
                'from'    => trim($from),
                'subject' => $subject,
                'date'    => $h->date ?? '',
                'seen'    => strpos($h->Unseen ?? 'U', 'U') === false,
            ];
        }

        if ($viewUid > 0) {
            $msgId = imap_msgno($mbox, $viewUid);
            if ($msgId > 0) {
                $h = imap_headerinfo($mbox, $msgId);
                $emailMeta = [
                    'from'    => isset($h->from[0]) ? imap_utf8(($h->from[0]->personal ?? '') . ' <' . ($h->from[0]->mailbox ?? '') . '@' . ($h->from[0]->host ?? '') . '>') : '',
                    'to'      => isset($h->to[0]) ? ($h->to[0]->mailbox ?? '') . '@' . ($h->to[0]->host ?? '') : '',
                    'subject' => isset($h->subject) ? imap_utf8($h->subject) : '(No subject)',
                    'date'    => $h->date ?? '',
                ];
                $structure = imap_fetchstructure($mbox, $msgId);
                $emailBody = fetch_body($mbox, $msgId, $structure);
                imap_setflag_full($mbox, (string)$viewUid, '\\Seen', ST_UID);
            }
        }

        imap_close($mbox);
    }
}

// ── Recursively extract best body part ───────────────────────────────────────
function fetch_body($mbox, $msgId, $structure, $partNum = null)
{
    $html  = '';
    $plain = '';

    if (!empty($structure->parts)) {
        foreach ($structure->parts as $idx => $part) {
            $num = $partNum ? $partNum . '.' . ($idx + 1) : (string)($idx + 1);
            [$h2, $p2] = extract_part($mbox, $msgId, $part, $num);
            if ($h2) $html  = $h2;
            if ($p2) $plain = $p2;
        }
    } else {
        [$html, $plain] = extract_part($mbox, $msgId, $structure, $partNum ?? '1');
    }

    if ($html)  return $html;
    if ($plain) return '<pre style="white-space:pre-wrap;font-family:inherit">' . htmlspecialchars($plain) . '</pre>';
    return '<em>No readable content.</em>';
}

function extract_part($mbox, $msgId, $part, $partNum)
{
    $html  = '';
    $plain = '';
    $subtype = strtolower($part->subtype ?? '');
    $type    = $part->type ?? 0;

    if ($type === TYPETEXT) {
        $data = imap_fetchbody($mbox, $msgId, $partNum);
        $enc  = $part->encoding ?? ENC7BIT;
        if ($enc === ENCBASE64)            $data = base64_decode($data);
        elseif ($enc === ENCQUOTEDPRINTABLE) $data = quoted_printable_decode($data);

        $charset = 'UTF-8';
        if (!empty($part->parameters)) {
            foreach ($part->parameters as $p) {
                if (strtolower($p->attribute) === 'charset') { $charset = $p->value; break; }
            }
        }
        if (strtolower($charset) !== 'utf-8') {
            $data = mb_convert_encoding($data, 'UTF-8', $charset);
        }

        if ($subtype === 'html')  $html  = $data;
        else                      $plain = $data;
    }

    if (!empty($part->parts)) {
        foreach ($part->parts as $idx => $subpart) {
            $num = $partNum . '.' . ($idx + 1);
            [$h2, $p2] = extract_part($mbox, $msgId, $subpart, $num);
            if ($h2) $html  = $h2;
            if ($p2) $plain = $p2;
        }
    }

    return [$html, $plain];
}

$pages = $total > 0 ? (int) ceil($total / $perPage) : 1;

require_once __DIR__ . '/_layout_header.php';
?>

<main class="main-content">
  <div class="page-header">
    <h1 class="page-title">Email Inbox</h1>
    <p class="page-subtitle">help@goreto.org · <?= $total ?> message<?= $total !== 1 ? 's' : '' ?></p>
  </div>

<?php if ($error): ?>
  <div class="alert alert-danger" style="padding:16px;background:#2a1218;border:1px solid #7f1d1d;border-radius:8px;color:#fca5a5;margin-bottom:24px">
    <?= htmlspecialchars($error) ?>
  </div>
<?php endif; ?>

<?php if ($viewUid > 0 && !$error): ?>
  <!-- ── Single email view ── -->
  <div class="card" style="margin-bottom:24px">
    <div class="card-body" style="padding:24px">
      <a href="email_inbox.php?p=<?= $page ?>" style="color:#a78bfa;text-decoration:none;font-size:13px">← Back to inbox</a>
      <table style="margin:20px 0;width:100%;border-collapse:collapse;font-size:14px;color:#e2e8f0">
        <tr><td style="padding:4px 12px 4px 0;color:#94a3b8;white-space:nowrap">From</td><td><?= htmlspecialchars($emailMeta['from'] ?? '') ?></td></tr>
        <tr><td style="padding:4px 12px 4px 0;color:#94a3b8">To</td><td><?= htmlspecialchars($emailMeta['to'] ?? '') ?></td></tr>
        <tr><td style="padding:4px 12px 4px 0;color:#94a3b8">Subject</td><td><strong><?= htmlspecialchars($emailMeta['subject'] ?? '') ?></strong></td></tr>
        <tr><td style="padding:4px 12px 4px 0;color:#94a3b8">Date</td><td><?= htmlspecialchars($emailMeta['date'] ?? '') ?></td></tr>
      </table>
      <hr style="border-color:#2d2d3d;margin:0 0 20px">
      <div style="background:#0d0b14;border-radius:8px;padding:20px;min-height:200px">
        <iframe id="emailFrame" srcdoc="" style="width:100%;min-height:500px;border:none;background:#fff;border-radius:6px"></iframe>
        <script>
          (function(){
            var raw = <?= json_encode($emailBody) ?>;
            var frame = document.getElementById('emailFrame');
            frame.srcdoc = raw;
          })();
        </script>
      </div>
    </div>
  </div>
<?php elseif (!$error): ?>
  <!-- ── Inbox list ── -->
  <div class="card">
    <div class="card-body" style="padding:0">
      <?php if (empty($emails)): ?>
        <p style="padding:32px;text-align:center;color:#64748b">No messages in inbox.</p>
      <?php else: ?>
        <table style="width:100%;border-collapse:collapse;font-size:14px">
          <thead>
            <tr style="border-bottom:1px solid #1e1b2e;color:#94a3b8;font-size:12px;text-transform:uppercase">
              <th style="padding:12px 20px;text-align:left;font-weight:500">From</th>
              <th style="padding:12px 20px;text-align:left;font-weight:500">Subject</th>
              <th style="padding:12px 20px;text-align:left;font-weight:500;white-space:nowrap">Date</th>
            </tr>
          </thead>
          <tbody>
            <?php foreach ($emails as $em): ?>
              <tr style="border-bottom:1px solid #1e1b2e;<?= !$em['seen'] ? 'background:#13102a' : '' ?>">
                <td style="padding:12px 20px;color:#e2e8f0;white-space:nowrap;max-width:220px;overflow:hidden;text-overflow:ellipsis">
                  <?php if (!$em['seen']): ?><span style="display:inline-block;width:7px;height:7px;background:#a78bfa;border-radius:50%;margin-right:6px;vertical-align:middle"></span><?php endif; ?>
                  <?= htmlspecialchars($em['from']) ?>
                </td>
                <td style="padding:12px 20px">
                  <a href="email_inbox.php?uid=<?= $em['uid'] ?>&p=<?= $page ?>" style="color:<?= !$em['seen'] ? '#f1f5f9' : '#94a3b8' ?>;text-decoration:none;font-weight:<?= !$em['seen'] ? '600' : '400' ?>">
                    <?= htmlspecialchars($em['subject']) ?>
                  </a>
                </td>
                <td style="padding:12px 20px;color:#64748b;white-space:nowrap;font-size:12px"><?= htmlspecialchars($em['date']) ?></td>
              </tr>
            <?php endforeach; ?>
          </tbody>
        </table>
      <?php endif; ?>
    </div>
  </div>

  <?php if ($pages > 1): ?>
  <div style="display:flex;gap:8px;justify-content:center;margin-top:20px">
    <?php for ($i = 1; $i <= $pages; $i++): ?>
      <a href="email_inbox.php?p=<?= $i ?>" style="padding:6px 14px;border-radius:6px;font-size:13px;text-decoration:none;background:<?= $i === $page ? '#7c3aed' : '#1e1b2e' ?>;color:<?= $i === $page ? '#fff' : '#94a3b8' ?>"><?= $i ?></a>
    <?php endfor; ?>
  </div>
  <?php endif; ?>
<?php endif; ?>

</main>

<?php require_once __DIR__ . '/_layout_footer.php'; ?>
