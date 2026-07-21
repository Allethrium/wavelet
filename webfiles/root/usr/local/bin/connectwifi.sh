#!/bin/bash


# Attempts to find and join a Wavelet network if it's available
# Typically called from wavelet_build after the display manager has launched

# Source the wavelet configuration helper functions
if [[ -f "/etc/wavelet.conf" ]]; then
    source "/etc/wavelet.conf"
fi

if [[ -f /var/wavelet_ramfs/etcd_interaction_hooks.sh ]]; then
  source /var/wavelet_ramfs/etcd_interaction_hooks.sh
else
  source /usr/local/bin/etcd_interaction_hooks.sh
fi


get_full_bssid(){
	sleep 2
	WIFI_BSSID=$(nmcli -f BSSID device wifi | grep "${WIFI_BSSID^^}" | head -n 1 | xargs)
	echo "$WIFI_BSSID"
}

connectwifi(){
	# Check for debug flag
	if [[ $- == *"x"* ]]; then
		# Spit out a list of wifi networks so we have something to refer to
		nmcli con show
	fi
	# Attempt to connect to the configured wifi before proceeding
	if nmcli con up "$WIFI_SSID"; then
		echo "	Configured connection established, exiting."
		exit 0
	else
		# Recreate the network
		# We now only support WPA2/3-ENT
		connectwifi_enterprise
	fi
}

connectwifi_psk(){
	# Obsolete
	ifname=$(nmcli dev show | grep wifi -B1 | head -n 1 | awk '{print $2}')
	# Keep scanning until we get a match on the BSSID
	until get_full_bssid | grep -m 1 "${WIFI_BSSID^^}"; do
		nmcli dev wifi rescan
	done
	# We need to do this once more, or the variable isn't populated.
	FULL_WIFI_BSSID=$(get_full_bssid)
	nmcli con show
	echo -e "	Found WiFi BSSID match! It is: $FULL_WIFI_BSSID\n"

	# Remove any old connection UUID's with the same name
	nmcli con del "$WIFI_SSID"
	# Create new connection
	response=$(nmcli connection add type wifi con-name "$WIFI_SSID" ifname "$ifname" ssid "$WIFI_SSID")
	currentuuid=$(echo "$response" | awk '{print $3}' | sed 's|(||g' | sed 's|)||g')
	echo "	Created Wavelet network connection with UUID: $currentuuid"
	echo -e "	Available network connections:\n$(nmcli con show)"
	for connection in $(nmcli -g NAME con show); do
		if [[ "$connection" == "$WIFI_SSID" ]]; then
			echo "	${connection} is a wavelet-configured WiFi connection, proceeding.."
			uuid=$(nmcli -g connection.uuid con show "$connection")
			echo -e "	connection is the active UUID of:${uuid}\nConfiguring and setting as ON"
			nmcli -g connection.uuid con mod "$uuid" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$wifipassword"
			nmcli -g connection.uuid con mod "$uuid" connection.autoconnect yes
			nmcli -g connection.uuid con up "$uuid"
			echo "${uuid}" > "/var/home/wavelet/config/wifi.$WIFI_SSID.key"
		fi
	done		

	sleep 2
	if [ $? -eq 0 ]; then
		echo -e "	Connection successful!  Continuing..\n"
	else
		if [[ $? = *"Error: bssid argument is missing"* ]]; then
			echo -e "	SSID is broadcast, retrying without BSSID argument..\n"
			cmd=(nmcli dev wifi connect "$WIFI_SSID" password "$wifipassword")
			"${cmd[@]}"
		fi
			echo -e "	Continuing to connect for three more tries..\n"
			cmd=(nmcli dev wifi connect "$WIFI_SSID" hidden yes password "$wifipassword" bssid "$wifibssid")
			"${cmd[@]}"; sleep 2; "${cmd[@]}"; sleep 2; "${cmd[@]}"
	fi
}

