<?php
header('Content-type: application/json');
include('get_auth_token.php');

$key = $_POST["key"];
$value = $_POST["value"];

function del_etcd($input, $token) {
	$prefixstring = "$input";
	$prefixstringplusOne = "$prefixstring" . "0";
	$keyPrefix=base64_encode($prefixstring);
	$keyPrefixPlusOneBit=base64_encode($prefixstringplusOne);
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/deleterange');
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_POST, 1);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\": \"$keyPrefix\", \"range_end\": \"$keyPrefixPlusOneBit\"}");
	$headers = array();
	$headers[] = 'Authorization: ' .  $token;
	$headers[] = 'Content-Type: application/x-www-form-urlencoded';
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	error_log("Calling delete_input_labels() function for key prefix \"$prefixstring\"");
	$result = curl_exec($ch);
	if (curl_errno($ch)) {
		echo 'Error:' . curl_error($ch);
	}
	echo "\n$input range removed";
}

function get_etcd($key, $token) {
	echo "Attempting to get $keyTarget";
	$b64KeyTarget = base64_encode($keyTarget);
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/range');
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_POST, 1);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$b64KeyTarget\"}");
	$headers = array();
	$headers[] = 'Authorization: ' .  $token;
	$headers[] = 'Content-Type: application/x-www-form-urlencoded';
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	$result = curl_exec($ch);
	if (curl_errno($ch)) {
		echo 'Error:' . curl_error($ch);
	}
	curl_close($ch);
	echo "\n Successfully got {$keyTarget} for {$keyValue} \n";
	return $keyValue;
}

$token						=	get_etcd_auth_token();
echo "PHP set_remove_input Received removal request for Key:\n$key\nAnd value:\n$value\n";

if (str_contains ($key, '/UI/network_shorthash/')) {
	echo "\nThis is a network device, calling appropriate function for network device..\n";
	del_etcd("$key", $token);
	del_etcd("/UI/short_hash/$value", $token);
} else {
	echo "\nThis is a local device, calling appropriate function for local device..\n";
	// we no longer need to perform steps to provide keys because all the data we need for interface is stored in postdata.
	del_etcd("/UI/short_hash/$value", $token);
	del_etcd($key, $token);
}
?>