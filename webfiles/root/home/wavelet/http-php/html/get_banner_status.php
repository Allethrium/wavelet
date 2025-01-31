<?php
header('Content-type: application/json');
// this module handles all the toggle functions in the webUI.  It takes one argument (the toggle key)
$toggleKey = $_POST["toggleKey"];

function poll_etcd_inputs($keyPrefix) {
		$ch = curl_init();
		// CURL example:  curl -L http://192.168.1.32:2379/v3/kv/range -X POST -d '{"key": "L2ludGVyZmFjZQ==", "range_end": "L2ludGVyZmFjZTA="}'
		curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/range');
		curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
		curl_setopt($ch, CURLOPT_POST, 1);
		curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\": \"$keyPrefix\"}");
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
		}
	//      $output = json_encode($newData);
		echo $decodedValue;
}

// modify these strings if you want to get a different key prefix out of etcd.  For Wavelet, there's no reason to change them.
$prefixstring = '/banner/enabled';
$keyPrefix=base64_encode($prefixstring);
poll_etcd_inputs($keyPrefix);
?>

