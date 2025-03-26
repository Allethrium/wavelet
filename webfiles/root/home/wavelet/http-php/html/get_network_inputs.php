<?php
header('Content-type: application/json');
include('get_auth_token.php');

// this script curls etcd for available NETWORKED input devices.  
function poll_etcd_inputs($key, $token) {
	$keyPrefixPlusOneBit		=	"{$key}0";
	$keyPrefix 					=	base64_encode("$key");
	$keyPrefixPlusOneBit		=	base64_encode("$keyPrefixPlusOneBit");
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
		// Packed format IP;DEVICE_LABEL(attempts to set the device hostname!);IP -- $HASH
		// \/UI\/network_interface\/192.168.1.27;Magewell_Proconvert_HDMI_null;d0:c8:57:81:b4:75
		$keyFull										=	base64_decode($item['key']);
		$value											=	base64_decode($item['value']);
		list($ipAddress, $hostName)						=	explode(";", $keyFull);
		$ipAddress										=	str_replace("/UI/network_interface/", '', $ipAddress);
		$newData[]			=	[
			'keyFull'	=>	$keyFull,
			'value'		=>	$value,
			'IP'		=>	$ipAddress,
			'key'		=>	$hostName
		];
	}
	$output = json_encode($newData);
	echo $output;
}

$key						=	'/UI/network_interface';
$token						=	get_etcd_auth_token();
poll_etcd_inputs($key, $token);
?>