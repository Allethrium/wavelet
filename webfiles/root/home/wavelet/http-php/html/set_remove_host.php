<?php
header('Content-type: application/json');
$key = $_POST["key"];
$value = $_POST["value"];

function delete_host_entries($key) {
	$prefixstring = "/hostHash/$key";
	$prefixstringplusOne = "$prefixstring" . "0";
	$keyPrefix=base64_encode($prefixstring);
	$keyPrefixPlusOneBit=base64_encode($prefixstringplusOne);
		$ch = curl_init();
		curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/deleterange');
		curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
		curl_setopt($ch, CURLOPT_POST, 1);
		curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\": \"$keyPrefix\", \"range_end\": \"$keyPrefixPlusOneBit\"}");
	$headers = array();
		$headers[] = 'Content-Type: application/x-www-form-urlencoded';
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	error_log("Calling delete_input_labels() function for key prefix \"$prefixString\""); // Log the function call
		$result = curl_exec($ch);
		if (curl_errno($ch)) {
			echo 'Error:' . curl_error($ch);
	}
	echo "$key removed";
}

function delete_host_hash($value) {
	$prefixstring = "/hostHash/$value";
	$prefixstringplusOne = "$prefixstring" . "0";
	$keyPrefix=base64_encode($prefixstring);
	$keyPrefixPlusOneBit=base64_encode($prefixstringplusOne);
		$ch = curl_init();
		curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/deleterange');
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
	echo "$key removed from host Hash entries..";
}
function delete_host_state($key) {
	$prefixstring = "/$key";
	$prefixstringplusOne = "$prefixstring" . "0";
	$keyPrefix=base64_encode($prefixstring);
	$keyPrefixPlusOneBit=base64_encode($prefixstringplusOne);
		$ch = curl_init();
		curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/deleterange');
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
}
function delete_host_label($key) {
	$prefixstring = "/hostLabel/$key";
	$prefixstringplusOne = "$prefixstring" . "0";
	$keyPrefix=base64_encode($prefixstring);
	$keyPrefixPlusOneBit=base64_encode($prefixstringplusOne);
		$ch = curl_init();
		curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/deleterange');
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
}
function set_host_deprovision($key) {
		$b64KeyTarget = base64_encode($key);
		$b64KeyValue = base64_encode("1");
		$ch = curl_init();
		curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/put');
		curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
		curl_setopt($ch, CURLOPT_POST, 1);
		curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$b64KeyTarget\", \"value\":\"$b64KeyValue\"}");
		$headers = array();
		$headers[] = 'Content-Type: application/x-www-form-urlencoded';
		curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
		$result = curl_exec($ch);
		if (curl_errno($ch)) {
				echo 'Error:' . curl_error($ch);
		}
		curl_close($ch);
		echo "Succesfully set {$key} to deprovision.  Unit will shutdown immediately.\n";
}

// Key is hostname, value is the hash
delete_host_entries($key);
delete_host_label($key);
delete_host_hash($value);
delete_host_state($key);
set_host_deprovision($key);
echo "Host has been removed from Wavelet.  If booted whilst connected to the network, it will re-register itself with the server.  If the security layer is enabled, it will be unsuccessful as it will need to be re-imaged from scratch.";
?>