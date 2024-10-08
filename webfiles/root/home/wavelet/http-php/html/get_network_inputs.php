<?php
header('Content-type: application/json');
// this script curls etcd for available NETWORKED input devices.  
function poll_etcd_inputs($keyPrefix, $keyPrefixPlusOneBit) {
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
	$dataArray = json_decode($result, true);
	foreach ($dataArray['kvs'] as $x => $item) {
		$decodedKeyShort = (str_replace("-video-index0", "", (str_replace("/network_interface/short/", "", (base64_decode($item['key']))))));
		$decodedKey = base64_decode($item['key']);
		$decodedValue = base64_decode($item['value']);
		$decodedShortHash = (str_replace("/network_interface/", "", base64_decode($item['value'])));
		$ipValue=get_device_ip($decodedShortHash);
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


function get_device_ip($decodedShortValue){
	$networkIPHashValue = base64_encode("/network_ip/$decodedShortValue");
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/range');
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_POST, 1);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\": \"$networkIPHashValue\"}");
	$headers = array();
	$headers[] = 'Content-Type: application/x-www-form-urlencoded';
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
$prefixstring = '/network_interface/';
$prefixstringplusone = '/network_interface0';
$keyPrefix=base64_encode($prefixstring);
$keyPrefixPlusOneBit=base64_encode($prefixstringplusone);
poll_etcd_inputs($keyPrefix, $keyPrefixPlusOneBit);
?>