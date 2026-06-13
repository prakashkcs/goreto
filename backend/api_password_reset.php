<?php
// Compatibility shim: the app (current builds) posts password-reset
// requests to /ekloadmin/api_password_reset.php, but the real handler
// lives in api/v1/. Forward to it. __DIR__ inside the target resolves
// to api/v1/, so its relative requires still work.
require __DIR__ . '/api/v1/api_password_reset.php';
