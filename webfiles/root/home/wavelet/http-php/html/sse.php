<?php
while (ob_get_level()) {
    ob_end_clean();
}

// This prevents writing to the session
session_start();
session_write_close();
ignore_user_abort(false);
set_time_limit(0);
ini_set('max_execution_time', '0');
ini_set('default_socket_timeout', '0');
if (function_exists('apache_setenv')) {
    apache_setenv('no-gzip', '1');
}
ini_set('zlib.output_compression', 0);
ini_set('implicit_flush', 1);

// Include auth without output
ob_start();
include('get_auth_token.php');
ob_end_clean();

// Set SSE headers
header('Content-Type: text/event-stream');
header('Cache-Control: no-cache');
header('X-Accel-Buffering: no');
header('Connection: keep-alive');

// Send initial content to establish connection
echo ": SSE Connection Established\n\n";
flush();

if (!function_exists('setCurl')) {
    send_error_event("Function Error: setCurl() is missing - check get_auth_token.php");
    exit;
}

function send_sse_event($data, $event = null, $id = null): void
{
	if ($id !== null) {
		echo "id: $id\n";
	}
	if ($event !== null) {
		echo "event: $event\n";
	}
	echo "data: " . json_encode($data) . "\n\n";
	flush();
}

function send_error_event($message, $id = null): void
{
	send_sse_event([
		'error' => $message,
		'timestamp' => time()
	], 'error', $id);
}

// Add heartbeat function to detect disconnections
function send_heartbeat($id = null): bool
{
	if (connection_aborted()) {
		return false;
	}
	echo "event: heartbeat\n";
	if ($id !== null) {
		echo "id: $id\n";
	}
	echo "data: {\"time\": " . time() . ", \"server_time\": " . microtime(true) . "}\n\n";
	try {
		flush();
	} catch (Throwable $e) {
		error_log("Heartbeat flush error: " . $e->getMessage());
	}
	return !connection_aborted();
}

