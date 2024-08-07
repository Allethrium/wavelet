<?php
header('Content-type: application/json');
// this script curls etcd for available input devices, cleans out the cruft and re-encodes a JSON object that should be handled by the webui index.html via AJAX

function poll_etcd_inputs($keyPrefix, $keyPrefixPlusOneBit) {
	$ch = curl_init();
	// CURL example:  curl -L http://192.168.1.32:2379/v3/kv/range -X POST -d '{"key": "L2ludGVyZmFjZQ==", "range_end": "L2ludGVyZmFjZTA="}'
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

	$dataArray = json_decode($result, true); // this decodes the JSON string as an associative array
	$newData = [];
	foreach ($dataArray['kvs'] as $x => $item) {
		$decodedKeyShort = (str_replace("-video-index0", "", (str_replace("/interface/", "", (base64_decode($item['key']))))));
		$decodedKey = base64_decode($item['key']);
		$decodedValue = base64_decode($item['value']);
		$hostName = (str_replace ("/hostLabel/", "", (str_replace("/type", "", $decodedKey))));
//		$hostHash = "";
		array_push($newData, [
			'key'		=>	$decodedKeyShort,
			'type'		=>	$decodedValue,
			'hostName'	=> 	(str_replace ("/hostLabel/", "", (str_replace("/type", "", $decodedKey)))),
			'hostHash'	=>	(str_replace ("\"", "", curl_etcd($hostName))),
		]);
	}
	$output = json_encode($newData);
	echo $output;
}

function curl_etcd($inputValue) {
		$b64KeyTarget = base64_encode("/$inputValue/Hash");
		$ch = curl_init();
		curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/range');
		curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
		curl_setopt($ch, CURLOPT_POST, 1);
		curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$b64KeyTarget\"}");
		$headers = array();
		$headers[] = 'Content-Type: application/x-www-form-urlencoded';
		curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
		$hashresult = curl_exec($ch);
		if (curl_errno($ch)) {
				echo 'Error:' . curl_error($ch);
		}
		curl_close($ch);
		$hashDataArray = json_decode($hashresult, true); // this decodes the JSON string as an associative array
		foreach ($hashDataArray['kvs'] as $x => $item) {
				$decodedHashKey = base64_decode($item['key']);
				$decodedHashValue = base64_decode($item['value']);
				$hostHashDecoded = json_encode($decodedHashValue);
		return $hostHashDecoded;
		}
}

// modify these strings if you want to get a different key prefix out of etcd.  For Wavelet, there's no reason to change them.
$prefixstring = '/hostLabel';
$prefixstringplusone = '/hostLabel0';
$keyPrefix=base64_encode($prefixstring);
$keyPrefixPlusOneBit=base64_encode($prefixstringplusone);
poll_etcd_inputs($keyPrefix, $keyPrefixPlusOneBit);
?>
