<?php
// Includes on every PHP module which interacts with etcd
// Defines common parameters they may need
// Also contains some other common QoL functions
// Grabs an auth token based on the password string set during server spinup in NGINX config

if (!defined('HOST_NAME')) {
	define('HOST_NAME', getenv('HOST_MACHINE_HOSTNAME'));
}

define('CACERT', '/usr/local/share/ca-certificates/ca.crt');
// Check if CA certificate exists
if (!file_exists(CACERT)) {
	echo "CA Certificate not found at: (CACERT)";
}

function setCurl(): CurlHandle|false
{
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_URL, 'https://' . (HOST_NAME) . ':2379/v3/auth/authenticate');
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
	curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'POST');
	curl_setopt($ch, CURLOPT_POST, 1);
	curl_setopt($ch, CURLOPT_CAINFO, (CACERT));
	curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
	curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 2);
	return $ch;
}

function get_etcd_authtoken($username, $password) {
	$data = [
		'name' => $username,
		'password'=> str_replace("\n", "", $password)];
	$post_data = json_encode($data);
	$headers = [
		'Content-Type: application/json',
	];
	$ch = setCurl();
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	curl_setopt($ch, CURLOPT_POSTFIELDS, $post_data);
	$response = curl_exec($ch);
	$responseArray = json_decode($response, true);
	return $responseArray['token'];
}

function decrypt($key, $encFile): false|string {
	$command = "openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -in $encFile -pass pass:$key";
	$process = proc_open($command, [
		0 => ['pipe', 'r'],
		1 => ['pipe', 'w'],
		2 => ['pipe', 'w'],
	], $pipes);
	if (is_resource($process)) {
		// Close stdin pipe immediately since we're not using it
		fclose($pipes[0]);

		$stdout = stream_get_contents($pipes[1]);
		$stderr = stream_get_contents($pipes[2]);
		fclose($pipes[1]);
		fclose($pipes[2]);
		proc_close($process);
		if ($stderr) {
			//Handle error (log, throw exception)
			error_log("openssl error: " . $stderr);
			return false;
		}
		return $stdout;
	}
	return false;
}

function get_etcd_auth_token() {
	$dir                =       "/run/secrets";
	$username           =       "webui";
	$key                =       file_get_contents("$dir/webui-key");
	$encFile            =       "$dir/webui-enc";
	$password           =       decrypt($key, $encFile);
	return get_etcd_authtoken($username, $password);
}

function get_prefix_range_end($prefix): string
{
	// Since many modules will use this, we add it to get_auth_token
	// Calculate the range end for a prefix watch
	// This increments the last byte to create the exclusive upper bound
	// NB - input is NOT base64 encoded.
	$len = strlen($prefix);
	if ($len === 0) {
		return "\0"; // Special case for empty prefix (watch all keys)
	}
	// Convert to array of bytes
	$bytes = str_split($prefix);
	// Find the last byte that can be incremented
	for ($i = $len - 1; $i >= 0; $i--) {
		$byte = ord($bytes[$i]);
		if ($byte < 0xff) {
			// Increment this byte
			$bytes[$i] = chr($byte + 1);
			// Return the prefix up to and including this byte
			return implode('', array_slice($bytes, 0, $i + 1));
		}
	}
	// All bytes are 0xff, no range end needed (watch single key or all keys with this prefix)
	return "\0";
}

function etcd_healthCheck(): bool{
	// Health check
	$HOST_NAME = "svr.wavelet.allethrium";
	$ch = setCurl();
	curl_setopt($ch, CURLOPT_URL, 'https://' . ($HOST_NAME) . ':2379/health');
	$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
	if ($httpCode !== 200) {
		return false;
	} else {
		return true;
	}
}