connectwifi_enterprise(){   
	# This should spawn on client spinup
	# The generated connection should be managable from the user account via the policykit rules.
	clientCertificateName="eaptls-client-$hostNameSys.crt"
	clientKeyName="eaptls-client-$hostNameSys.key"
	if [[ ! -f "/etc/pki/tls/certs/$clientCertificateName" ]] || [[ ! -f "/etc/pki/tls/private/$clientKeyName" ]]; then
    	echo "  ERROR: Missing client certificates. Please ensure 802.1x certificates were issued."
    	return 1
	fi
	# Keep scanning until we get a match on our partial BSSID
	attempt=0
	max_attempts=60
	until get_full_bssid | grep -m 1 "${WIFI_BSSID^^}" || [ $attempt -ge $max_attempts ]; do
	  echo "  Scanning for WiFi network (attempt $((++attempt))/$max_attempts)..."
		nmcli dev wifi rescan
		sleep 5
	done
	if [ $attempt -ge $max_attempts ]; then
		echo "  ERROR: Could not find the configured WiFi network. Please check if access point is available."
		return 1
	fi

	# We need to do this once more, or the variable isn't populated.
	FULL_WIFI_BSSID="$(get_full_bssid)"
	echo "	WiFi AP BSSID located: $FULL_WIFI_BSSID"
	ifname="$(nmcli dev show | grep wifi -B1 | head -n 1 | awk '{print $2}')"
	if [ -z "$ifname" ]; then
    	echo "ERROR: No WiFi interface detected"
    	return 1
	fi
	conn_id="${WIFI_SSID}_${hostNameSys}"
	uuid="$(cat /proc/sys/kernel/random/uuid)"

	# Remove any existing connection with the same name
	nmcli con del "$conn_id" 2>/dev/null
	# Generates an nmcli connection with the appropriate certificates
	# Our certificates should already be generated during wavelet-install-client immediately after domain enrollment
	# Our private key doesn't have a password configured, so we need to set password-flags=4
	file="/etc/NetworkManager/system-connections/wavelet-8021x.nmconnection"
	cat > "$file" << EOF
[connection]
id=${WIFI_SSID}_${hostNameSys}
uuid=$(cat /proc/sys/kernel/random/uuid)
type=wifi
interface-name=${ifname}
autoconnect=true
autoconnect-priority=100
autoconnect-retries=0
wait-activation-delay=30

[wifi]
mode=infrastructure
ssid=$WIFI_SSID
powersave=2

[wifi-security]
key-mgmt=wpa-eap

[802-1x]
eap=tls
identity=anonymous-od-type-a
phase1-auth-flags=32
ca-cert=/etc/ipa/ca.crt
client-cert=/etc/pki/tls/certs/${clientCertificateName}
private-key=/etc/pki/tls/private/${clientKeyName}
private-key-password-flags=4
password=FALSE_EAP_TLS_PASSWORD
password-flags=1

[ipv4]
method=auto
dhcp-timeout=60

[ipv6]
addr-gen-mode=default
method=auto

[proxy]
EOF
	chmod 0600 "$file"
    systemctl restart NetworkManager.service
    nmcli connection reload
    echo "	WPA2-Enterprise profile created successfully"
    # Try to activate the connection
    echo "	Activating WPA2-Enterprise connection..."
      if nmcli con up "$conn_id"; then
        echo "WPA2-Enterprise connection activated successfully!"
        return 0
      else
        echo "Failed to activate connection (this is normal) - Will retry in 10 seconds..."
        sleep 10
        nmcli con up "$conn_id"
      fi
      echo "Failed to create WPA2-Enterprise connection profile"
      echo "You can manually retry by issuing the following terminal command: nmcli con up $conn_id"
      return 1
}

detect_disable_ethernet(){
    # Check for other active network connections (e.g., Wi-Fi, Mobile Data, Secondary Ethernet) before disabling
    # We exclude standard ethernet types and the specific UUID we are targeting to ensure we don't block other Ethernet links
    local ethernet_activeUUID; local wifi_activeUUID
    ethernet_activeUUID="$(nmcli -t -f UUID,TYPE,STATE con show --active | grep '802-3-ethernet' | awk -F ':' '{print $1}')"
    wifi_activeUUID="$(nmcli -t -f UUID,TYPE,STATE con show --active | grep '802-11-wireless' | awk -F ':' '{print $1}')"
    if [[ -n "$ethernet_activeUUID" ]] && [[ -z "$wifi_activeUUID" ]]; then
        echo "  There is an active ethernet network connection detected, but no active WiFi."
        echo "  Disabling ethernet will offline this device and provisioning will block, therefore we end the process here."
        echo "  Please verify the Wireless Access Point is configured correctly, ignore these messages to continue in a wired mode."
        exit 0
    fi
    # Check for a manual no-wifi flag as set in the installer
    flag_value=$(grep "^${WIFI_MODE_ENABLED}=" /etc/wavelet/wavelet.conf | cut -d'=' -f2 | tr -d '\r')
	if [[ "$flag_value" == 1 ]]; then
		echo -e "	The WIFI_MODE_ENABLED flag is disabled.  Please enable this if this host should utilize wireless connectivity."
		exit 0
	else
		nmcli con down "$ethernet_activeUUID"
		nmcli con mod "$ethernet_activeUUID" connection.autoconnect no
		echo "	The primary ethernet connection with UUID $ethernet_activeUUID has been disabled."
		echo -e "	To re-enable, you can use:\n	nmcli con up $ethernet_activeUUID\n	Or:\n	nmtui\n	For a gui interface."
	fi
}

set_ethernet_mtu(){
	for interface in $(nmcli con show | grep ethernet | awk '{print $3}'); do
			nmcli con mod "${interface}" mtu 9000
	done
}


#####
#
# Main
#
#####


logName="/var/home/wavelet/logs/connectwifi.log"
if [[ -e "$logName" || -L "$logName" ]] ; then
	i=0
	while [[ -e "$logName-$i" || -L "$logName-$i" ]] ; do
		(( i++ ))
	done
	logName="$logName-$i"
fi
exec >"${logName}" 2>&1

# In this case we only want the non-fqdn
hostNameSys="$(hostname -s)"

if [[ "$hostNameSys" = *"svr"* ]]; then
	echo "	This script enables wifi and disables other networking devices.  It is highly recommended to have the server running on a wired link."
	echo "	If you want to run the server via a WiFi connection, this should be configured and enabled manually via nmtui or nmcli."
	echo "	Performance will likely suffer as a result."
	exit 0
fi

if [[ "$ENABLE_WIFI" == 1 ]]; then
	echo "	The WIFI_MODE_ENABLED flag is disabled.  Please enable this if this host should utilize wireless connectivity."
	exit 0
fi

# Ensure wifi radio is on
nmcli r wifi on

if [[ "$1" == *"E"* ]]; then
	echo "	Module run with -E flag, ethernet connection will remain enabled"
	set_ethernet_mtu
	connectwifi_enterprise
else
	echo "	No flags with module call, disabling ethernet connection."
	connectwifi_enterprise
fi

# Attempt to disable ethernet, or leave on if it's the only available connection
detect_disable_ethernet