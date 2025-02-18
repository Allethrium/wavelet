<?php
header('Content-type: application/json');
include('get_auth_token.php');
// this script curls etcd for available hosts.

function poll_etcd_hosts() {
	$prefix					=		"/UI/hostlist";
	$keyPrefix				=		base64_encode($prefix);
	$keyPrefixPlusOneBit	=		base64_encode($prefix . '0');
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/range');
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_POST, 1);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\": \"$keyPrefix\", \"range_end\": \"$keyPrefixPlusOneBit\"}");
	$headers = array();
	$headers[] = 'Content-Type: application/x-www-form-urlencoded';
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	$result = curl_exec($ch);
	if (curl_errno($ch)) {
		echo 'Error:' . curl_error($ch);
	}
	curl_close($ch);
	$dataArray 				=		json_decode($result, true);
	foreach ($dataArray['kvs'] as $x => $item) {
		$key		=		str_replace ("/UI/hostlist/", "", (base64_decode($item['key'])));
       	$value		=		base64_decode($item['value']);
		$newData[] = [
			'key'				=>	$key,
			'value'				=>	$value,
			'type'				=>	$value,
			'hostName'			=>	$key,
			'hostHash'			=>	curl_etcd($key . '/hash'),
			'hostLabel'			=>	curl_etcd($key . '/control/label'),
			'hostIP'			=>	curl_etcd($key . '/IP'),
			'hostBlankStatus'	=>	curl_etcd($key . '/control/BLANK'),
		];
	}
	$output = json_encode($newData);
	echo $output;
}

function curl_etcd($key) {
		$b64KeyTarget = base64_encode("/UI/hosts/$key");
		$ch = curl_init();
		curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/range');
		curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
		curl_setopt($ch, CURLOPT_POST, 1);
		curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$b64KeyTarget\"}");
		$headers = array();
		$headers = [
			"Authorization: $token",
			"Content-Type: application/json"
		];
		curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
		$hashresult = curl_exec($ch);
		if (curl_errno($ch)) {
				echo 'Error:' . curl_error($ch);
		}
		curl_close($ch);
		$hashDataArray = json_decode($hashresult, true); 
		foreach ($hashDataArray['kvs'] as $x => $item) {
				$decodedHashKey		=	base64_decode($item['key']);
				$decodedHashValue	=	base64_decode($item['value']);
				$hostHashDecoded 	=	json_encode($decodedHashValue);
        		return str_replace ("\"", "", $hostHashDecoded);
		}
}

$token=get_etcd_authtoken;
poll_etcd_hosts();
?>