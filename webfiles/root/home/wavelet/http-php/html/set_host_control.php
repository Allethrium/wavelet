<?php
header('Content-type: application/json');
include('get_auth_token.php');

$hostName = $_POST["key"];				// The hostName of the device
$hostHash = $_POST["hash"];				// Hash value of the target device
$value = $_POST["value"]; 				// this can be a bool or a label
$function = $_POST["hostFunction"];		// from JS

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
//									REBOOT(bool)
//									REVEAL(bool)
//									BLANK(bool)
//									The host modules can write to the UI subkeys, the UI is limited to only UI.
// * - not modified by this module or the webUI, but populated always from the host.

function set_etcd($keyPrefix, $keyValue, $token) {
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
	curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'POST');	
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/put');
	curl_setopt($ch, CURLOPT_POST, 1);
	$headers = [
		"Authorization: $token",
		"Content-Type: application/json"
	];
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$keyPrefix\", \"value\":\"$keyValue\"}");
	curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
	$result = curl_exec($ch);
	if (curl_errno($ch)) {
		echo 'Error:' . curl_error($ch);
	}
	curl_close($ch);
}

function validateValue($function, $value) {
	// if we are writing to any of these keys, the value must be 0 or 1.
	$booleanFields	=	array("PROMOTE", "DEPROVISION", "RESET", "REBOOT", "REVEAL", "BLANK");
	foreach($booleanFields as $t)
	{
		if (preg_match("/\b" . $t . "\b/i", $function)) {
			$output		=	var_dump((bool) $value);	//	convert to bool
		} else {
			$output 	=	$value;					//	this can only be the label function
		}
	}
}

validateValue($function, $value);
$token			=	get_etcd_auth_token();
$prefixstring	=	"/UI/hosts/$hostName/control/$function";
$keyPrefix		=	base64_encode($prefixstring);
$keyValue		=	base64_encode($value);
set_etcd($keyPrefix, $keyValue, $token);
?>