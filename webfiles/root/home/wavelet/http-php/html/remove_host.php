<?php
header('Content-type: application/json');
$key = $_POST["key"];
$value = $_POST["value"];

function delete_host_labels($key) {
	$prefixstring = "decoderlabel/$key";
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
	echo "$key removed from decoderlabel.";
}

function delete_host_ip($key) {
	$prefixstring = "decoderip/$key";
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
	echo "$key removed from decoder IP List.";
}

function delete_host_keys($key) {
	$prefixstring = "$key";
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
	echo "$key removed from decoder state tracking.";
}

echo "Key received $key";
delete_host_labels($key);
delete_host_ip($key);
delete_host_keys($key);


echo "Requested Label, IP and config keys deleted for device hostname $host.  Rebooting host and rejoining will re-register it with Wavelet.";
?>
