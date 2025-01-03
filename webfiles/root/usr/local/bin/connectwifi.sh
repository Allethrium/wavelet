#!/bin/bash
# Attempts to find and join a Wavelet network if it's available

get_full_bssid(){
	sleep 3
	wifibssid=$(nmcli -f BSSID device wifi | grep ${wifi_ap_mac} | head -n 1 | xargs)
	echo ${wifibssid}
}

connectwifi(){
	# Check for debug flag
	if [[ $- == *"x"* ]]; then
		# Spit out a list of wifi networks so we have something to refer to
		nmcli con show
	fi

	# Attempt to connect to the configured wifi before proceeding
	if nmcli con up $(cat /var/home/wavelet/wifi_ssid); then
		echo "Configured connection established, exiting."
		exit 0
	fi

	if [[ -f /var/prod.security.enabled ]]; then
		connectwifi_enterprise
	else
		connectwifi_psk
	fi
}

connectwifi_psk(){
	networkssid=$(cat /var/home/wavelet/wifi_ssid)
	wifipassword=$(cat /var/home/wavelet/wifi_pw)
	wifi_ap_mac=$(cat /var/home/wavelet/wifi_bssid)
	# Determine wifi ifname (what a pain..)
	ifname=$(nmcli dev show | grep wifi -B1 | head -n 1 | awk '{print $2}')

	# Keep scanning until we get a match on wifi_ap_mac
	until get_full_bssid | grep -m 1 "${wifi_ap_mac}"; do
		nmcli dev wifi rescan
	done
	# We need to do this once more, or the variable isn't populated.
	wifibssid=$(get_full_bssid)
	# Spit this out for notation purposes
	nmcli con show
	echo -e "Found WiFi BSSID match! It is: ${wifibssid}\n"

	# Remove any old connection UUID's with the same name
	nmcli con del ${networkssid}
	# Create new connection
	response=$(nmcli connection add type wifi con-name ${networkssid} ifname ${ifname} ssid ${networkssid})
	currentuuid=$(echo $response | awk '{print $3}' | sed 's|(||g' | sed 's|)||g')
	echo "Created Wavelet network connection with UUID: ${currentuuid}"
	echo -e "Available network connections:\n$(nmcli con show)"
	for connection in $(nmcli -g NAME con show); do
		if [[ ${connection} == ${networkssid} ]]; then
			echo "${connection} is a wavelet-configured WiFi connection, proceeding.."
			uuid=$(nmcli -g connection.uuid con show "${connection}")
			echo -e "connection is the active UUID of:${uuid}\nConfiguring and setting as ON"
			nmcli -g connection.uuid con mod ${uuid} wifi-sec.key-mgmt wpa-psk wifi-sec.psk ${wifipassword}
			nmcli -g connection.uuid con mod ${uuid} connection.autoconnect yes
			nmcli -g connection.uuid con up ${uuid}
			echo "${uuid}" > /var/home/wavelet/wifi.${networkssid}.key
		else
			echo "Not a wavelet configured wifi connection, ignoring"
		fi
	done		

	sleep 2
	if [ $? -eq 0 ]; then
		echo -e "Connection successful!  Continuing..\n"
	else
		if [[ $? = *"Error: bssid argument is missing"* ]]; then
			echo -e "SSID is broadcast, retrying without BSSID argument..\n"
			nmcli dev wifi connect ${networkssid} password ${wifipassword}
		fi
			echo -e "Continuing to connect for three more tries..\n"
			sleep 2
			nmcli dev wifi connect ${networkssid} hidden yes password ${wifipassword} bssid ${wifibssid}
			sleep 2
			nmcli dev wifi connect ${networkssid} hidden yes password ${wifipassword} bssid ${wifibssid}
			sleep 2
			nmcli dev wifi connect ${networkssid} hidden yes password ${wifipassword} bssid ${wifibssid}
	fi
}

