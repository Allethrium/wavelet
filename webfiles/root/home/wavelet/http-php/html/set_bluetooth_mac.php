<?php
header('Content-type: application/json');
include 'get_auth_token.php';
// Here we are called from JS with only one key to set a new bluetooth MAC address in the system
$value = $_POST["btMAC"];

function curl_etcd($value, $token) {
		echo "Attempting to set /audio_interface_bluetooth_mac for $value";
		$b64KeyTarget = base64_encode("/audio_interface_bluetooth_mac");
		$b64KeyValue = base64_encode($value);
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
		echo "\n Succesfully set /audio_interface_bluetooth_mac for {$value} \n";
}

// curl etcd uv_hash_select for the value of the device hash we want to see streaming on the system
// please note how we have to call the function twice to set the reverse lookup values as well as the fwd values!
echo "posted data are:\nMAC Address: $value\nKey: audio_interface_bluetooth_mac\n";
$token						=	get_etcd_auth_token();
curl_etcd($value, $token);
?>