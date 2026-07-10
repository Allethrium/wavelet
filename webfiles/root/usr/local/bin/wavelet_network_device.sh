#!/bin/bash

# Wavelet network sense script
# Processes data from the Kea DHCP server via UNIX Socket

# Runs in two modes:
#   --probe $IP, tries to test a device manually and update in Wavelet if its a supported device.
#   normal operation called from monitoring the /DHCP etcd key, which performs device interrogation and population.


# Etcd Interaction hooks
ETCDINTERACTIONHOOKS=""
if [[ -f "/var/wavelet_ramfs/etcd_interaction_hooks.sh" ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source "/usr/local/bin/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/usr/local/bin/etcd_interaction_hooks.sh"
fi
echo "		Pathing: $ETCDINTERACTIONMOD"

parse_macaddr() {
	# Perhaps we can dispense with this, since we only truly care about getting the video stream.
	# This is largely obsolete from an earlier build
	# However, there's a possibility we can use Wavelet to enforce PTZ camera orientations via REST
	# Hence I'm leaving this in here for future tweaking
	echo -e "	Detect network device function called with the following data:\n		MAC: ${2^^}\n		IP Address: ${1}"
	ipAddr="$1"
	echo "	Searching for pre-existing matches in system.."
	printvalue=""
	# Load a list of all hosts and search for this device MAC address by string match.
	KEYNAME="/HOSTS/"; read_etcd_prefix_list; currentHosts="$printvalue"
	while read -r line; do
		if [[ "${line^^}" == "${2^^}" ]]; then
			echo "	Found MAC already in host keys, will not process further."
			exit 0
		fi
	done <<<"$currentHosts"
	# We put ^^ after the var to convert to uppercase!
	case "${2^^}" in
		# Convert input to all uppercase with ^^i
		D0:C8:57:8*)                    echo -e "	Nanjing (Magewell) device matched, proceeding to attempt configuration"                    ; event_magewell_ndi
		;;
		70:B3:D5:75:D*)                 echo -e "	Nanjing (Magewell) device matched, proceeding to attempt configuration"                    ; event_magewell_ndi
		;;
		D4:E0:8E*)                      echo -e "	ValueHD Corporation (PTZ Optics) matched, proceeding to attempt configuration"             ; event_ptz_ndiHX
		;;
		whateverNDIis)                  echo -e "	NDI matched, proceeding to attempt configuration"                                          ; event_vendorDevice3
		;;
		# This one might need different config as the camera is of a different design
		DC:ED:84*)                      echo -e "	PTZ Optics NDI Cam (Haverford Systems Inc.) matched, proceeding to attempt configuration"  ; event_ptz_ndiHX
		;;
		*)                              event_checkForSupport
		;;
	esac
}

# Device processing blocks - these are the 'driver' as far as this module is concerned.

create_magewell_wavelet_user() {
	# sub-function to delete/recreate wavelet userI
	# Delete wavelet user if already exists
	curl -s -b /var/tmp/sid.txt \
		"http://$ipAddr/mwapi?method=del-user&id=wavelet"
	waveletUserPass=$(cat /home/wavelet/config/networkdevice_userpass)
	echo -e "	Attempting to add Wavelet user.."
	md5sumWaveletPassword=$(echo -n "${waveletUserPass}" | md5sum | cut -d' ' -f1)
	curl -s -b /var/tmp/sid.txt \
		"http://$ipAddr/mwapi?method=add-user&id=wavelet&pass=${md5sumWaveletPassword}"
	# Now we login with the Wavelet User to save the cookie
	curl -s --cookie-jar /var/tmp/wavelet_sid.txt \
		"http://$ipAddr/mwapi?method=login&id=wavelet&pass=$md5sumWaveletPassword"
	# Further security settings for these devices are really the responsibility of the installation engineer
	echo -e "	Recommend changing the device default Admin password for security reasons.\n"
}

add_wavelet_ca(){
	# Add the IPA CA to the magewell device for TLS
	echo "	Adding the IPA CA certificate to the device.."
	CERT_FILE="/etc/ipa/ca.crt"
	UPLOAD_URL="http://$ipAddr/mwapi?method=upload-cert"
	RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
		-b "/var/tmp/sid.txt" \
		-F "file=@$CERT_FILE;type=application/x-x509-ca-cert" \
		"$UPLOAD_URL")
	HTTP_STATUS=$(echo "$RESPONSE" | grep -oP 'HTTP_STATUS:\K[0-9]+')
	BODY=$(echo "$RESPONSE" | sed 's/HTTP_STATUS:[0-9]*//')
	if [[ "$HTTP_STATUS" -ne 200 ]]; then
		echo "	Upload failed with HTTP status: $HTTP_STATUS" >&2
		echo "	Response body: $BODY" >&2
		exit 1
	fi
	if echo "$BODY" | grep -q '"success":true'; then
		echo "	Certificate uploaded successfully."
	else
		echo "	Upload failed. Server response: $BODY" >&2
		exit 1
	fi
}

