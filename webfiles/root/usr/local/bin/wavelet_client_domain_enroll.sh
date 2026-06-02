#!/bin/bash
# Called from the domain enroll watcher service (wavelet-root)
# Runs only on server

detect_self(){
	case $(hostname) in
		svr*)
			echo "	I am a Server"
			generate_ipaHost
			;;
		*)
			echo "	This device is not a server."
			exit 0
			;;
		esac
}

generate_ipaHost(){
	# Kinit as admin so we can make configuration changes
	echo "$(cat /var/secrets/ipaadmpw.secure)" | kinit admin
	# Ping so ensure the IP:MAC is in the ARP table
	ping "${targetMachineIP}" -c 1
	# Get client MAC Address
	targetMACAddr="$(arp -a | grep "${targetMachineIP}" | awk '{print $4}' | head -n 1)"
	# Generate the OTP encryption factor by SHA256ing the target IP+MAC (this ought to match a similar process on the target)
	# In other words, both machines independently generate the password factor
	# The 'ticket' is valid for an hour - may introduce annoying issues if we run a task at 12:59:59 though!
	# Note - the client machines will be set to rotate their MAC addresses!!
    # Check if current time is within 30 seconds of the end of current hour
    current_second=$(date +%S)
    current_minute=$(date +%M)
    if [ "$current_minute" -eq 59 ] && [ "$current_second" -ge 30 ]; then
        sleep_seconds=$((60 - current_second))
        echo "Waiting $sleep_seconds seconds until next hour to avoid collision on encryption factor2."
        sleep "$sleep_seconds"
    fi
	local factor2="$(echo -n $targetMachineIP,$(dnsdomainname),${targetMACAddr^^},$(date +"%H"))"
	factor2="$(echo $factor2 | sha256sum | cut -d ' ' -f1)"
	# Add IPA host principal (DNS should be fine here, so we don't need IP addresses)
	# Since Kea DHCP may not have pushed the "correct" hostname to IPA, we force the host principal creation.
	local otp="$(ipa host-add $targetHostName --random --force | grep 'Random password: ')"
	# Clean, then Base64 the random password as it may contain escapable chars
	local otp="${otp#*: }"; local otp="$(echo $otp | base64 -w 0)"
	if [[ "$otp" == "Cg==" ]]; then
		echo "Random OTP password variable is base64 zero, something may have gone wrong with provisioning."
		echo "Check FreeIPA server logs on server in /var/freeipa-data/var/log for more information."
		exit 1
	fi
	# Generate our base64 encoded binary
	local binVar="$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass pass:$factor2 - <<< $otp | base64 -w 0)"
    local decryptResult="$(base64 -d <<< $binVar | openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -pass pass:$factor2 )"
    local decryptResult="$(base64 -d <<< "$decryptResult")"
	if [[ "$decryptResult" == "$(base64 -d <<< "${otp}")" ]]; then
		echo "  Password encrypted and tested successfully!"
	else
		echo "  Decrypt failed, something is wrong!"
		exit 1
	fi
	# Supply OTP via etcd - we should avoid etcd_interaction_hooks.sh in this instance.
	KEYNAME="/ENROLL/REQUEST/$targetHostName/OTP"; KEYVALUE="$binVar"
	declare -A commandLine=([3]="put" [2]="$KEYNAME" [1]="--" [0]="$KEYVALUE");
	# We don't need userargs because they are populated within the script's environment.
	etcdctl "${commandLine[@]}"; unset commandLine
	# Client will be unable to decrypt OTP if factor2 doesn't match, everything deleted quickly.
	echo "	Deleting keys after 20 Second delay.."
	sleep 20
	# Delete all keys
	KEYNAME="/ENROLL/REQUEST/$targetHostName"
	declare -A commandLine=([3]="del" [2]="$KEYNAME" [1]="--prefix")
	etcdctl "${commandLine[@]}"; unset commandLine
	unset userArg binVar otp decryptResult factor2
}

remove_and_retry_enrollment(){
	# Attempts enrollment a second time, if an initial enrollment had failed.
	echo "$(cat /var/secrets/ipaadmpw.secure)" | kinit admin
	ipa host-del $targetHostName
	generate_ipaHost
}

#####
#
# Main
#
#####


# Check for pre-existing log file
logName="/var/home/wavelet-root/logs/enroll.log"
exec >> "${logName}" 2>&1
etcdValue="${ETCD_WATCH_VALUE//\"}"
etcdKey="${ETCD_WATCH_KEY//\"}"
if [[ "$etcdValue" == "" ]]; then
    exit 0
fi

if [[ "$etcdKey" == *"/OTP" ]]; then
    exit 0
fi

ETCDCTL_ENDPOINTS="https://$(hostname):2379"
ETCDCTL_CACERT="/etc/ipa/ca.crt"

if [[ -f "/var/wavelet_ramfs/wavelet_secure_credentials.sh" ]]; then
	source "/var/wavelet_ramfs/wavelet_secure_credentials.sh"
else
	source "/usr/local/bin/wavelet_secure_credentials.sh"
fi

generate_etcd_userarg user=wavelet-root hostname="$(hostname)" extraargs=ENROLL

if [[ -z "$ETCDCTL_PASSWORD" ]] || [[ -z "$ETCDCTL_USER" ]]; then
	echo "	ERROR:  Username and password not found for Enrollment process."
	exit 0
fi

targetHostName="$(echo "${etcdKey##*REQUEST/}" | xargs)"; targetHostName="${targetHostName##*/}"
targetMachineIP="${etcdValue#*REQUEST;}"

if [[ "$etcdKey" == *"OTP_RECOVER"* ]]; then
	remove_and_retry_enrollment
fi

if [[ -z "$targetHostName" ]]; then
	echo "Invalid hostname supplied.  Exiting."
	exit 0
fi

detect_self