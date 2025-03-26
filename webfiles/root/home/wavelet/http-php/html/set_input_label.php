<?php
header('Content-type: application/json');
include('get_auth_token.php');
// Here we are called from JS with three POST variables
// Hash = device hash from webUI, 
// label = device label from webUI, this is used to overwrite the device string in /interface/ and make the label persistent.
// oldText = the old device label, which we need to delete from ETCD.
		
$hash = $_POST["value"];
$label = $_POST["label"];
$oldText = $_POST["oldInterfaceKey"];
$hostName = $_POST["host"];
$hostLabel = $_POST["hostLabel"];

function set_etcd_inputLabel($keyTarget, $keyValue, $token) {
	$b64KeyTarget = base64_encode($keyTarget);
	$b64KeyValue = base64_encode($keyValue);
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/put');
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_POST, 1);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$b64KeyTarget\", \"value\":\"$b64KeyValue\"}");
	$headers = array();
	$headers[] = 'Authorization: ' .  $token;
	$headers[] = 'Content-Type: application/x-www-form-urlencoded';
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	$result = curl_exec($ch);
	if (curl_errno($ch)) {
		echo 'Error:' . curl_error($ch);
	}
	curl_close($ch);
	echo "\nSuccesfully set $keyTarget for $keyValue";
}

function del_etcd($keyTarget, $token) {
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
	echo "\nSuccessfully deleted $keyTarget";
}


// curl etcd uv_hash_select for the value of the device hash we want to see streaming on the system
// please note how we have to call the function twice to set the reverse lookup values as well as the fwd values!
echo "posted data are: \n New Label: $label, \n Old Full Key: $oldText, \n Hash: $hash \n";

// Here we need to determine if we are dealing with a USB or PCIe capture device attached to the server, or whether we are dealing with a network device, as they are written in different keys on etcd
$token	=	get_etcd_auth_token();
if (str_contains ($oldText, 'network_interface')) {
		// Packed format IP;DEVICE_LABEL(attempts to set the device hostname!);IP -- $HASH
		echo "This is a network device, calling appropriate function for network device..";
		set_etcd_inputLabel('/UI/network_interface/' . "$hostName;$label;$hostName", $hash, $token);
		del_etcd($oldText, $token);
	} else {
		echo "This is a local device, calling appropriate function for local device..";
		// Ensure key format remains:  HOSTNAME;HOSTNAMEPRETTY;DEVICELABEL;DEVICE FULLPATH
		set_etcd_inputLabel('/UI/interface/' . "$hostName;$hostLabel;$label;$oldText" , $hash, $token);
		set_etcd_inputLabel('/UI/short_hash/' . $hash, "$hostName;$hostLabel;$label;$oldText", $token);
		del_etcd("$oldText", $token);
	}
?>