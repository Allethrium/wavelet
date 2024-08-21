<?php
header('Content-type: application/json');
// Here we are called from JS with 
$key = "dec2DC8.wavelet.local";

function curl_etcd($inputValue) {
		$b64KeyTarget = base64_encode($inputValue);
		$ch = curl_init();
		curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/range');
		curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
		curl_setopt($ch, CURLOPT_POST, 1);
		curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$b64KeyTarget\"}");
		$headers = array();
		$headers[] = 'Content-Type: application/x-www-form-urlencoded';
		curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
		$result = curl_exec($ch);
		if (curl_errno($ch)) {
				echo 'Error:' . curl_error($ch);
		}
		curl_close($ch);
		$dataArray = json_decode($result, true); // this decodes the JSON string as an associative array
		foreach ($dataArray['kvs'] as $x => $item) {
				$decodedKey = base64_decode($item['key']);
				$decodedValue = base64_decode($item['value']);
				$hostHash = json_encode($decodedValue);
		echo $hostHash;
		}
}

// looks for a hash value for a host
$inputValue = "/$key/Hash";
curl_etcd($inputValue);
?>
