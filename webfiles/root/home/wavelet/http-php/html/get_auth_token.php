<?php
// Grabs an auth token based on the password string set during server spinup in NGINX config
// These vars shouldn't be accessible from the web browser side, and even if they are, they grant access only to /UI/

function get_etcd_authtoken($username, $password) {
	$data = [
		'name' => $username,
		'password'=> str_replace("\n", "", $password)];
	$post_data = json_encode($data);
	$ch = curl_init();
	curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
	curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'POST');
	curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/auth/authenticate');
	$headers = [
		'Content-Type: application/json',
	];
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	curl_setopt($ch, CURLOPT_POSTFIELDS, $post_data);
	curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
	$response = curl_exec($ch);
	//$response =curl_getinfo($ch);
	curl_close($ch);
	$responseArray = json_decode($response, true);
	$token = $responseArray['token'];
	return $token;
}

function base64_url_decode($input) {
 return strtr($input, '._-', '+/+');
}

function decrypt($pw2) {
	//return openssl_decrypt(base64_decode(file_get_contents("/var/secrets/crypt.bin")), 'aes-256-cbc', $key, OPENSSL_RAW_DATA);
	return base64_decode((shell_exec("openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -in /var/secrets/crypt.bin -nosalt -pass pass:$pw2")));
}

function get_etcd_auth_token() {
$dir			= 	"/var/secrets";
$username		= 	"webui";
$pw2 			=	file_get_contents("$dir/pw2.txt");
$password		=	decrypt($pw2);
$token			=	get_etcd_authtoken($username, $password);
return $token;
}
?>
