<?php
header('Content-type: application/json');
include('get_auth_token.php');

$etcd_ch = setCurl();

// This module handles input requests pertaining to group or host primitives, or their inputs

// Read raw JSON input and decode
$rawInput       = file_get_contents('php://input');
if ($rawInput === false) {
	error_log("ERROR: Failed to read input");
	http_response_code(500);
	echo json_encode(["error" => "Failed to read input"]);
	exit;
}
$submissionData           = json_decode($rawInput, true);

if ($submissionData === null) {
	error_log("ERROR: Invalid JSON input: " . $rawInput);
	http_response_code(400);
	echo json_encode(["error" => "Invalid JSON input"]);
	exit;
}

$opData         = $submissionData ["data"] ?? null; // further data for suboperations and values etc.
$hashID         = $submissionData ["hash"] ?? null; // hash ID of the element, can be null in case of new group rq
$parentHash     = $submissionData ["parentHash"] ?? null; // the parent hash if needed
$operation      = $submissionData ["request"] ?? null; // operation we are performing on the element
$type           = $submissionData ["type"]; //  GROUP, HOST, INPUT, GLOBALS

$token          = get_etcd_auth_token();

// Debug logging - add this at the beginning to see all inputs
//error_log("SET_CONTROL: DEBUG: Received request - Type: " . $type . ", Operation: " . $operation . ", Data: " . $opData . ", HashID: " . $hashID);

function set_etcd($token, $keyPrefix, $keyValue): void
{
	$ch = setCurl();
	$headers = [
		"Authorization: $token",
		"Content-Type: application/json"
	];
    curl_setopt($ch, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_2_0);
    curl_setopt($ch, CURLOPT_URL, 'https://' . (HOST_NAME) . ':2379/v3/kv/put');
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$keyPrefix\", \"value\":\"$keyValue\"}");
//	error_log("SET_CONTROL: DEBUG: Attempting to write to ETCD: " . $keyPrefix . " With Value: " . $keyValue);
	curl_exec($ch);
	if (curl_errno($ch)) {
		http_response_code(500);
		echo json_encode(["error" => "Network error: " . curl_error($ch)]);
	} else {
        curl_reset($ch);
		$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
		if ($httpCode >= 400) {
			http_response_code($httpCode);
			echo json_encode(["error" => "etcd error: $httpCode"]);
		} else {
//			error_log("SET_CONTROL: DEBUG: Wrote: " . $keyPrefix . " With Value: " . $keyValue);
			echo json_encode([
				"success" => true,
//				"key" => $keyPrefix,
//				"value" => $keyValue
			]);
		}
	}
}

/**
 * Returns true if the value is a full sha256 hash (64 lowercase hex chars).
 * Groups and hosts are keyed by such hashes.
 */
function is_valid_hash($value): bool
{
    return is_string($value) && preg_match('/^[a-f0-9]{64}$/', $value) === 1;
}

/**
 * Input hashes are special: they may be the static placeholder options
 * 0 (black screen), 1 (static image), 2 (test card) OR a full sha256 hash
 * of a real input. Returns true for either.
 */
function is_valid_input_hash($value): bool
{
    return in_array($value, ['0', '1', '2'], true) || is_valid_hash($value);
}

/**
 * Rejects the request with a 400 if $value is not a full sha256 hash.
 * Used as a guard to prevent malformed/phantom hashes being written to etcd.
 */
function require_valid_hash($value): void
{
    if (!is_valid_hash($value)) {
        error_log("SET_CONTROL: ERROR: Rejecting write for invalid hash: " . var_export($value, true));
        http_response_code(400);
        echo json_encode(["error" => "Invalid hash: must be a full sha256 hash"]);
        exit;
    }
}

