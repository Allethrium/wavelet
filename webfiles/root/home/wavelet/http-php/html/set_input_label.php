<?php
header('Content-type: application/json');
include('get_auth_token.php');
// Here we are called from JS with three POST variables
// Hash = device hash from webUI, 
// label = device label from webUI, this is used to overwrite the device string in /interface/ and make the label persistent.
// oldText = the old device label, which we need to delete from ETCD.


$hash = $_POST["value"];
$label = $_POST["label"];
$oldText = $_POST["oldvl"];

function set_etcd_inputLabel($keyTarget, $keyValue) {
	$b64KeyTarget = base64_encode($keyTarget);
	$b64KeyValue = base64_encode($keyValue);
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/put');
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_POST, 1);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$b64KeyTarget\", \"value\":\"$b64KeyValue\"}");
	$headers = array();
	$headers = [
		"Authorization: $token",
		"Content-Type: application/json"
	];
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	$result = curl_exec($ch);
	if (curl_errno($ch)) {
		echo 'Error:' . curl_error($ch);
	}
	curl_close($ch);
	echo "\nSuccesfully set $keyTarget for $keyValue";
}

function del_etcd($keyTarget) {
	$b64KeyTarget = base64_encode($keyTarget);
	$b64KeyTargetPlusOne = base64_encode("$keyTarget\0");
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/deleterange');
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_POST, 1);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$b64KeyTarget\", \"range_end\":\"$b64KeyTargetPlusOne\"}");
	$headers = array();
	$headers = [
		"Authorization: $token",
		"Content-Type: application/json"
	];
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	$result = curl_exec($ch);
	if (curl_errno($ch)) {
			echo 'Error:' . curl_error($ch);
	}
	curl_close($ch);
	echo "\nSuccesfully deleted $keyTarget";
}


// curl etcd uv_hash_select for the value of the device hash we want to see streaming on the system
// please note how we have to call the function twice to set the reverse lookup values as well as the fwd values!
echo "posted data are: \n New Label: $label, \n Old Label: $oldText, \n Hash: $hash \n";

// Here we need to determine if we are dealing with a USB or PCIe capture device attached to the server, or whether we are dealing with a network device, as they are written in different keys on etcd
$token=get_etcd_authtoken;
if (str_contains ($hash, '/network_interface/')) {
		echo "This is a network device, calling appropriate function for network device..";
		$value=$hash;
		$modHash=(str_replace("/network_interface/", "", $value));
		set_etcd_inputLabel('/network_interface/short/' . $label, $modHash);
		set_etcd_inputLabel('/network_shorthash/' . $modHash, $label);
		del_etcd($oldText);
	} else {
		echo "This is a local device, calling appropriate function for local device..";
		set_etcd_inputLabel('/interface/' .$label, $hash);
		set_etcd_inputLabel('/short_hash/' .$hash, $label);
		del_etcd("$oldText");
	}
?>