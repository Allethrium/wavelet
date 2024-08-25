<?php
$key = $_POST["key"];

function curl_etcd($keyTarget) {
        $b64KeyTarget = base64_encode($keyTarget);
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
        $dataArray = json_decode($result, true);
        foreach ($dataArray['kvs'] as $x => $item) {
                $decodedKey = base64_decode($item['key']);
                $decodedValue = base64_decode($item['value']);
        }
        echo $decodedValue;
        return $decodedValue;
}

$keyTarget = ("/hostHash/$key/ipaddr");
curl_etcd($keyTarget);
?>
