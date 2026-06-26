<?php
// Etcd Watcher CLI Daemon
// Maintains persistent etcd watch on /UI/ prefix
// Publishes processed events to Redis stream "etcd:raw:stream"

while (ob_get_level()) {
    ob_end_clean();
}

set_time_limit(0);

include('get_auth_token.php');

// Redis connection parameters
$redisHost = 'localhost';
$redisPort = 6379;
$redisPassword = trim(file_get_contents('/run/secrets/redispw'));
$redisStream = 'etcd:raw:stream';
$redisDb = 2;

// Process etcd events and push to Redis stream
function process_events($events, $watchCounter, $redisClient, $redisStream): int {
    // processes raw etcd events into a JSON format which the frontend can more readily understand
    $newData = [];
    foreach ($events as $event) {
        if (!isset($event['kv'])) {
            continue;
        }
        $kv = $event['kv'];
        $eventType = $event['type'] ?? 'UPDATE';
        $decodedKey = base64_decode($kv['key']);
        $decodedValue = isset($kv['value']) ? base64_decode($kv['value']) : null;
        // Strip /UI/ prefix
        $strippedKey = $decodedKey;
        if (str_starts_with($strippedKey, '/UI/')) {
            $strippedKey = substr($strippedKey, 4);
        }
        // Classify event type for frontend
        $parts = explode('/', $strippedKey);
        $type = $parts[0] ?? null;
        $targetType = $type;
        if ($type === 'HOSTS' && count($parts) > 3 && $parts[3] === 'inputs') {
            $targetType = 'INPUTS';
        }
        $action = ($eventType === 'DELETE') ? 'delete' : 'update';
        $newData[] = [
            'id' => $watchCounter++,
            'key' => $strippedKey,
            'value' => $decodedValue,
            'event_type' => $eventType,
            'action' => $action,
            'type' => match ($targetType) {
                'GROUPS' => 'group',
                'HOSTS' => 'host',
                'INPUTS' => 'input',
                default => 'global',
            },
            'revision' => $kv['mod_revision'] ?? null,
            'timestamp' => time(),
        ];
    }

    if (!empty($newData)) {
        $redisClient->xAdd($redisStream, '*', ['data' => json_encode($newData)]);
        error_log("ETCD_WATCH: Pushed " . count($newData) . " events to Redis stream '$redisStream'");
    }
    return $watchCounter;
}

// Main etcd watch loop
function run_watch($token, $redisClient, $redisStream): bool {
    if (empty($token)) {
        error_log("ETCD_WATCH: ERROR: Authentication token is missing or invalid");
        return false;
    }
    $watchCounter = 0;
    $targetKey = "/UI/";
    $prefixRangeStart = base64_encode($targetKey);
    $prefixRangeEnd = base64_encode(get_prefix_range_end($targetKey));
    $postData = json_encode([
        "create_request" => [
            "key" => $prefixRangeStart,
            "range_end" => $prefixRangeEnd,
            "progress_notify" => true
        ]
    ]);
    $ch = curl_init();
    $headers = [
        'Authorization: ' . $token,
        'Content-Type: application/json',
    ];

    curl_setopt_array($ch, [
        CURLOPT_URL            => 'https://' . HOST_NAME . ':2379/v3/watch',
        CURLOPT_HTTPHEADER     => $headers,
        CURLOPT_POST           => true,
        CURLOPT_POSTFIELDS     => $postData,
        CURLOPT_RETURNTRANSFER => false,
        CURLOPT_SSL_VERIFYPEER => false,
        CURLOPT_SSL_VERIFYHOST => false,
        CURLOPT_CONNECTTIMEOUT => 3,
        CURLOPT_HTTP_VERSION   => CURL_HTTP_VERSION_2_0,
    ]);

    $buffer = '';

    curl_setopt($ch, CURLOPT_WRITEFUNCTION, function($ch, $data) use ($prefixRangeStart, &$buffer, &$watchCounter, $redisClient, $redisStream) {
        $buffer .= $data;
        while (($pos = strpos($buffer, "\n")) !== false) {
            $line = substr($buffer, 0, $pos);
            $buffer = substr($buffer, $pos + 1);

            if (trim($line) === '') {
                continue;
            }
            $dataArray = json_decode($line, true);
            if (json_last_error() !== JSON_ERROR_NONE) {
                error_log("ETCD_WATCH: JSON Decode Error: " . json_last_error_msg());
                continue;
            }
            if (isset($dataArray['error'])) {
                error_log("etcd Error: " . json_encode($dataArray['error']));
                continue;
            }
            if (!isset($dataArray['result'])) {
                continue;
            }
            $result = $dataArray['result'];
            // Watch canceled
            if (isset($result['canceled']) && $result['canceled'] === true) {
                $cancelReason = $result['cancel_reason'] ?? 'Unknown reason';
                error_log("ETCD_WATCH: Watch canceled: " . $cancelReason);
                return -1;
            }
            // Watch created
            if (isset($result['created']) && $result['created'] === true) {
                $watchCounter++;
                error_log("ETCD_WATCH: Watch created successfully (watch_id: $watchCounter)");
                continue;
            }
            // Progress notify - just continue
            if (isset($result['header']) && !isset($result['events']) && !isset($result['created'])) {
                error_log("ETCD_WATCH: ETCD watch progress notify received..");
                continue;
            }
            // Process events
            if (isset($result['events']) && is_array($result['events'])) {
                error_log("ETCD_WATCH: Processing raw etcd event..");
                $watchCounter = process_events($result['events'], $watchCounter, $redisClient, $redisStream);
            }
        }
        return strlen($data);
    });
    error_log("ETCD_WATCH: Starting etcd watch for key range: $targetKey");
    $result = curl_exec($ch);
    $curlError = curl_error($ch);
    if ($result === false) {
        error_log("cURL Error: " . $curlError);
        return false;
    }
    error_log("ETCD_WATCH: Watch connection closed normally");
    return false;
}

