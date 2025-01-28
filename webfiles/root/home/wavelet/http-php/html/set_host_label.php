<?php
// Here we are called from JS with three POST variables
// Hash = device hash from webUI, 
// label = device label from webUI, this is used to overwrite the device string in /interface/ and make the label persistent.
// oldText = the old device label, which we need to delete from ETCD.
$hash = $_POST["hash"];
$prettyName = $_POST["prettyName"];
$hostName = $_POST["hostName"];
$type = $_POST["type"];

function curl_etcd($keyTarget, $keyValue) {
		// sets the type for the NEW hostname so it populates to the correct DOM
		$b64KeyTarget = base64_encode("/$keyTarget");
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
		echo "\n Succesfully set {$keyTarget} for:\n{$keyValue}";
}

echo "posted data are: \nNew Label: $prettyName\nHash: $hash \nHost Name: $hostName\nType: $type";
// This script sets the NEW hostname object and then a reset flag.  Everything else is handled by run_ug/build_ug on reboot
$keyTarget="$hostName/hostNamePretty";
$keyValue=$prettyName;
curl_etcd("$keyTarget", "$keyValue");

// set old hostname relabel bit to activate process on target host
// after the task on the target host is completed, it will remove its old entries automatically
$keyTarget="$hostName/RELABEL";
$keyValue="1";
curl_etcd("$keyTarget", "$keyValue");
?>