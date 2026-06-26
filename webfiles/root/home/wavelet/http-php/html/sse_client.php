<?php
// SSE Client - reads from Redis stream and forwards events to connected browser clients
// Called per-request by PHP-FPM via nginx
// Supports event replay via Last-Event-ID header
// Uses XREAD for fan-out: every client receives every event
// SSE IDs are Redis stream IDs, enabling replay from any point in the stream

// Clear any output buffering
while (ob_get_level()) {
    ob_end_clean();
}

// Don't timeout, continue on client disconnect
set_time_limit(0);
ignore_user_abort(true);

// Configuration
$redisHost = '127.0.0.1';
$redisPort = 6379;
$redisPassword = trim(file_get_contents('/run/secrets/redispw'));
$redisStream = 'etcd:raw:stream';
$redisDb = 2;

// Logging helper
function log_msg($msg): void {
    error_log("sse_client[getmypid()]: $msg");
}

// Event buffer for replay - keep last N events per connection
$MAX_BUFFER = 256;
$eventBuffer = [];

// Send SSE-formatted data
function send_sse_event($data, $event = null, $id = null): void {
    if ($id !== null) {
        echo "id: {$id}\n";
    }
    if ($event !== null) {
        echo "event: {$event}\n";
    }
    echo "data: " . json_encode($data) . "\n\n";
    flush();
}

// Buffer an event for replay
function buffer_event($event, $eventId): void {
    global $eventBuffer, $MAX_BUFFER;
    $event['id'] = $eventId;
    $eventBuffer[] = $event;
    if (count($eventBuffer) > $MAX_BUFFER) {
        array_shift($eventBuffer);
    }
}

// Send SSE headers
header('Content-Type: text/event-stream');
header('Cache-Control: no-cache');
header('Connection: keep-alive');
header('X-Accel-Buffering: no');

// Connect to Redis
$redisSock = new Redis;
$redisSock->connect($redisHost, $redisPort);
if ($redisPassword) {
    $redisSock->auth($redisPassword);
}
$redisSock->select($redisDb);
log_msg("Connected to Redis at {$redisHost}:{$redisPort}");

// Get Last-Event-ID from request — this is a Redis stream ID from a previous connection
$lastId = '0-0';
if (isset($_SERVER['HTTP_LAST_EVENT_ID'])) {
    $lastId = $_SERVER['HTTP_LAST_EVENT_ID'];
    log_msg("Client requested replay from stream ID {$lastId}");
}

// Send initial connection event
send_sse_event(['status' => 'connected'], 'connected');

// Replay missed events from Redis stream, then supplement with in-memory buffer
if (isset($_SERVER['HTTP_LAST_EVENT_ID']) && $_SERVER['HTTP_LAST_EVENT_ID'] !== '0-0') {
    $lastEventId = $_SERVER['HTTP_LAST_EVENT_ID'];
    log_msg("Replaying missed events from {$lastEventId}");
    // Query Redis for missed events
    $redisMissed = $redisSock->xReadRange($redisStream, '(' . $lastEventId, '+', ['count' => 1000]);
    $replayedCount = 0;
    if ($redisMissed !== false && isset($redisMissed[$redisStream])) {
        foreach ($redisMissed[$redisStream] as $eventId => $eventData) {
            $data = json_decode($eventData['data'], true);
            if ($data === null) {
                continue;
            }
            if (!is_array($data) || isset($data[0]) === false) {
                $data = [$data];
            }
            $batch = [];
            foreach ($data as $event) {
                buffer_event($event, $eventId);
                $batch[] = $event;
            }
            if (!empty($batch)) {
                send_sse_event($batch, 'etcd_update');
                $replayedCount++;
            }
        }
    }

    // Supplement with in-memory buffer for events sent during this connection before disconnect
    foreach ($eventBuffer as $event) {
        if (isset($event['id']) && $event['id'] > $lastEventId) {
            send_sse_event($event, 'etcd_update');
            $replayedCount++;
        }
    }
    log_msg("Replayed {$replayedCount} missed events to client");
}

// Event loop
$lastHeartbeat = time();
$heartbeatId = 0;
$heartbeatInterval = 15;

while (true) {
    // Check if client disconnected
    if (connection_aborted()) {
        log_msg("Client disconnected");
        break;
    }

    // Send heartbeat if needed
    if (time() - $lastHeartbeat >= $heartbeatInterval) {
        $heartbeatId++;
        echo "event: heartbeat\n";
        echo "id: {$heartbeatId}\n";
        echo "data: {\"time\": " . time() . ", \"server_time\": " . microtime(true) . "}\n\n";
        flush();
        $lastHeartbeat = time();
    }

    // Read from stream (fan-out: every client gets every message)
    $result = $redisSock->xRead([$redisStream => $lastId], 5000, 100);

    if ($result === false) {
        // Redis error — reconnect
        $lastError = $redisSock->getLastError();
        $redisSock->close();
        $redisSock->connect($redisHost, $redisPort);
        if ($redisPassword) {
            $redisSock->auth($redisPassword);
        }
        $redisSock->select($redisDb);
        log_msg("Reconnected to Redis after error: " . $lastError);
        sleep(1);
        continue;
    }

    if ($result === null) {
        // Timeout — no data yet, continue loop
        continue;
    }

    if (isset($result[$redisStream])) {
        foreach ($result[$redisStream] as $eventId => $eventData) {
            // Track last read ID for next iteration
            $lastId = $eventId;
            $data = json_decode($eventData['data'], true);
            if ($data === null) {
                log_msg("WARNING: Failed to decode event from stream");
                continue;
            }

            // Ensure data is an array (batch)
            if (!is_array($data) || isset($data[0]) === false) {
                $data = [$data];
            }

            // Buffer all events and collect valid ones
            $batch = [];
            foreach ($data as $event) {
                buffer_event($event, $eventId);
                $batch[] = $event;
            }

            // Send as a single batched array (no SSE id, matching old client format)
            if (!empty($batch)) {
                send_sse_event($batch, 'etcd_update');
            }
        }
    }
}

log_msg("SSE connection closed");
