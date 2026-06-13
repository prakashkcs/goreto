# Goreto Backend (PHP)

Source snapshot of the production backend that runs on the VPS at
`/var/www/html/ekloadmin`. Mirrored here for version control.

## Layout
- `api/v1/` — REST + cron endpoints used by the Flutter app
- `admin/`  — admin panel (moderation, KYC, settings, NSFW review, etc.)
- root `*.php` — entry shims

## Secrets (NOT in this repo)
All credentials live **only on the server**, outside version control:
- `config/config.php` — DB host/user/pass/name + base URL (gitignored)
- `service_account.json` — Firebase (kept in `/var/www/private/`)
- API keys (Bunny CDN, Agora, OneSignal, IAP) — stored in the DB `app_settings`
  table and the admin panel, not hardcoded.
- Admin logins — hashed in the `admin_users` table.

To run a copy, create `config/config.php` returning
`['db' => ['host'=>, 'name'=>, 'user'=>, 'pass'=>], 'base_url' => ...]`.