// Main function, which sets up an etcd watch on the /UI/ range
function poll_etcd($token): void
{
	if (empty($token)) {
		send_error_event("Authentication token is missing or invalid");
		return;
	}
	static $watchCounter = 0;
	if (isset($_SERVER['HTTP_LAST_EVENT_ID'])) {
		$lastEventId = (int)$_SERVER['HTTP_LAST_EVENT_ID'];
		if ($lastEventId < $watchCounter) {
			// Re-send missed events
			$recentEvents = get_events_after_id($lastEventId);
			foreach ($recentEvents as $event) {
				send_sse_event($event, 'etcd_update', $event['id']);
			}
		}
	}
	$lastHeartbeat = time();
	$startTime = time();
	$heartbeatInterval = 15;
	$heartbeatId = 0;
	if (connection_aborted()) {
		error_log("SSE client disconnected before watch setup");
		exit();
	}
    $ch = setCurl();
    $headers = [
        'Authorization: ' . $token,
        'Content-Type: application/json'
    ];
    // Set the etcd range start and end
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
    error_log("Setting up watch for key range: " . $targetKey . " to " . "${targetKey}0");
	curl_setopt($ch, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_2_0);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    curl_setopt($ch, CURLOPT_URL, 'https://' . (HOST_NAME) . ':2379/v3/watch');
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $postData);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, false);
    curl_setopt($ch, CURLOPT_TIMEOUT, 0);
    curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 10);
    $buffer = '';
    $max_execution_time =  9999;
    $timeout_triggered = false;
    curl_setopt($ch, CURLOPT_NOPROGRESS, false);
	curl_setopt($ch, CURLOPT_PROGRESSFUNCTION,
		function($resource, $download_size, $downloaded, $upload_size, $uploaded)
		use (&$startTime, $max_execution_time) {
			if (connection_aborted()) {
				error_log("ETCD Watch: Client disconnected (progress check)");
				return 1; // Abort the transfer
			}
			if ((time() - $startTime) > $max_execution_time) {
				error_log("ETCD Watch: Max execution time reached (progress check)");
				return 1; // Abort
			}
			return 0; // Continue transfer
		});
    curl_setopt($ch, CURLOPT_WRITEFUNCTION,
        function($ch, $data)
		use ($prefixRangeStart, &$buffer, &$watchCounter, &$lastHeartbeat, $heartbeatInterval, &$heartbeatId) {
            $dataLen = strlen($data);
            error_log("Received chunk, length: $dataLen bytes");
            $buffer .= $data;
            while (($pos = strpos($buffer, "\n")) !== false) {
                $line = substr($buffer, 0, $pos);
                $buffer = substr($buffer, $pos + 1);
                if (trim($line) === '') {
                    continue;
                }
                $dataArray = json_decode($line, true);
                if (json_last_error() !== JSON_ERROR_NONE) {
                    $errorMsg = "JSON Decode Error: " . json_last_error_msg();
                    error_log($errorMsg);
                    send_error_event($errorMsg);
                    continue;
                }
                if (isset($dataArray['error'])) {
                    $errorMsg = "etcd Error: " . json_encode($dataArray['error']);
                    error_log($errorMsg);
                    send_error_event($errorMsg);
                    continue;
                }
                if (isset($dataArray['result'])) {
                    $result = $dataArray['result'];
					// etcdv3 watch API uses "created" apparently
                    if (isset($result['canceled']) && $result['canceled'] === true) {
                        $cancelReason = $result['cancel_reason'] ?? 'Unknown reason';
                        error_log("Watch canceled: " . $cancelReason);
                        send_error_event("Watch canceled: " . $cancelReason);
                        return -1;
                    }
					if (isset($result['created']) && $result['created'] === true) {
						$watchCounter++;
						$watchInfo = [
							'status' => 'watching',
							'key' => base64_decode($prefixRangeStart),
							'watch_id' => $watchCounter,
							'header' => $result['header'] ?? null,
							'worker_pid' => getmypid()
						];
						error_log("Watch created successfully (PID: " . getmypid() . "): " . json_encode($watchInfo));
                        send_sse_event($watchInfo, 'watch_created');
                        continue;
                    }
                    if (isset($result['header']) && !isset($result['events']) && !isset($result['created'])) {
                        error_log("Watch progress notification received");
                        continue;
                    }
                    if (isset($result['events']) && is_array($result['events'])) {
                        $newData = [];
                        $eventType = "UPDATE";
                        foreach ($result['events'] as $event) {
                            //error_log("DEBUG: Event Data: " . json_encode($result['events']));
                            if (isset($event['type'])) {
                                $eventType = $event['type'];
                            }
                            if (isset($event['kv'])) {
                                $kv = $event['kv'];
                                $decodedKey = base64_decode($kv['key']);
                                $decodedValue = isset($kv['value']) ? base64_decode($kv['value']) : null;
                                $strippedKey = $decodedKey;
                                if (substr($strippedKey, 0, 4) === '/UI/') {
                                    $strippedKey = substr($strippedKey, 4);
                                }
                                if ($eventType === 'DELETE') {
                                    error_log("DEBUG: Processing deletion event for key: " . $strippedKey);
                                    // We know this is the only event with TYPE set
                                    $isTargetPath = false;
                                    $targetType = null;
                                    $parts = explode('/', $strippedKey);
                                    // Pattern matching for exact paths:
                                    // - HOSTS/HostHashID (exactly 2 parts after HOSTS)
                                    // - HOSTS/HostHashID/inputs/... (any inputs path under HOSTS)
                                    // - GROUPS/GroupHashID (exactly 2 parts after GROUPS)
                                    $parts = explode('/', $strippedKey);
                                    if (count($parts) >= 2) {
                                        $firstPart = $parts[0]; // Should be HOSTS or GROUPS
                                        if ($firstPart === 'GROUPS' && count($parts) === 2) {
                                            $isTargetPath = true;
                                            $targetType = 'GROUPS';
                                        } elseif ($firstPart === 'HOSTS') {
                                            if (count($parts) >= 3 && $parts[3] === 'inputs') {
                                                $isTargetPath = true;
                                                $targetType = 'HOSTS';
                                            } else {
                                                $isTargetPath = true;
                                                $targetType = 'INPUTS';
                                            }
                                        }
                                    }
                                    if ($isTargetPath) {
                                        $commonFields = [
                                            'key' => $strippedKey,
                                            'value' => $decodedValue,
                                            'event_type' => $eventType,
                                            'action' => 'delete'
                                        ];
                                        switch ($targetType) {
                                            case 'GROUPS':
                                                $newData[] = array_merge($commonFields, ['type' => 'group']);
                                                break;
                                            case 'HOSTS':
                                                $newData[] = array_merge($commonFields, ['type' => 'host']);
                                                break;
                                            case 'INPUTS':
                                                $newData[] = array_merge($commonFields, ['type' => 'input']);
                                                break;
                                            default:
                                                error_log("DEBUG: Unknown target type: $targetType");
                                                break;
                                        }
                                        error_log("DEBUG: Pushing DELETE event for key: $strippedKey");
                                    } else {
                                        error_log("DEBUG: Skipping non-target DELETE event: $strippedKey");
                                        continue;
                                    }
                                } else {
                                    $parts = explode('/', $strippedKey);
                                    $type = $parts[0] ?? null;
                                    // Determine if this is an inputs path
                                    $targetType = $type;
                                    if ($type === 'HOSTS' && count($parts) > 3 && $parts[3] === 'inputs') {
                                        $targetType = 'INPUTS';
                                    }
                                    $commonFields = [
                                        'key' => $strippedKey,
                                        'value' => $decodedValue,
                                        'event_type' => $eventType,
                                        'action' => 'update'
                                    ];
                                    $newData[] = match ($targetType) {
                                        'GROUPS' => array_merge($commonFields, ['type' => 'group']),
                                        'HOSTS' => array_merge($commonFields, ['type' => 'host']),
                                        'INPUTS' => array_merge($commonFields, ['type' => 'input']),
                                        default => array_merge($commonFields, ['type' => 'global']),
                                    };
                                    error_log("DEBUG: Pushing UPDATE event for type: $targetType");
                                }
                            } else {
                                error_log("DEBUG: Skipping event with unknown type: $eventType");
                                continue 2;
                            }
                        }
                        // Debug: Log the final data
                        error_log("Final newData count: " . count($newData));
                        if (!empty($newData)) {
                            error_log("Sending SSE event with " . count($newData) . " items");
                            send_sse_event($newData, 'etcd_update');
                        } else {
                            error_log("No data to send - empty newData array");
                        }
                    }
                }
            }
			if (connection_aborted()) return strlen($data);
			if (time() - $lastHeartbeat >= $heartbeatInterval) {
				if (!send_heartbeat($heartbeatId++)) {
					error_log("ETCD Watch: Client disconnected during heartbeat");
					return -1;
				}
				$lastHeartbeat = time();
			}
			return strlen($data);
        });
    error_log("Starting cURL execution for watch");
    $result = curl_exec($ch);
    if ($timeout_triggered) {
        // Max execution time was reached
        error_log("Watch ended due to timeout");
        if (!connection_aborted()) {
            send_sse_event(['status' => 'timeout', 'action' => 'reconnect'], 'timeout');
        }
    } elseif ($result === false) {
        $curlError = curl_error($ch);
        error_log("cURL Error: " . $curlError);
        if (!connection_aborted()) {
            send_error_event("cURL Error: " . $curlError);
        }
    } else {
        error_log("Watch connection closed normally");
        if (!connection_aborted()) {
            send_sse_event(['status' => 'connection_closed', 'action' => 'reconnect'], 'reconnect');
        }
    }
    error_log("Watch cleanup complete (PID: " . getmypid() . ")");
}

try {
    // Connectivity test to etcd cluster
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, 'https://' . (HOST_NAME) . ':2379/health');
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 5);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
    $healthCheck = curl_exec($ch);
    if ($healthCheck === false) {
        send_error_event("Connection Test Failed: Could not reach etcd server - " . curl_error($ch));
        exit;
    }
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    if ($httpCode !== 200) {
        send_error_event("Connection Test Failed: HTTP $httpCode - Response: " . substr($healthCheck, 0, 200));
        exit;
    }
    send_sse_event(['status' => 'health_check_passed'], 'health');
} catch (Exception $e) {
    send_error_event("Connection Test Exception: " . $e->getMessage());
    exit;
}

$token = get_etcd_auth_token();
poll_etcd($token);