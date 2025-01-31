<?php
header('Content-type: application/json');
// this module handles all the toggle functions in the webUI.  It takes one argument (the toggle key)

// Import the etcd password from the OS environment
$password = base64_encode(os.environ('ETCD_PASS'));
$username = base64_encode('wavelet_webui');

$toggleKey = $_POST["toggleKey"];

curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'POST');
curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);

function get_etcd_authtoken($password, $username) {
	// returns etcd authorization token utilizing the systemd ETCD_PASS variable and the username wavelet_webui
	curl_setopt($ch, CURLOPT_URL, 'http://localhost:2379/v3/auth/authenticate');
	$headers [
		'Content-Type: application/x-www-form-urlencoded'
		];
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"name\": \"$username\", \"password\": \"$password\"}");
	curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
	$token = curl_exec($ch);
	curl_close($ch);
}

function poll_etcd_inputs($token, $keyPrefix) {
		$ch = curl_init();
		curl_setopt($ch, CURLOPT_URL, 'http://localhost:2379/v3/kv/range');
		curl_setopt($ch, CURLOPT_POST, 1);
		$headers = array();
		$headers[
			"Authorization: $token",
		    'Content-Type: application/x-www-form-urlencoded';
		curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\": \"$keyPrefix\"}");
		curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
		$result = curl_exec($ch);
		if (curl_errno($ch)) {
			echo 'Error:' . curl_error($ch);
		}
		curl_close($ch);
		$dataArray = json_decode($result, true); // this decodes the JSON string as an associative array
		foreach ($dataArray['kvs'] as $x => $item) {
		$decodedKey = base64_decode($item['key']);
		$decodedValue = base64_decode($item['value']);
		}
		echo $decodedValue;
}

// modify these strings if you want to get a different key prefix out of etcd.  For Wavelet, there's no reason to change them.

$prefixstring = "/$toggleKey/enabled";
$keyPrefix=base64_encode($prefixstring);
get_etcd_authtoken($password, $username)
poll_etcd_inputs($token, $keyPrefix);
?>

