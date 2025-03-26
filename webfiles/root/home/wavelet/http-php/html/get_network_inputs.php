<?php
header('Content-type: application/json');
include('get_auth_token.php');

// this script curls etcd for available NETWORKED input devices.  
function poll_etcd_inputs($key, $token) {
	$keyPrefix 					=	base64_encode($key);
	$keyPrefixPlusOneBit		=	base64_encode("$key" . "0");
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/range');
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_POST, 1);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\": \"$keyPrefix\", \"range_end\": \"$keyPrefixPlusOneBit\"}");
	$headers = array();
	$headers[] = 'Authorization: ' .  $token;
	$headers[] = 'Content-Type: application/x-www-form-urlencoded';
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	$result = curl_exec($ch);
	if (curl_errno($ch)) {
		echo 'Error:' . curl_error($ch);
	}
	curl_close($ch);
	$dataArray = json_decode($result, true);
	foreach ($dataArray['kvs'] as $x => $item) {
		// Packed format IP;DEVICE_LABEL(attempts to set the device hostname!);DEVICE_MAC -- $HASH
		list($ipAddress, $hostName, $macAddress)		=	explode(";", (base64_decode($item['key'])));
		$decodedKeyFull									=	base64_decode($item['key']);
		$ipAddress										=	str_replace("/UI/interface/", '', $ipAddress);
		$hostName										=	$hostName
		$value 											=	base64_decode($item['value']);
		$newData[] = [
			'value'		=>	$value,
			'key'		=>	$hostName,
			'keyFull'	=>	$decodedKeyFull,
			'IP'		=>	$ipAddress
		];
	}
	$output = json_encode($newData);
	echo $output;
}

$key						=	'/UI/network_interface/';
$token						=	get_etcd_auth_token();
poll_etcd_inputs($key, $token);
?>