function validateValue($function, $value): void
{
	// Status suffix mappings: key => expected suffix
	$statusSuffixMap = array(
		"reboot" => "rebootStatus",
		"reveal" => "revealStatus",
		"reset" => "resetStatus",
	);
	// if we are writing to any of these keys, the value must be 0 or 1.
	$booleanFields  = array(
		"audioStatus",
		"bannerStatus",
		"blankStatus",
		"deprovision",
		"directMode",
		"livestreamStatus",
		"lowInformationMode",
		"persistInput",
		"promote",
		"reboot",
		"reset",
		"reveal",
		"UIEnable"
	);
	// Debug: Log validation attempt
//	error_log("SET_CONTROL: DEBUG: Validating function: " . $function . ", value: " . $value);
	// Check if this is one of the status fields that need suffix mapping
	$actualFunction = $function;
	foreach($statusSuffixMap as $baseKey => $statusKey) {
		if ($function === $statusKey) {
			$actualFunction = $baseKey;
			// Overwrite $function to the base value
			$function = $baseKey;
//			error_log("SET_CONTROL: DEBUG: Overwritten function to mapped base value: " . $function);
			break;
		}
	}
	// Check if the function name (or its mapped base) matches any boolean field
	$isBooleanField = false;
	foreach($booleanFields as $t)
	{
		if ($function === $t || $actualFunction === $t) {
			$isBooleanField = true;
			// Validate that value is 0 or 1
			if ($value !== "0" && $value !== "1") {
				error_log("ERROR: Control value must be 0 or 1 for: " . $function . " (got: " . $value . ")");
				http_response_code(400);
				echo json_encode(["error" => "Invalid value for boolean field " . $function . ": must be 0 or 1"]);
				return;
			}
			// If we reach here, it's a valid boolean field with valid value
			error_log("SUCCESS: Validated boolean field: " . $function . " with value: " . $value);
			return;
		}
	}
	if (!$isBooleanField) {
		error_log("ERROR: Control field does not appear to be valid: " . $function);
		http_response_code(400);
		echo json_encode(["error" => "Control field does not appear to be valid: " . $function]);
		exit;
	}
}

function checkImageData($imageData) {
	// Validate image data before storing
    $maxSize = 20 * 1024 * 1024; // 20MB
    if (strlen($imageData) > $maxSize) {
        error_log("ERROR: Image size exceeds 10MB");
        http_response_code(400);
        echo json_encode(["error" => "Image size exceeds 10MB"]);
        exit;
    }
	// MP4 check
	$header = substr($imageData, 0, 12);
	// MP4: size(4 bytes) + "ftyp" at offset 4
	if (substr($header, 4, 4) === "ftyp") {
		// Quick sanity: ensure first 4 bytes are a reasonable file size
		$sizeBytes = unpack("N", substr($header, 0, 4));
		if ($sizeBytes[1] > $maxSize || $sizeBytes[1] < 12) {
			error_log("ERROR: Invalid MP4 file size header");
			http_response_code(400);
			echo json_encode(["error" => "Invalid MP4 file"]);
			exit;
		}
		return 'mp4';
	}
	// Check for null bytes or control characters that might indicate malicious content
	if (strpos($imageData, "\0") !== false && substr($imageData, 0, 2) !== "\xFF\xD8" && substr($imageData, 0, 8) !== "\x89PNG\r\n\x1a\n") {
		error_log("ERROR: Suspicious null bytes detected in image data");
		http_response_code(400);
		echo json_encode(["error" => "Invalid image data"]);
		exit;
	}
	$size = getimagesizefromstring($imageData);
	if ($size === false) {
		error_log("ERROR: Invalid image format for staticImage");
		http_response_code(400);
		echo json_encode(["error" => "Unsupported image format"]);
		exit;
	}
	if ($size[0] > 1920 || $size[1] > 1080) {
		error_log("ERROR: Image dimensions exceed 1920x1080");
		http_response_code(400);
		echo json_encode(["error" => "Image dimensions exceed 1920x1080"]);
		exit;
	}
	$allowedMimeTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/avif'];
	if (!isset($size['mime']) || !in_array($size['mime'], $allowedMimeTypes)) {
		error_log("ERROR: Unsupported MIME type: " . $size['mime']);
		http_response_code(400);
		echo json_encode(["error" => "Unsupported image format: " . $size['mime']]);
		exit;
	} else {
		switch ($size['mime']) {
			case 'image/jpeg':
				$extension = 'jpg';
				break;
			case 'image/png':
				$extension = 'png';
				break;
			case 'image/gif':
				$extension = 'gif';
				break;
			case 'image/avif':
				$extension = 'avif';
				break;
			default:
				// This shouldn't happen since we already checked the MIME type
				$extension = '';
				error_log("ERROR: Unexpected MIME type: " . $size['mime']);
				http_response_code(400);
				echo json_encode(["error" => "Unsupported image format: " . $size['mime']]);
				exit;
		}
	}
	// Additional magic byte validation for common formats
	$header = substr($imageData, 0, 12);
	$validHeader = false;

	// PNG: \x89PNG\r\n\x1a\n
	if (substr($header, 0, 8) === "\x89PNG\r\n\x1a\n") {
		$validHeader = true;
	}
	// JPEG: \xFF\xD8\xFF
	elseif (substr($header, 0, 3) === "\xFF\xD8\xFF") {
		$validHeader = true;
	}
	// GIF: GIF87a or GIF89a
	elseif (substr($header, 0, 6) === "GIF87a" || substr($header, 0, 6) === "GIF89a") {
		$validHeader = true;
	}
	if (!$validHeader) {
		error_log("ERROR: Image header does not match declared MIME type");
		http_response_code(400);
		echo json_encode(["error" => "Image header validation failed"]);
		exit;
	}
	// Check aspect ratio sanity (optional - prevents extremely distorted images)
	$aspectRatio = $size[0] / $size[1];
	if ($aspectRatio < 0.1 || $aspectRatio > 10) {
		error_log("WARNING: Unusual aspect ratio: " . $aspectRatio);
	}
	return $extension;
}

