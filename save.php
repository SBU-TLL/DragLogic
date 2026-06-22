<?php
// Append a saved proof to record.json (one JSON object per line).
//
// This is the app's only server-side endpoint. The app itself is a static,
// client-side tool (normally served from GitHub Pages) with no authentication,
// so these writes are best-effort research telemetry — there is no user to
// authenticate. Hardened to keep it from being a trivial abuse vector:
//   - POST only
//   - payload size-capped (legit proofs are a few KB)
//   - must be well-formed JSON, so the log can't be poisoned with arbitrary bytes
// NOTE for production/Azure: if this telemetry is kept, put it behind auth or
// rate-limiting and ensure record.json lives on writable, non-web-served storage.

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    http_response_code(405);
    exit;
}

$data = $_POST['data'] ?? '';
if ($data === '' || strlen($data) > 1048576) { // reject empty or > 1 MB
    http_response_code(400);
    exit;
}
json_decode($data);
if (json_last_error() !== JSON_ERROR_NONE) {
    http_response_code(400);
    exit;
}

file_put_contents(__DIR__ . '/record.json', $data . "\n", FILE_APPEND | LOCK_EX);
