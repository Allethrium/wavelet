<?php
header('Content-type: application/json');
include('get_auth_token.php');
// This module gets UV hash select value, which tells the UI what the currently streaming device is.

<<<<<<< Updated upstream
function poll_etcd_inputs($keyPrefix) {
=======
function poll_etcd_inputs($keyPrefix, $token) {
>>>>>>> Stashed changes
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/range');
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_POST, 1);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\": \"$keyPrefix\"}");
	$headers = array();
<<<<<<< Updated upstream
	$headers = [
		"Authorization: $token",
		"Content-Type: application/json"
	];
=======
	$headers[] = 'Authorization: ' .  $token;
	$headers[] = 'Content-Type: application/x-www-form-urlencoded';
>>>>>>> Stashed changes
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	$result = curl_exec($ch);
	if (curl_errno($ch)) {
		echo 'Error:' . curl_error($ch);
	}
	curl_close($ch);
	$dataArray = json_decode($result, true);
	foreach ($dataArray['kvs'] as $x => $item) {
		$decodedKey = base64_decode($item['key']);
		$decodedValue = base64_decode($item['value']);
		$newData[] = [
			'key'	=> $decodedKey,
			'value'	=> $decodedValue,
		];
	}
	$output = json_encode($newData);
	echo $output;
}

$prefixstring = "/UI/UV_HASH_SELECT";
$keyPrefix=base64_encode($prefixstring);
<<<<<<< Updated upstream
$token=get_etcd_authtoken;
poll_etcd_inputs($keyPrefix);
=======
$token						=	get_etcd_auth_token();
poll_etcd_inputs($keyPrefix, $token);
>>>>>>> Stashed changes
?>