event_magewell_ndi(){
	# Interrogates Magewell device, attempts preconfigured username and password
	# It then tries to set appropriate settings for streaming into UltraGrid.
	# We assume the preconfigured username/pass combo of admin/Admin here.
	# If this is different, you should set it here ( might want a credentials file for this )
	defaultAdminUsername="Admin"
	defaultAdminPassword="Admin"
	echo -e "		Calling curl with GET request for Default Username and Password.."
	md5sumAdminPassword=$(echo -n "${defaultAdminPassword}" | md5sum | cut -d' ' -f1)
	result=$(curl -s --cookie-jar /var/tmp/sid.txt \
	  "http://${ipAddr}/mwapi?method=login&id=${defaultAdminUsername}&pass=${md5sumAdminPassword}" | jq .[] | head -n 1)
	if [[ "${result}" -ne 0 ]]; then
		echo -e "\n		Connection to MageWell device failed!  Reset the device to FACTORY DEFAULTS and try again!\n"
		exit 1
	else
		echo "		Connection with default credentials succeeded! proceeding.."
		# Despite REST API docs, doesn't seem to work.
		# add_wavelet_ca
		# Perhaps we should autogen an admin password and store it in etcd here for security purposes?
		# This network device username and password should be generated by the wavelet installer script
		# at the same time as the wavelet_root and wavelet user passwords, mod ignition and installer scripts
		# Check for existing user
		result=$(curl -s -b /var/tmp/sid.txt "http://${ipAddr}/mwapi?method=get-users")
		if 	[[ $result = *"wavelet"* ]] && \
			[[ -f /var/tmp/wavelet_sid.txt ]]; then
			echo "Wavelet user already generated, testing.."
			result=$(curl -s -b /var/tmp/wavelet_sid.txt \
				"http://${ipAddr}/mwapi?method=login&id=wavelet&pass=${md5sumWaveletPassword}" \
				| jq .[] | head -n 1)
			if [[ ${result} == "0" ]]; then
				echo "Curl returns status 0, success!"
			else
				echo "Failed, resetting wavelet user."
				create_magewell_wavelet_user
			fi
		else
			create_magewell_wavelet_user
		fi
		magewellCommands=(	"mwapi?method=set-video-config&out-fr-convertion=frame-rate-half" \
							"mwapi?method=set-video-config&out-raw-resolution=false&out-cx=1920&out-cy=1080" \
							"mwapi?method=set-video-config&in-auto-quant-range=false&in-quant-range=full" \
							"mwapi?method=set-video-config&in-auto-color-fmt=false&in-color-fmt=rgb" \
							"mwapi?method=set-video-config&bit-rate-ratio=150" \
							"mwapi?method=set-ndi-config&enable=true")
		for i in "${magewellCommands[@]}"; do
			uri="http://$ipAddr/$i"
			cookiefile="/var/tmp/wavelet_sid.txt"
			#echo "Command: curl -b /var/tmp/wavelet_sid.txt http://$ipAddr/$i"
			if /usr/bin/curl -s -b "$cookiefile" "$uri"; then
				continue
			else
				echo "  Errors with: $uri"
			fi
		done
		echo -e "\n		Attempting to match with NDI devices found by UltraGrid.."
		deviceHostName="$(curl -s -b /var/tmp/wavelet_sid.txt http://$ipAddr/mwapi?method=get-summary-info | jq '.device.name' | tr -d '"')"
		type="net"
		subType="NDI"
		event_checkForSupport
		populate_to_etcd
	fi
}

event_ptz_ndiHX(){
	# Interrogates PTZ Cam device
	# This device supports NDI, so we try to use that.
	# The camera also supports PTZ commands over TCP/UDP ports 5678 and 1259 respectively.
	# Manual available at:  https://ptzoptics.imagerelay.com/share/PT-MOVE-SE-G3-User-Manual
	# We don't currently have any expanded documentation for other HTTP calls
	# We are a little stuck until PTZ comes through.
	# If they come through.
	type="net"
	subType="NDI"
	# sleep 5 # We introduce a delay so mDNS can pick up the NDI source.
	event_checkForSupport
}

