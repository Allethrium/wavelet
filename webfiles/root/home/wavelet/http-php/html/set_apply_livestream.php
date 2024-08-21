<?php
// POST fields from JS AJAX will only ever single entries.  We extract them both here.
$lsurl = $_POST["lsurl"];
$apikey = $_POST["apikey"];

// create a new cURL resource
    // example of a valid cURL command:
    // curl -L http://192.168.1.32:2379/v3/kv/put -X POST -d '{"key":"aW5wdXQ=", "value":"Mw=="}'
// Generated by curl-to-PHP: http://incarnate.github.io/curl-to-php/

function curl_etcd($keyTarget, $keyValue) {
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
	echo "Succesfully set {$keyTarget} for {$keyValue} \n";
}

// curl etcd uv_hash_select for the value of the device hash we want to see streaming on the system
// actually activating the LiveStream is down to uv_hash_select.php
curl_etcd("/livestream/url", $lsurl);
curl_etcd("/livestream/apikey", $apikey);
?>
