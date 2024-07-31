<?php
// Here we are called from JS with three POST variables
// Hash = device hash from webUI, 
// label = device label from webUI, this is used to overwrite the device string in /interface/ and make the label persistent.
// oldText = the old device label, which we need to delete from ETCD.
$hash = $_POST["value"];
$label = $_POST["label"];
$oldText = $_POST["oldvl"];

// create a new cURL resource
    // example of a valid cURL command:
    // curl -L http://192.168.1.32:2379/v3/kv/put -X POST -d '{"key":"aW5wdXQ=", "value":"Mw=="}'
// Generated by curl-to-PHP: http://incarnate.github.io/curl-to-php/
// writing a new keyname makes a new key

function curl_etcd($keyTarget, $keyValue) {
	echo "Attempting to set $keyTarget for $keyValue";
	$b64KeyTarget = base64_encode($keyTarget);
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
	echo "\n Succesfully set {$keyTarget} for {$keyValue} \n";
}

function del_etcd($keyTarget) {
	// And we DELETE the old key/keyvalue, because the hash is the same.
	echo "Attempting to delete old entry $keyTarget";	
	$b64KeyTarget = base64_encode($keyTarget);
	$b64KeyTargetPlusOne = base64_encode("$keyTarget\0");
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/deleterange');
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
        curl_setopt($ch, CURLOPT_POST, 1);
        curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$b64KeyTarget\", \"range_end\":\"$b64KeyTargetPlusOne\"}");
        $headers = array();
        $headers[] = 'Content-Type: application/x-www-form-urlencoded';
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        $result = curl_exec($ch);
        if (curl_errno($ch)) {
                echo 'Error:' . curl_error($ch);
        }
        curl_close($ch);
        echo "\n Succesfully deleted {$keyTarget} \n";
}


// curl etcd uv_hash_select for the value of the device hash we want to see streaming on the system
// please note how we have to call the function twice to set the reverse lookup values as well as the fwd values!
echo "posted data are: \n New Label: $label, \n Old Label: $oldText, \n Hash: $hash \n";

// Here we need to determine if we are dealing with a USB or PCIe capture device attached to the server, or whether we are dealing with a network device, as they are written in different keys on etcd

if (str_contains ($hash, 'network_shorthash')) {
		echo "This is a network device, calling appropriate function for network device.."
		curl_etcd("/network_interface/short/$label", $hash);
		curl_etcd("/network_shorthash/$hash", "$label");
		del_etcd($oldText);
	} else {
		echo "This is a local device, calling appropriate function for local device.."
		curl_etcd("/interface/$label", "$hash");
		curl_etcd("/short_hash/$hash", "$label");
		del_etcd("$oldText");
	}
?>
