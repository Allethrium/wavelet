<?php
header('Content-type: application/json');
$key = $_POST["key"];
$value = $_POST["value"];

function delete_input_labels($key) {
	$prefixstring = "interface/$key";
	$keyPrefix=base64_encode($prefixstring);
		$ch = curl_init();
		curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/deleterange');
		curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
		curl_setopt($ch, CURLOPT_POST, 1);
		curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$keyPrefix\"}");
	$headers = array();
		$headers[] = 'Content-Type: application/x-www-form-urlencoded';
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	error_log("Calling delete_host_labels() function for key prefix \"$keyPrefix\""); // Log the function call
		$result = curl_exec($ch);
		if (curl_errno($ch)) {
			echo 'Error:' . curl_error($ch);
	}
	echo "$key removed from /interface/...";
}

function delete_short_hash($value) {
	$prefixstring = "/short_hash/$value";
	$keyPrefix=base64_encode($prefixstring);
		$ch = curl_init();
		curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/deleterange');
		curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
		curl_setopt($ch, CURLOPT_POST, 1);
		curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$keyPrefix\"}");
	$headers = array();
		$headers[] = 'Content-Type: application/x-www-form-urlencoded';
		curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
		$result = curl_exec($ch);
		if (curl_errno($ch)) {
			echo 'Error:' . curl_error($ch);
	}
		error_log();
	echo "$key removed from /short_hash/ ..";
}

function delete_hash($value) {
	$prefixstring = "$value";
	$keyPrefix=base64_encode($prefixstring);
		$ch = curl_init();
		curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/deleterange');
		curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
		curl_setopt($ch, CURLOPT_POST, 1);
		curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$keyPrefix\"}");
	$headers = array();
		$headers[] = 'Content-Type: application/x-www-form-urlencoded';
		curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
		$result = curl_exec($ch);
		if (curl_errno($ch)) {
			echo 'Error:' . curl_error($ch);
	}
		error_log();
	echo "$key removed from hash table.  Subsequent new device detections will remove other entries.";
}

echo "Key received $key";
delete_input_labels($key);
delete_short_hash($value);
delete_hash($value);


echo "Requested Label and tracking data have been removed from Wavelet - subsequent redections will clear old data and repopulate as a fresh device, if it entered some kind of failure mode.";
?>