event_checkForSupport(){
	# This is a more general-purpose function to check for NDI and RTSP streams, and use them if available.
	# LibNDI should be installed on wavelet by default along with avahi mDNS (DEPENDENCY)
	echo "	Checking for device support.."
	local deviceHostName
	if [[ -z "$deviceHostName" ]]; then
		deviceHostName="$(nslookup $ipAddr | awk '{print $4}' | xargs)"
	fi
	if [[ "$printvalue" == "dec" ]]; then
		echo "  	Host is populated as a Wavelet client, not processing further."
		exit 0
	fi
	type="net"
	get_ndi_devices
	for dev in "${ndiDevices[@]}"; do
		if [[ "$dev" == *"$ipAddr"* ]]; then
			echo "  	NDI is available for this device, querying for NDI ports and defaulting to NDI.."
			UGdeviceStreamCommand="-t ndi:name=${dev%--*}:color=100"
			UGdeviceSubscribeCommand="-t ndi:name=${dev%--*}"
			deviceHostName="NDI-${dev%--*}"
			subType="NDI"
			populate_to_etcd
		else
			if ffprobe -v quiet -show_streams "$UGdeviceStreamCommand"; then
				deviceHostName="RTSP-$ipAddr"
				subType="RTSP"
				populate_to_etcd
				echo -e "		Device RTSP configured, however it may not work without further settings.\n"
				continue
			else
				echo "		Discovery error! falling back on direct IP interrogation.."
				event_checkIP
				continue
			fi
		fi
	done
}

event_checkIP(){
	echo "	Attempting direct device type resolution by IP address.."
	# do some acrobatics to locate NDI or RTSP support here
}

event_check_multiCast(){
	# Would look for MC or other possible things we have yet to look at.
	echo "		Multicast testing TBD, if it even makes sense."
}

populate_to_etcd(){
	# Since we run on the server, we can populate our keys to the UI directly.
	# Initial group is always the server group
	local deviceResult=0
	if [[ -z "$GROUP_HASH" ]]; then
		KEYNAME="/HOSTS/$hostNameSys/control/GROUP"; read_etcd_global; initGroupHash="$printvalue"
	else
		initGroupHash="$GROUP_HASH"
	fi
	echo "	Populating ETCD with discovery data.."
	# Packed format $HASH -- IP;DEVICE_LABEL(attempts to set the device hostname!);MAC;type
	interfaceEntry="$ipAddr;$deviceHostName;$macAddr;$type;$subType"
	domainVar="${SERVER_HOSTNAME#*.}"
	# Generate a host hash and input hash from the device MACaddr, making them stable.
	hostHash="$(sha256sum <<<"$macAddr-HOST" | tr -d ' \t\n-')"
	inputHash="$(sha256sum <<<"$macAddr-INPUT" | tr -d ' \t\n-')"
	KEYDATA="mod(\"/HOSTS/$deviceHostName.$domainVar\") = \"0\"

put /HOSTS/$deviceHostName.$domainVar \"$hostHash\"
put /HOSTS/$deviceHostName.$domainVar/inputs/$inputHash \"$interfaceEntry\"
put /HOSTS/$deviceHostName.$domainVar/control/type \"$type\"
put /HOSTS/$deviceHostName.$domainVar/subType \"$subType\"
put /HOSTS/$deviceHostName.$domainVar/control/IP \"$ipAddr\"
put /HOSTS/$deviceHostName.$domainVar/MAC \"${macAddr^^}\"
put /HOSTS/$deviceHostName.$domainVar/uv_encode_cmd/inputStream \"$(base64 -w 0 <<<"$UGdeviceStreamCommand")\"
put /HOSTS/$deviceHostName.$domainVar/uv_stream_cmd/subscribeStream \"$(base64 -w 0 <<<"$UGdeviceSubscribeCommand")\"
put /HOSTS/$deviceHostName.$domainVar/control/directMode \"1\"
put /HOSTS/$deviceHostName.$domainVar/control/GROUP \"$initGroupHash\"
put /HOSTS/$deviceHostName.$domainVar/control/healthStatus \"0\"
put /HOSTS/$deviceHostName.$domainVar/control/wavelet_build_completed \"1\"
del DHCP

put /HOSTS/$deviceHostName.$domainVar \"$hostHash\"
put /HOSTS/$deviceHostName.$domainVar/inputs/$inputHash \"$interfaceEntry\"
put /HOSTS/$deviceHostName.$domainVar/control/type \"$type\"
put /HOSTS/$deviceHostName.$domainVar/subType \"$subType\"
put /HOSTS/$deviceHostName.$domainVar/control/IP \"$ipAddr\"
put /HOSTS/$deviceHostName.$domainVar/MAC \"${macAddr^^}\"
put /HOSTS/$deviceHostName.$domainVar/uv_encode_cmd/inputStream \"$(base64 -w 0 <<<"$UGdeviceStreamCommand")\"
put /HOSTS/$deviceHostName.$domainVar/uv_stream_cmd/subscribeStream \"$(base64 -w 0 <<<"$UGdeviceSubscribeCommand")\"
put /HOSTS/$deviceHostName.$domainVar/control/directMode \"1\"
put /HOSTS/$deviceHostName.$domainVar/control/GROUP \"$initGroupHash\"
put /HOSTS/$deviceHostName.$domainVar/control/healthStatus \"0\"
put /HOSTS/$deviceHostName.$domainVar/control/wavelet_build_completed \"1\"
del DHCP

"
	echo "Attempting to write $KEYDATA"
	write_etcd_txn "$KEYDATA"
	KEYNAME="/HOSTS/$deviceHostName.$domainVar/control/generateConf"; KEYVALUE="1"; write_etcd_global
	KEYNAME="/HOSTS/$deviceHostName.$domainVar/control/inputUpdate"; KEYVALUE="1"; write_etcd_global &
}

