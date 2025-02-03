<?php
header('Content-type: application/json');
// this module handles all the host status controls for the webui.
// Input is the host, the value to set and the value it is set to.
// replaces the four previous host control modules

// Keymap:
//
// /UI/hosts/$hostNameSys(hostKey/	label($hostNamePretty)
//									hostHash(Hash)*
//									IP(Hash)*
//									PROMOTE(bool)
//									DEPROVISION(bool)
//									RESET(bool)
//									REVEAL(bool)
//									BLANK(bool)
//									The host modules can write to the UI subkeys, the UI is limited to only UI.
// * - not modified by this module or the webUI, but populated always from the host.

// Import the etcd password from..something..somewhere - nginx env?
$password = base64_encode('test');
$username = base64_encode('wavelet_webui');

$hostKey 		= $_POST["toggleID"];		// 
$value			= $_POST["value"]; 			// this can be a bool or a label
$hostFunction	= $_POST["function"];		// from JS

function get_etcd_authtoken($password, $username) {
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
	curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'POST');
	// returns etcd authorization token utilizing the systemd ETCD_PASS variable and the username wavelet_webui
	curl_setopt($ch, CURLOPT_URL, 'http://1982.168.1.32:2379/v3/auth/authenticate');
	$headers = [
		'Content-Type: application/x-www-form-urlencoded',
	];
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"name\": \"$username\", \"password\": \"$password\"}");
	curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
	$token = curl_exec($ch);
	curl_close($ch);
	return $token;
}

function set_etcd($keyPrefix, $keyValue) {
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
	curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'POST');	
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/put');
	curl_setopt($ch, CURLOPT_POST, 1);
	$headers = [
		"Authorization: $token",
		"Content-Type: application/x-www-form-urlencoded"
	];
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$keyPrefix\", \"value\":\"$keyValue\"}");
	curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
	$result = curl_exec($ch);
	if (curl_errno($ch)) {
		echo 'Error:' . curl_error($ch);
	}
	curl_close($ch);
	echo "Set Key: $keyPrefix and Value: $keyValue";
}

function validateValue($function, $value) {
	// if we are writing to any of these keys, the value must be 0 or 1.
	$booleanFields	=	('PROMOTE REVEAL DEPROVISION BLANK RESET');
	if (strpos($booleanFields, $function) {
		$output		=	vardump((bool) $value);	//	convert to bool
	else
		$output 	=	$value;					//	this can only be the label function
	}
}


// The key context, everything this does happens below here.
validateValue($function, $value);
$token=get_etcd_authtoken($password, $username);

$prefixstring = "/ui/hosts/$hostKey/control/$function";

$keyPrefix=base64_encode($prefixstring);
$keyValue=base64_encode($value);
set_etcd($keyPrefix, $keyValue);
?>