connectwifi_enterprise(){   
	# Won't work right now, more of a bones until we get the core stuff refactored.       
	networkssid=$(cat /var/home/wavelet/wifi_ssid)
	wifi_ap_mac=$(cat /var/home/wavelet/wifi_bssid)
	# Determine wifi ifname (what a pain..)
	ifname=$(nmcli dev show | grep wifi -B1 | head -n 1 | awk '{print $2}')
	# Generates an nmcli connection with the appropriate certificates
	until get_full_bssid | grep -m 1 "${wifi_ap_mac}"; do
		nmcli dev wifi rescan
		get_full_bssid
	done

	# Define paths to pregenerated certificates.
	# These might be generated and managed by the DC, or we could do them manually if we need to at some point.
	wifiCACert=/etc/ipa/ca.crt
	wifiClientCert=/etc/pki/tls/certs/this_wificlient.crt
	wifiClientKey=/etc/pki/tls/private/this_wificlient.crt
	wifiServerKey=/etc/pki/tls/certs/wifiserver.crt

	# Some nmcli examples.  We would just be using certificates for our intended setup without any identity passwords.
	#nmcli connection add type wifi con-name "MySSID" ifname wlp3s0 ssid "MySSID" -- wifi-sec.key-mgmt wpa-eap 802-1x.eap ttls 802-1x.phase2-auth mschapv2 802-1x.identity "USERNAME" 
	#nmcli connection add type wifi con-name "MySSID" ifname wlp3s0 ssid "MySSID" -- wifi-sec.key-mgmt wpa-eap 802-1x.eap tls 802-1x.identity "USERNAME" 802-1x.ca-cert ~/ca.pem 802-1x.client-cert ~/cert.pem  802-1x.private-key-password "..." 802-1x.private-key ~/key.pem

	# nmcli connection add type wifi con-name "${networkssid}" ifname ${ifname} ssid "${networkssid}" \
	# -- wifi-sec.key-mgmt wpa-eap 802-1x.eap tls 802-1x.identity "WAVELET" \
	# 802-1x.ca-cert ${wifiCACert} \
	# 802-1x.client-cert ${wifiClientCert} \
	# 802-1x.private-key-password "${privateKeyPassword}" \ 
	# 802-1x.private-key ${wifiClientKey}
}

detect_disable_ethernet(){
	if [[ -f /var/no.wifi ]]; then
		echo -e "The /var/no.wifi flag is set.  Please remove this file if this host should utilize wireless connectivity."
		exit 0
	else
		ethernetInterfaceUUID=$(nmcli con show | grep ethernet | awk '{print $4}')
		echo -e "Ethernet Interface UUID discovered: ${ethernetInterfaceUUID}"
		if [[ $(nmcli -g ip4.address con show uuid ${ethernetInterfaceUUID}) == "" ]]; then
			# Simplify this from the previous loop, just find ethernet interface and awk for connection UUID, then disable.
			echo "Ethernet connection detected with no IPV4 address.  Ethernet is disconnected or disabled, doing nothing."
		else
			nmcli -f uuid con down "${ethernetInterfaceUUID}"
			echo -e "The primary ethernet connection with UUID ${ethernetInterfaceUUID} has been disabled.\nTo re-enable, you can use:\nnmcli con up ${ethernetInterfaceUUID}\nOr:\nnmtui\nFor a gui interface."
		fi	
	fi
}

set_ethernet_mtu(){
	for interface in $(nmcli con show | grep ethernet | awk '{print $3}'); do
			nmcli con mod ${interface} mtu 9000
	done
}

#####
#
# Main
#
#####


logName="/var/home/wavelet/connectwifi.log"
if [[ -e $logName || -L $logName ]] ; then
	i=0
	while [[ -e $logName-$i || -L $logName-$i ]] ; do
		let i++
	done
	logName=$logName-$i
fi
#set -x
exec >${logName} 2>&1


if [[ $(hostname) = *"svr"* ]]; then
	echo -e "This script enables wifi and disables other networking devices.  It is highly recommended to have the server running on a wired link."
	echo -e "If you want to run the server via a WiFi connection, this should be configured and enabled manually via nmtui or nmcli."
	echo -e "Performance will likely suffer as a result."
	exit 0
fi

if [[ -f /var/no.wifi ]]; then
	echo -e "The /var/no.wifi flag is set.  Please remove this file if this host should utilize wireless connectivity."
	exit 0
fi

# Ensure wifi radio is on
nmcli r wifi on

if [[ $1 == *"E"* ]]; then
	echo -e "module run with -E flag, ethernet connection will remain enabled"
	set_ethernet_mtu
	connectwifi
else
	echo -e "no flags with module call, disabling ethernet connection."
	connectwifi
	detect_disable_ethernet
fi