get_ndi_devices(){
	# Makes an array ${ndiDevices[@]} of NDI devices NAME--IP:PORT
	ndiDevices=()
	while IFS=$'\n' read -r line; do
		[[ $line == *"ipa_ipvlan_shim"* ]] && continue
		# Only process resolved records (=)
		[[ $line != "=;"* ]] && continue
		IFS=';' read -r _ _ _ name _ _ _ ip port _ <<< "$line"
		name="${name%%[![:alnum:]_-]*}"
        ip="${ip//\\./\.}"
		ip="${ip%%[![:alnum:].-]*}"
		ndiDevices+=("${name}--${ip}:${port}")
	done <<<"$(avahi-browse -t -r -p _ndi._tcp)"
#	local ultraGridBinaryFile
#	if [[ -f "/var/wavelet_ramfs/ultragrid/squashfs-root/AppRun" ]]; then
#		binaryFile="/var/wavelet_ramfs/ultragrid/squashfs-root/AppRun"
#	else
#		binaryFile="/usr/local/bin/ultragrid/squashfs-root/AppRun"
#	fi
#	blockStart=0
#	array=()
#	ndiDevices=()
#	while IFS=$'\n' read -r line; do
#		if [[ $line ==  *'available sources'* ]]; then
#			# initialize sources
#			sources=""
#			blockStart=1
#		fi
#		if [[ $blockStart == 1 ]] && [[ $line != *'available sources'* ]] && [[ $line != *'Exit'* ]] && [[ -n $line ]]; then
#			array+=("$(echo $line)")
#		fi
#	done<<<"$("$binaryFile" --tool uv -t ndi:help)"
#	for i in "${array[@]}"; do
#			# We need to perform regex here to extract the IP address.
#			device="$(awk '{print $1}'<<<"$i")--$(grep -oP '\b(?:\d{1,3}\.){3}\d{1,3}'<<<"$i" | head -n 1)"
#			ndiDevices+=( "$device" )
#	done
}

check_etcd_env(){
	# Check to see if ETCD env vars are populated if we are invoked without args
	if [[ -z "$ETCD_WATCH_KEY" ]]; then
		exit 0
	else
		# First we need to strip and process the key, removing quotations and getting our vars.
		# ETCD_WATCH_KEY is IP:MACADDR:operation, so we split by first : delimiter
		ETCD_WATCH_VALUE="${ETCD_WATCH_VALUE//\"}"
		ipAddr="${ETCD_WATCH_VALUE%%:*}"
		macOp="${ETCD_WATCH_VALUE#*:}"
		operation="${macOp##*:}"
		macAddr="${macOp%:*}"
		parse_macaddr "$ipAddr" "$macAddr"
	fi
}


#####
#
# Main
#
####


if [[ "${ETCD_WATCH_EVENT_TYPE//\"}" == "DELETE" ]]; then
	# We won't respond to key deletion events
	exit 0
fi

# Load the server env conf file
configFile="/var/home/wavelet/config/$hostNameSys.conf"
source "$configFile"

start_timer
trap 'stop_timer "$timer_id_out"; echo "Total: ${timer_duration}s" >&2' EXIT

logName="/var/home/wavelet/logs/networkDevice.log"
hostNameSys="$(hostname)"
exec >>"$logName" 2>&1
check_etcd_env