switch ($type) {
	case 'GROUP':
//		error_log("SET_CONTROL: DEBUG: GROUP operation");
		switch ($operation) {
			case 'deleteGroup':
				// Asks Wavelet to delete the group
				// If the group is populated, all hosts will revert to the default/server group
//				error_log("SET_CONTROL: DEBUG: GROUP operation: deleteGroup:". $hashID);
				require_valid_hash($hashID);
				$prefixstring   =   "/UI/GLOBALS/control/GROUP-DELETE";
				$keyValue       =   $hashID;
				break;
			case 'GROUPCONTROL':
				$parts = explode(':', $opData, 3);
				// Debug: Log the parsed parts
//				error_log("SET_CONTROL: DEBUG: GROUPCONTROL parts: " . implode(", ", $parts));
				if (count($parts) < 2) {
					error_log("ERROR: Missing data in GROUPCONTROL");
					echo json_encode(["error" => "Missing data"]);
					return;
				}
				// `${controlKey}:${controlValue}:TOGGLE`;
				$subOperation = $parts[0];
				$dataValue    = $parts[1];
				$toggle      = $parts[2] ?? null; // This is a string literal "TOGGLE" to tell us it's a toggle value
				if ($hashID === null || $hashID === '') {
					error_log("ERROR: Missing hashID for GROUP control");
					http_response_code(400);
					echo json_encode(["error" => "Missing hashID"]);
					return;
				}
				// Guard: a group hash must always be a full sha256 hash. This
				// prevents phantom/malformed hashes (e.g. source values like
				// "1" or "2--2" used as group keys) from being written to etcd.
				require_valid_hash($hashID);
//				error_log("SET_CONTROL: DEBUG: GROUPCONTROL - subOperation: " . $subOperation . ", dataValue: " . $dataValue . ", toggle: " . $toggle);
				if ($toggle === "TOGGLE") {
					validateValue($parts[0], $parts[1]);
					$prefixstring	=	"/UI/GROUPS/" . $hashID . "/control/" . $parts[0];
					$keyValue = $dataValue;
				} else {
					# Guard against null hashID value being submitted for anything in this branch, noop.
					switch ($subOperation) {
						// These handle the non-boolean operations
						case 'chainedToGroup':
							// this key stores the hash of the target group, if this group of $hashID is chained
							$prefixstring = "/UI/GROUPS/$hashID/control/chainedToGroup";
							$keyValue = $dataValue;
							break;
						case 'changeBannerContent':
							// in this case, keyValue is a compound ${urlData};${apiKey}
							// The backend script expects this format and will fail if it is not correct
							$prefixstring = "/UI/GROUPS/$hashID/control/bannerContent";
							$keyValue = $dataValue;
							break;
						case 'changeBTMac':
							$prefixstring = "/UI/GROUPS/$hashID/control/blueToothMAC";
							$keyValue = $dataValue;
							break;
						case 'changeEncoderTimeout':
							// Validate that the value is an integer between 0 and 1440
							$validatedTimeout = filter_var($dataValue, FILTER_VALIDATE_INT, array("options" => array("min_range" => 0, "max_range" => 1440)));
							if ($validatedTimeout === false) {
								error_log("ERROR: Encoder timeout must be an integer between 0 and 1440 (got: " . var_export($dataValue, true) . ")");
								http_response_code(400);
								echo json_encode(["error" => "Invalid encoder timeout: must be an integer between 0 and 1440"]);
								return;
							}
							$prefixstring = "/UI/GROUPS/$hashID/control/encoderTimeout";
							$keyValue = $validatedTimeout;
							break;
						case 'changeGroupSource':
							$prefixstring = "/UI/GROUPS/$hashID/control/sourceHash";
							$keyValue = $dataValue;
							break;
						case 'changeGroupCodec':
							$prefixstring = "/UI/GROUPS/$hashID/control/activeCodec";
							$keyValue = $dataValue;
							break;
						case 'changeLiveStreamURL':
							// We now have a URL target key and an API key object
							$prefixstring = "/UI/GROUPS/$hashID/control/LiveStreamURL";
							$keyValue = $dataValue;
							break;
						case 'changeLiveStreamKey':
							// We now have a URL target key and an API key object
							$prefixstring = "/UI/GROUPS/$hashID/control/LiveStreamKey";
							$keyValue = $dataValue;
							break;
						case 'groupCreated':
							$prefixstring = "/UI/GROUPS/$hashID/control/newGroup";
							$keyValue = "0";
							break;
						case 'relabel':
							$prefixstring = "/UI/GROUPS/$hashID/control/label";
							$keyValue = $dataValue;
							break;
						case 'staticImage':
							// This will handle image binary data
							// It will enforce a 10mb (!) size limit, and ensure only image data are processed.
							$imageData = base64_decode($dataValue, true);
							$extension = checkImageData($imageData);
                            $imageDir = dirname(__FILE__) . '/data/';
							$userID = getmyuid();
							if ( !file_exists($imageDir) ) {
								mkdir ($imageDir, 0744);
							}
							// Explicit directory validation: fail safely if path doesn't exist
							if (!is_dir($imageDir)) {
								error_log("ERROR: Image storage directory missing: $imageDir");
								http_response_code(500);
								echo json_encode(["error" => "Image storage directory not configured"]);
								exit;
							}
                            $filename = uniqid('image_', true) . '.' . $extension;
                            $filePath = $imageDir . $filename;
							if (file_put_contents($filePath, $imageData) === false) {
								// Replace $userId with the actual User ID variable (e.g., $_SESSION['uid'], $userId, etc.)
								error_log("ERROR: Failed to save image for User ID: $userID, Path: $filePath");
								echo json_encode(["error" => "Failed to save image"]);
								exit;
							}
                            $prefixstring = "/UI/GROUPS/$hashID/control/staticImage";
                            $keyValue = $filename;
							break;
						case 'swatchValue':
							// validates and sets an RGBA swatch value
							$prefixstring = "/UI/GROUPS/$hashID/control/swatchValue";
							$keyValue = $dataValue;
							break;
						default:
							http_response_code(400);
							echo json_encode(["error" => "Bad subOperation for GROUPCONTROL: " . $subOperation]);
							return;
					}
				}
				break;
			default:
				http_response_code(400);
//				error_log("SET_CONTROL: DEBUG: ERROR: GROUP operation, default selector.");
				return;
		}
//		error_log("SET_CONTROL: DEBUG: Final attempting etcd write: " . $prefixstring . " with value: " . $keyValue);
		if (isset($prefixstring, $keyValue)) {
			$keyPrefix = base64_encode($prefixstring);
			$keyValue  = base64_encode($keyValue);
			// Debug: Log final etcd call
//			error_log("SET_CONTROL: DEBUG: Final GROUPCONTROL etcd call: " . $keyPrefix . " with value: " . $keyValue);
			set_etcd($token, $keyPrefix, $keyValue);
		}
		break;

	// Host operations
	case "HOST": {
		switch ($operation) {
			// Everything for hosts is "controls"
			case 'HOSTCONTROL':
				$parts = explode(':', $opData, 3);
				// Debug: Log the parsed parts
				error_log("DEBUG: HOSTCONTROL parts: " . implode(", ", $parts));
				if (count($parts) < 2) {
					error_log("ERROR: Missing data in HOSTCONTROL");
					echo json_encode(["error" => "Missing data"]);
					return;
				}
				// `${controlKey}:${controlValue}:TOGGLE`;
				$subOperation = $parts[0];
				$dataValue    = $parts[1];
				$toggle      = $parts[2] ?? null;
//				error_log("SET_CONTROL: DEBUG: HOSTCONTROL - subOperation: " . $subOperation . ", dataValue: " . $dataValue . ", toggle: " . $toggle);
				if ($hashID === null || $hashID === '') {
					error_log("ERROR: Missing hashID for HOST control");
					http_response_code(400);
					echo json_encode(["error" => "Missing hashID"]);
					return;
				}
				// Guard: host hashes must be full sha256 hashes.
				require_valid_hash($hashID);
				if ($toggle === "TOGGLE") {
					validateValue($parts[0], $parts[1]);
					$prefixstring	=	"/UI/HOSTS/" . $hashID . "/control/" . $parts[0];
					$keyValue = $dataValue;
				} else {
					switch ($subOperation) {
						case 'changeGroup':
							// We relabel the host
							$prefixstring = "/UI/HOSTS/$hashID/control/GROUP";
							$keyValue = $dataValue;
							break;
						case 'hostCreated':
							// Consumes the newHost flag
							$prefixstring = "/UI/HOSTS/$hashID/newHost";
							$keyValue = "0";
							break;
						case 'inputRelabel':
							// in opData payload we have the full semicolon delimited string of our input device:
							// I.E PARENT_HOSTNAME;DEVICE LABEL;DEVICE_FULLPATH:DEVICE_TYPE
							// I.E svr.wavelet.allethrium;IPEVO_Ziggi-HD_Plus:USB-14.0-5.4;/dev/video2/;HOST
							// I.E 192.168.1.3;NDI1231511Box;00:11:22:33:44;NDI
							// explode it
							if ($parentHash === null || $parentHash === '') {
								// Guard against malformed writes
								error_log("ERROR: Missing parentHash for inputRelabel");
								http_response_code(400);
								echo json_encode(["error" => "Missing parentHash"]);
								return;
							}
							// parentHash must be a host (full sha256 hash); hashID
							// is an input and may be a static option (0/1/2) or a
							// real input hash.
							require_valid_hash($parentHash);
							if (!is_valid_input_hash($hashID)) {
								error_log("SET_CONTROL: ERROR: Rejecting inputRelabel for invalid input hash: " . var_export($hashID, true));
								http_response_code(400);
								echo json_encode(["error" => "Invalid input hash"]);
								return;
							}
							$inputParts = explode(";", $dataValue);
							$parentHostName = $inputParts[0];
							$label = $inputParts[1];
							$inputPath = $inputParts[2];
							$inputType = $inputParts[3];
							// recombine and rewrite it
							$prefixstring = "/UI/HOSTS/$parentHash/inputs/$hashID";
							$keyValue = "$parentHostName;$label;$inputPath;$inputType";
							break;
						case 'relabel':
							// We relabel the host
							$prefixstring = "/UI/HOSTS/$hashID/control/label";
							$keyValue = $dataValue;
							break;
						default:
//							error_log("SET_CONTROL: DEBUG: Unknown HOST subOperation: " . $subOperation);
							// Don't write if nothing matched
							$prefixstring = null;
							$keyValue = null;
							break;
					}
				}
				break;
		}
		if (isset($prefixstring, $keyValue)) {
			$keyPrefix = base64_encode($prefixstring);
			$keyValue = base64_encode($keyValue);
			// Debug: Log final etcd call
//			error_log("SET_CONTROL: DEBUG: Final HOSTCONTROL etcd call: " . $prefixstring . " with value: " . $keyValue);
			set_etcd($token, $keyPrefix, $keyValue);
		}
		break;
	}
	case "GLOBALS":
		switch ($operation) {
			case 'createGroup':
				// Asks Wavelet to generate a new group with a random name
//				error_log("SET_CONTROL: DEBUG: GROUP operation: createGroup");
				$prefixstring   =   "/UI/GLOBALS/control/GROUP-CREATE";
				$keyValue       =   "PLEASE";
				break;
			case 'GLOBALSCONTROL':
				// Debug: Log incoming data
//				error_log("SET_CONTROL: DEBUG: GLOBALSCONTROL received - Operation: " . $operation . ", Data: " . $opData);
				$parts = explode(':', $opData, 3);
				// Debug: Log the parsed parts
//				error_log("SET_CONTROL: DEBUG: GLOBALSCONTROL parts: " . implode(", ", $parts));
				if (count($parts) < 2) {
					error_log("ERROR: Missing data in GLOBALSCONTROL");
					echo json_encode(["error" => "Missing data"]);
					return;
				}
				// `${controlKey}:${controlValue}:TOGGLE`;
				$subOperation = $parts[0];
				$dataValue    = $parts[1];
				$toggle      = $parts[2] ?? null;
//				error_log("SET_CONTROL:  GLOBALSCONTROL - subOperation: " . $subOperation . ", dataValue: " . $dataValue . ", toggle: " . $toggle);
				if ($toggle === "TOGGLE") {
					validateValue($parts[0], $parts[1]);
					$prefixstring	=	"/UI/GLOBALS/controls/" . $parts[0];
					$keyValue = $dataValue;
				} else {
					switch ($subOperation) {
						case 'relabel':
							// We can relabel the system header (EXAMPLE)
							$prefixstring = "/UI/GLOBALS/controls/relabel";
							$keyValue = $dataValue;
							break;
						default:
							// Debug: Log unknown subOperation
//							error_log("SET_CONTROL: DEBUG: Unknown subOperation in GLOBALS: " . $subOperation);
							break;
					}
				}
				break;
		}
//		error_log("SET_CONTROL: DEBUG: Final attempting etcd write: " . $prefixstring . " with value: " . $keyValue);
		if (isset($prefixstring, $keyValue)) {
			$keyPrefix = base64_encode($prefixstring);
			$keyValue = base64_encode($keyValue);
			// Debug: Log final etcd call
//			error_log("SET_CONTROL: DEBUG: Final GLOBALSCONTROL etcd call: " . $keyPrefix . " with value: " . $keyValue);
			set_etcd($token, $keyPrefix, $keyValue);
		}
		break;
	default:
		http_response_code(400);
		echo json_encode(["error" => "Unknown type: " . $type]);
		return;
}