// Main daemon

error_log("ETCD_WATCH: Starting etcd watcher daemon (PID: " . getmypid() . ")");

// Health check
if (etcd_healthCheck()) {
    error_log("ETCD_WATCH: ERROR: etcd health check failed");
    exit(1);
}
error_log("ETCD_WATCH: etcd health check passed");

// Connect to Redis (publisher only - etcd_watch only publishes)
error_log("ETCD_WATCH: Redis connection activation..");
error_log("ETCD_WATCH: Host: " . $redisHost);
error_log("ETCD_WATCH: Port: " . $redisPort);
error_log("ETCD_WATCH: DB: " . $redisDb);
$redisClient = new Redis;

$redisClient->connect($redisHost, $redisPort);
if ($redisPassword) {
    $redisClient->auth($redisPassword);
}

if ($redisClient->ping()) {
    error_log("ETCD_WATCH: Redis connected successfully: PONG\n");
} else {
    error_log("ETCD_WATCH: Redis connection failed");
    exit(1);
}

$redisClient->select($redisDb);
// Ensure the stream exists
// Old: $redisClient->xAdd($redisStream, '*', ['data' => '[]'], ['MAXLEN', '~', 0]);
$redisClient->xAdd($redisStream, '*', ['data' => '[]'], 0, true);
error_log("ETCD_WATCH: Stream '$redisStream' ready");
// Get etcd auth token
$token = get_etcd_auth_token();
if ($token === false) {
    error_log("ETCD_WATCH: ERROR: NO AUTH TOKEN!");
}
// Watch loop with reconnection
$maxRetries = 32;
$retryCount = 0;
$baseDelay = 1;

while (true) {
    $watched = run_watch($token, $redisClient, $redisStream);
    if ($watched) {
        $retryCount = 0;
        continue;
    }
    // Connection lost, reconnect with backoff
    $retryCount++;
    if ($retryCount > $maxRetries) {
        error_log("ETCD_WATCH: ERROR: Max retries ($maxRetries) exceeded, giving up");
        exit(1);
    }
    $delay = min($baseDelay * pow(2, $retryCount - 1), 60);
    error_log("ETCD_WATCH: Watch connection lost, reconnecting in: $delay seconds. (attempt $retryCount/$maxRetries)");
    sleep($delay);
    // Reconnect Redis if needed
    if ($redisClient->ping()) {
        continue;
    } else {
        error_log("ETCD_WATCH: Redis connection lost, reconnecting..");
        $redisClient->connect($redisHost, $redisPort);
    }
}
