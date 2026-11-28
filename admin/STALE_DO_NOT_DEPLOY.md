# This folder is stale — do not deploy from it

The live admin panel (`/var/www/html/ekloadmin/admin` on the server) matches
**`backend/admin/`**, not this folder. Several files here are older versions
(users.php, posts.php, sound_reports.php differ, and `_cascade.php` is missing),
so deploying them would undo fixes.

Edit and deploy admin files from `backend/admin/` only.
(Found during the reference-integrity audit, 2026-11-28.)
