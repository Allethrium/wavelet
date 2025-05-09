<?php
header('Content-type: application/json');
include('get_auth_token.php');

// This module gets called every n seconds from the JS frontend
// It takes no inputs, and returns a key and value depending on the functionID with which it was called.
// The value is in the packed format timestamp|are-of-interest
// The key is only updated from the wavelet_poll_watcher services running on the server.

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
		$newData[] = [
			'key'				=>	$decodedKey,
			'value'				=>	$decodedValue,
		];
	}
	$output = json_encode($newData);
	echo $output;
}

$prefixstring		=	"/UI/POLL_UPDATE";
$keyPrefix			=	base64_encode($prefixstring);
$token				= 	get_etcd_auth_token();
poll_etcd_inputs($token, $keyPrefix);
?>