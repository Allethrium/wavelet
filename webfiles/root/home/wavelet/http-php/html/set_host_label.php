<?php
// Here we are called from JS with three POST variables
// Hash = device hash from webUI, 
// label = device label from webUI, this is used to overwrite the device string in /interface/ and make the label persistent.
// oldText = the old device label, which we need to delete from ETCD.
$key = $_POST["key"];
$value = $_POST["value"];
$type = $_POST["type"]

function curl_etcd($keyTarget, $keyValue) {
		echo "Attempting to set $keyTarget for $keyValue";
		$b64KeyTarget = base64_encode("hostlabel/$keyTarget");
		$b64KeyValue = base64_encode($keyValue);
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
		echo "\n Succesfully set hostlabel/{$keyTarget} for {$keyValue} \n";
}

function curl_etcd_hostname($keyTarget, $keyValue) {
		echo "Attempting to set $keyTarget for $keyValue";
		$b64KeyTarget = base64_encode("$keyTarget/hostlabel");
		$b64KeyValue = base64_encode($keyValue);
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
		echo "\n Succesfully set {$keyTarget}/hostlabel for {$keyValue} \n";
}

function set_etcd_hostHash($keyTarget, $keyValue) {
		echo "Attempting to set $keyTarget for $keyValue";
		$b64KeyTarget = base64_encode("/hostHash/$keyTarget/$keyValue");
		$b64KeyValue = base64_encode($keyValue);
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
		echo "\n Succesfully set /hostHash/{$keyTarget}/label for {$keyValue} \n";
}


// curl etcd uv_hash_select for the value of the device hash we want to see streaming on the system
// please note how we have to call the function twice to set the reverse lookup values as well as the fwd values!

// add an IF argument here to set decoderlabel/encoderlabel etc.
echo "posted data are: \n New Label: $value\n Key: $key \n";
curl_etcd("$key", "$value");
curl_etcd_hostname("$key", "$value");
set_etcd_hosthash("$key", "$value");
?>
