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

function get_device_ip($input, $token){
	echo "looking for $input";
	$networkIPHashValue = base64_encode("$input");
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/range');
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($ch, CURLOPT_POST, 1);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\": \"$networkIPHashValue\"}");
	$headers = array();
	$headers[] = 'Authorization: ' .  $token;
	$headers[] = 'Content-Type: application/x-www-form-urlencoded';
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	$IPresult = curl_exec($ch);
	if (curl_errno($ch)) {
		echo 'Error:' . curl_error($ch);
	}
	curl_close($ch);
	$dataIPArray = json_decode($IPresult, true);
	foreach ($dataIPArray['kvs'] as $x => $item) {
		$decodedValue = base64_decode($item['value']);
	}
	return $decodedValue;
	echo "\nFound: $decodedValue";
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

if (str_contains ($value, '/network_ip/')) {
	echo "\nThis is a network device, calling appropriate function for network device..\n";
	$modHash		=	(str_replace("/network_ip/", "", $value));
	# Extract network IP and use it to delete
	$ipAddr			=	get_device_ip($value, $token);
	del_etcd("/network_uv_stream_command/$ipAddr", $token);
	del_etcd("$key", $token);
	del_etcd("/network_ip/$modHash", $token);
	del_etcd("/network_longhash/$modHash", $token);
	del_etcd("/network_shorthash/$modHash", $token);
} else {
	echo "\nThis is a local device, calling appropriate function for local device..\n";
	// We find long_interface and devpath_lookup from hash so we delete that last
	$longInterface	=	get_etcd("/hash/$value", $token); 
	$longInterface	=	strstr($longInterface, '/inputs', true);
	$longInterface	=	"/long_interface/" . $longInterface;
	$strippedKey	=	strstr($key, '/interface/', true);
	$strippedKey	=	substr($strippedKey, 0, strpos($variable, "/"));
	$hostName		=	strstr($strippedKey, '/', true);
	del_etcd("/$hostName/devpath_lookup/$value", $token);
	del_etcd("$longInterface", $token);
	del_etcd("/short_hash/$value", $token);
	del_etcd("/hash/$value", $token);  
	del_etcd($key, $token);
}
?>