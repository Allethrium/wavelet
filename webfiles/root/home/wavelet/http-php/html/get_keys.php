<?php
header('Content-type: application/json');
include('get_auth_token.php');

function poll_etcd_range($keyPrefix, $keyPrefixPlusOneBit, $token) {
	$ch = setCurl();
	$headers = [
		'Authorization: ' . $token,
		'Content-Type: application/x-www-form-urlencoded'
	];
    curl_setopt($ch, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_2_0);
	curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
	curl_setopt($ch, CURLOPT_URL, 'https://' . (HOST_NAME) . ':2379/v3/kv/range');
	curl_setopt($ch, CURLOPT_POSTFIELDS, "{\"key\": \"$keyPrefix\", \"range_end\": \"$keyPrefixPlusOneBit\"}");
	$result = curl_exec($ch);
	if (curl_errno($ch)) {
		return null;
	}
	return json_decode($result, true);
}

function parse_groups($dataArray) {
	if (empty($dataArray['kvs'])) {
		return [];
	}
	$groups = [];
	foreach ($dataArray['kvs'] as $item) {
		$key = base64_decode($item['key']);
		$value = base64_decode($item['value'] ?? '');
		if (str_starts_with($key, '/UI/GROUPS/')) {
			$groupParts = explode('/', $key);
			$groupName = $groupParts[3];
			if (!isset($groups[$groupName])) {
				$groups[$groupName] = [
					'hashID' => $groupName,
					'type' => 'group',
					'key' => $groupName,
					'controls' => []
				];
			}
			if (count($groupParts) == 6) {
				if (str_contains($key, '/control/')) {
					$controlParts = explode('/control/', $key);
					if (isset($controlParts[1])) {
						$controlName = $controlParts[1];
						$groups[$groupName]['controls'][$controlName] = $value;
					}
				}
			}
		}
	}
	return array_values($groups);
}

function parse_hosts_and_inputs($dataArray) {
	if (empty($dataArray['kvs'])) {
		return [];
	}
	usort($dataArray['kvs'], function($a, $b) {
		$keyA = base64_decode($a['key']);
		$keyB = base64_decode($b['key']);
		$lenA = strlen($keyA);
		$lenB = strlen($keyB);
		if ($lenA === $lenB) {
			return strcmp($keyA, $keyB);
		}
		return $lenA - $lenB;
	});
	$hosts = [];
	foreach ($dataArray['kvs'] as $item) {
		// Skip items with missing or invalid data
		if (!isset($item['key'])) {
			continue;
		}
		$key = base64_decode($item['key']);
		$value = base64_decode($item['value'] ?? "");
		if (empty($key) || (empty($value) && $value !== '0')) {
			continue;
		}
		if (!str_starts_with($key, '/UI/HOSTS/')) {
			continue;
		}
        $hostParts = explode('/', $key);
        $hostHash = $hostParts[3];

        if (!isset($hosts[$hostHash])) {
            $hosts[$hostHash] = [
                'hashID' => $hostHash,
                'labelText' => $value,
                'type' => 'host',
                'key' => $value,
                'parentHashID' => null, // may remove, obsolete?
                'controls' => [],
                'inputs' => []
            ];
        }
        if (str_contains($key, '/hash')) {
            $hosts[$hostHash]['hashID'] = $value;
        } elseif (str_contains($key, '/control/')) {
            $controlParts = explode('/control/', $key);
            if (isset($controlParts[1])) {
                $controlName = $controlParts[1];
                $hosts[$hostHash]['controls'][$controlName] = $value;
            }
        } elseif (str_contains($key, '/inputs/')) {
            $parsedKeys = explode(";", $value);
            $inputLabel = $parsedKeys[1] ?? "";
            $subType = end($parsedKeys) ?? '';
            $hosts[$hostHash]['inputs'][] = [
                'hashID' => $hostParts[5],
                'keyFull' => $value,
                'labelText' => $inputLabel,
                'type' => 'input',
                'subType' => $subType,
                'parentHashID' => $hosts[$hostHash]['hashID'] ?? null,
                'isActive' => false // always false
            ];
        }
    }
	return array_values($hosts);
}

function parse_globals($dataArray) {
	if (empty($dataArray['kvs'])) {
		return [];
	}
	usort($dataArray['kvs'], function($a, $b) {
		$keyA = base64_decode($a['key']);
		$keyB = base64_decode($b['key']);
		$lenA = strlen($keyA);
		$lenB = strlen($keyB);
		if ($lenA === $lenB) {
			return strcmp($keyA, $keyB);
		}
		return $lenA - $lenB;
	});
	$globals = [];
	foreach ($dataArray['kvs'] as $item) {
		// Skip items with missing or invalid data
		if (!isset($item['key']) || !isset($item['value'])) {
			continue;
		}
		$key = base64_decode($item['key']);
		$value = base64_decode($item['value']);
		// Only process UI keys
		if (!str_starts_with($key, '/UI/')) {
			continue;
		}
		// Exclude HOSTS and GROUPS paths
		if (str_starts_with($key, '/UI/HOSTS/') || str_starts_with($key, '/UI/GROUPS/')) {
			continue;
		} elseif (str_starts_with($key, '/UI/GLOBALS/') && str_contains($key, '/controls/')) {
			$controlParts = explode('/controls/', $key);
			if (isset($controlParts[1])) {
				$controlName = $controlParts[1];
				$globals['CONTROLS'][$controlName] = $value;
			}
		} elseif (str_starts_with($key, '/UI/GLOBALS/CODECS/')) {
			// Extract codec key from path
			$parts = explode('/', $key);
			$codecKey = $parts[4] ?? null;
			if ($codecKey) {
				$globals['CODECS'][$codecKey] = $value;
			}
		}
	}
	return $globals;
}

$token = get_etcd_auth_token();

// Fetch globals
$groupsPrefix = base64_encode('/UI/');
$groupsPrefixEnd = base64_encode(get_prefix_range_end('/UI/'));
$globalsData = poll_etcd_range($groupsPrefix, $groupsPrefixEnd, $token);
$globals = parse_globals($globalsData);

// Fetch groups
$groupsPrefix = base64_encode('/UI/GROUPS/');
$groupsPrefixEnd = base64_encode(get_prefix_range_end('/UI/GROUPS/'));
$groupsData = poll_etcd_range($groupsPrefix, $groupsPrefixEnd, $token);
$groups = parse_groups($groupsData);

// Fetch hosts and inputs
$hostsPrefix = base64_encode('/UI/HOSTS/');
$hostsPrefixEnd = base64_encode(get_prefix_range_end('/UI/HOSTS/'));
$hostsData = poll_etcd_range($hostsPrefix, $hostsPrefixEnd, $token);
$hosts = parse_hosts_and_inputs($hostsData);

echo json_encode([
	'groups' => $groups,
	'hosts' => $hosts,
	'globals' => $globals
]);