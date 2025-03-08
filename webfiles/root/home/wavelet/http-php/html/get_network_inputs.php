<?php
header('Content-type: application/json');
include('get_auth_token.php');

// this script curls etcd for available NETWORKED input devices.  
function poll_etcd_inputs($keyPrefix, $keyPrefixPlusOneBit, $token) {
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/range');
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_POST, 1);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\": \"$keyPrefix\", \"range_end\": \"$keyPrefixPlusOneBit\"}");
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
<<<<<<< Updated upstream
		$decodedKeyShort = (str_replace("-video-index0", "", (str_replace("/UI/network_interface/short/", "", (base64_decode($item['key']))))));
		$decodedKey = base64_decode($item['key']);
		$decodedValue = base64_decode($item['value']);
		$decodedShortHash = (str_replace("/UI/network_interface/", "", base64_decode($item['value'])));
		$ipValue=get_device_ip($decodedShortHash);
=======
		$decodedKeyShort		=	(str_replace("-video-index0", "", (str_replace("/UI/network_interface/short/", "", (base64_decode($item['key']))))));
		$decodedKey				=	base64_decode($item['key']);
		$decodedValue			=	base64_decode($item['value']);
		$decodedShortHash		=	(str_replace("/UI/network_interface/", "", base64_decode($item['value'])));
		$ipValue=get_device_ip($decodedShortHash, $token);
>>>>>>> Stashed changes
			$newData[] = [
				'value' => $decodedValue,
				'key' => $decodedKeyShort,
				'keyFull' => $decodedKey,
				'IP' => $ipValue
			];
		}
	$output = json_encode($newData);
	echo $output;
}


function get_device_ip($decodedShortValue, $token){
	$networkIPHashValue = base64_encode("/network_ip/$decodedShortValue");
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/range');
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_POST, 1);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\": \"$networkIPHashValue\"}");
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
	$IPresult = curl_exec($ch);
	if (curl_errno($ch)) {
		echo 'Error:' . curl_error($ch);
	}
	curl_close($ch);
	$dataIPArray = json_decode($IPresult, true);
	foreach ($dataIPArray['kvs'] as $x => $item) {
		$decodedValue = base64_decode($item['value']);
		return $decodedValue;
	}
}

// modify these strings if you want to get a different key prefix out of etcd.  For Wavelet, there's no reason to change them.
<<<<<<< Updated upstream
$prefixstring = '/UI/network_interface/';
$prefixstringplusone = '/UI/network_interface0';
$keyPrefix=base64_encode($prefixstring);
$keyPrefixPlusOneBit=base64_encode($prefixstringplusone);
$token=get_etcd_authtoken;
poll_etcd_inputs($keyPrefix, $keyPrefixPlusOneBit);
=======
$prefixstring				=	'/UI/network_interface/';
$prefixstringplusone 		=	'/UI/network_interface0';
$keyPrefix 					=	base64_encode($prefixstring);
$keyPrefixPlusOneBit		=	base64_encode($prefixstringplusone);
$token						=	get_etcd_auth_token();

poll_etcd_inputs($keyPrefix, $keyPrefixPlusOneBit, $token);
>>>>>>> Stashed changes
?>