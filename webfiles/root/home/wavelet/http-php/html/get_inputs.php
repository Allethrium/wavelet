<?php
header('Content-type: application/json');
include('get_auth_token.php');
// this script curls etcd for available input devices, 
// cleans out the cruft and re-encodes a JSON object that should be handled by the webui index.html via AJAX

function poll_etcd_inputs($keyPrefix, $keyPrefixPlusOneBit, $token) {
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/range');
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_POST, 1);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\": \"$keyPrefix\", \"range_end\": \"$keyPrefixPlusOneBit\"}");
	$headers		=	array();
	$headers[]		=	'Authorization: ' .  $token;
	$headers[]		=	'Content-Type: application/x-www-form-urlencoded';
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	$result = curl_exec($ch);
	if (curl_errno($ch)) {
		echo 'Error:' . curl_error($ch);
	}
	curl_close($ch);
	$dataArray				=	json_decode($result, true); // this decodes the JSON string as an associative array
	if (is_array($dataArray['kvs']) && count($dataArray['kvs']) > 0) {
		foreach ($dataArray['kvs'] as $x => $item) {
			// we get back a list of keys/vals from /UI/interface/$KEY
			// $KEY is a packed format of:  HOSTNAME;HOSTNAMEPRETTY;DEVICELABEL;DEVICE FULLPATH
			$keyFull													=	base64_decode($item['key']);
			$decodedValue												=	base64_decode($item['value']);
			list($hostName, $hostNamePretty, $inputLabel, $inputPath) 	=	explode(";", $keyFull);
			$newHostName 												=	str_replace("/UI/interface/", '', $hostName);
			$newData[]			=	[
				'key'				=>	isset($inputLabel) ? $inputLabel: "0",
				'value'				=>	isset($decodedValue) ? $decodedValue : "0",
				'keyFull'			=>	isset($keyFull) ? $keyFull : "0",
				'keyLong'			=>	isset($inputPath) ? $inputPath : "0",
				'host'				=>	isset($newHostName) ? $newHostName : "0",
				'hostNamePretty'	=>	isset($hostNamePretty) ? $hostNamePretty : "0"
			];
		}
	} else {
		$newData 				=	[];
	}
	$output = json_encode($newData);
	echo $output;
}

function curl_etcd($key, $token) {
	// - useful for debugging but will BREAK return vals! echo nl2br ("Attempting to get: $key\n");
	$b64KeyTarget	=	base64_encode("$key");
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/range');
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_POST, 1);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$b64KeyTarget\"}");
		$headers	=	array();
		$headers[]	=	'Authorization: ' .  $token;
		$headers[]	=	'Content-Type: application/x-www-form-urlencoded';
		curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
		$result = curl_exec($ch);
		if (curl_errno($ch)) {
			echo 'Error:' . curl_error($ch);
		}
		curl_close($ch);
	$hashDataArray = json_decode($result, true); 
	foreach ($hashDataArray['kvs'] as $x => $item) {
		$decodedKey		=	base64_decode($item['key']);
		$decodedValue	=	strtok(base64_decode($item['value']), "\\");
		$Decoded		=	json_encode($decodedValue);
		return $Decoded;
	}
}


$prefixstring 				=	'/UI/interface';
$prefixstringplusone		=	'/UI/interface0';
$keyPrefix					=	base64_encode($prefixstring);
$keyPrefixPlusOneBit		=	base64_encode($prefixstringplusone);
$token						=	get_etcd_auth_token();
poll_etcd_inputs($keyPrefix, $keyPrefixPlusOneBit, $token);
?>