<?php
// Compatibility shim: app posts stories to /ekloadmin/stories.php but the
// handler lives in api/v1/. __DIR__ inside the target resolves to api/v1/.
require __DIR__ . '/api/v1/stories.php';
