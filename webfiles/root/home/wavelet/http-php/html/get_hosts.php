<?php
header('Content-type: application/json');
// this script curls etcd for available hosts, cleans out the cruft and re-encodes a JSON object that should be handled by the webui index.html via AJAX

function poll_etcd_labels() {
	$prefixstring = 'decoderlabel/';
	$prefixstringplusone = 'decoderlabel0';
	$keyPrefix=base64_encode($prefixstring);
	$keyPrefixPlusOneBit=base64_encode($prefixstringplusone);
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
		$dataLabelArray = json_decode($result, true); // this decodes the JSON string as an associative array
		foreach ($dataLabelArray['kvs'] as $x => $item) {
			$decodedKeyShort = (str_replace("decoderlabel/", "", (base64_decode($item['key']))));
			$decodedValue = base64_decode($item['value']);
				$newLabelData[] = [
						'key' => htmlspecialchars(trim($decodedKeyShort)),
						'value' => htmlspecialchars($decodedValue),
				];
		}
		$labeloutput = json_encode($newLabelData);
		return $labeloutput;
}

$outputLabel    =   json_encode(json_decode(poll_etcd_labels(),true));
echo $outputLabel;
?>