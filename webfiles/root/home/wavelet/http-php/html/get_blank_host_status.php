<?php
header('Content-type: application/json');
// polls etcd for the host blank status
$hostName   =   $_POST["key"];

function poll_etcd_host($keyPrefix) {
	$ch = curl_init();
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

// we might want to add the capability to get the valid hostName from the hash, as promotion/renaming is making a mess of things.
$prefixstring = "/$hostName/DECODER_BLANK";
$keyPrefix=base64_encode($prefixstring);
poll_etcd_host($keyPrefix);
?>
