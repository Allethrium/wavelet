<?php
header('Content-type: application/json');
include('get_auth_token.php');

// this module handles all the toggle functions in the webUI.  It takes one argument (the toggle key)

$toggleKey 		= $_POST["toggleID"];
$toggleValue	= $_POST["toggleValue"]; 

function set_etcd($token, $keyPrefix, $keyValue) {
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
	curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'POST');	
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/put');
	curl_setopt($ch, CURLOPT_POST, 1);
	$headers = [
		"Authorization: $token",
		"Content-Type: application/json"
	];
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$keyPrefix\", \"value\":\"$keyValue\"}");
	curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
	$result = curl_exec($ch);
	if (curl_errno($ch)) {
		echo 'Error:' . curl_error($ch);
	}
	curl_close($ch);
	echo "Set Key: $keyPrefix and Value: $keyValue";
}

// error_reporting(E_ALL);
$prefixstring	=	"/UI/$toggleKey";
$keyPrefix		=	base64_encode($prefixstring);
$keyValue		=	base64_encode($toggleValue);
$token			=	get_etcd_auth_token();

// curl etcd uv_hash_select for the value of the device hash we want to see streaming on the system
set_etcd($token, $keyPrefix, $keyValue);
set_etcd($token, "input_update", "1");
?>