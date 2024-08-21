<?php
// Here we are called from JS with 
// key = device hostname
// value = device label (initially ALSO device hostname)
$key = $_POST["hostName"];

function curl_etcd($key) {
        echo "Attempting to get $key";
        $b64KeyTarget = base64_encode($key);
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, 'http://192.168.1.32:2379/v3/kv/range');
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
        curl_setopt($ch, CURLOPT_POST, 1);
        curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\":\"$b64KeyTarget\"}");
        $headers = array();
        $headers[] = 'Content-Type: application/x-www-form-urlencoded';
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
        $result = curl_exec($ch);
        if (curl_errno($ch)) {
                echo 'Error:' . curl_error($ch);
        }
        curl_close($ch);
        echo "\n Successfully got {$key} for {$result} \n";
        return $result;
}

// curl etcd uv_hash_select for the value of the device hash we want to see streaming on the system
// please note how we have to call the function twice to set the reverse lookup values as well as the fwd values!
echo "posted data are: Host: $key \n";
curl_etcd("/hostHash/$key/ipaddr");
?>
