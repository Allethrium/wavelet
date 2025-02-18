<?php
// POST fields from JS AJAX will only ever single entries.  We extract them both here.
function get_etcd_authtoken($password, $username) {
	$password = base64_encode($_ENV['PASSWORD']);
	$username = base64_encode('webui');
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
	curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'POST');
	// returns etcd authorization token utilizing the systemd password variable and the username webui
	curl_setopt($ch, CURLOPT_URL, 'http://1982.168.1.32:2379/v3/auth/authenticate');
	$headers = [
		'Content-Type: application/json',
	];
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"name\": \"$username\", \"password\": \"$password\"}");
	curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
	$token = curl_exec($ch);
	curl_close($ch);
	return $token;
}
get_etcd_authtoken;
?>