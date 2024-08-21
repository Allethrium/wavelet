<?php
// Here we are called from JS with three POST variables
// Hash = device hash from webUI, 
// label = device label from webUI, this is used to overwrite the device string in /interface/ and make the label persistent.
// oldText = the old device label, which we need to delete from ETCD.
$hash = $_POST["hash"];
$newName = $_POST["newName"];
$oldName = $_POST["oldName"];

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


// since we track by hash and the backend script does the cleanup, we need only submit the hash, and the new device label.
echo "posted data are: \n New Label: $newName\n Hash: $hash \n";
set_etcd_hosthash("$newName", "$hash");
?>
