<?php
header('Content-type: application/json');
include('get_auth_token.php');

// this module handles all the toggle functions in the webUI.  It takes one argument (the toggle key)

// Import the etcd password from the OS environment
$password = base64_encode('test');
$username = base64_encode('wavelet_webui');

$toggleKey = $_POST["key"];

function poll_etcd_inputs($token, $keyPrefix) {
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
	curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'POST');	
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/range');
	curl_setopt($ch, CURLOPT_POST, 1);
	$headers = [
		"Authorization: $token",
		"Content-Type: application/x-www-form-urlencoded"
	];
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
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

error_reporting(E_ALL);
$prefixstring = "/ui/$toggleKey";
$keyPrefix=base64_encode($prefixstring);
$token=get_etcd_authtoken($password, $username);
$token=get_etcd_authtoken;
poll_etcd_inputs($token, $keyPrefix);
?>