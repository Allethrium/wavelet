<?php
header('Content-type: application/json');
include 'get_auth_token.php';
// this script curls etcd for available input devices, cleans out the cruft and re-encodes a JSON object that should be handled by the webui index.html via AJAX

function poll_etcd_inputs($keyPrefix, $keyPrefixPlusOneBit, $token) {
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
	$dataArray = json_decode($result, true); // this decodes the JSON string as an associative array
	foreach ($dataArray['kvs'] as $x => $item) {
	// This forms the "pretty" label, the value that gets changed when the relabel key is picked.
	$decodedKeyShort = (str_replace("-video-index0", "", (str_replace("/interface/", "", (base64_decode($item['key']))))));
	// This is the hash value of the device, and is used to track the device state if it is unplugged/plugged back in to the same port
	$decodedKey = base64_decode($item['key']);
	// This is the "long" device name which is used as a reverse lookup w/ the device hash
	$decodedValue = base64_decode($item['value']);
		$newData[] = [
			'key'	=> $decodedKey,
			'value'	=> $decodedValue,
		];
	}
	$output = json_encode($newData);
	echo $output;
}

$prefixstring				=	'/audio_interface_bluetooth_mac';
$prefixstringplusone		=	'/audio_interface_bluetooth_mac0';
$keyPrefixPlusOneBit		=	base64_encode($prefixstring);
$keyPrefixPlusOneBit		=	base64_encode($prefixstringplusone);
$token						=	get_etcd_auth_token();
poll_etcd_inputs($keyPrefix, $keyPrefixPlusOneBit, $token);
?>