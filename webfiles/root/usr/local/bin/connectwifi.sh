#!/bin/bash
# Attempts to find and join a Wavelet network if it's available

get_full_bssid(){
	sleep 3
	wifibssid=$(nmcli -f BSSID device wifi | grep ${wifi_ap_mac} | head -n 1 | xargs)
	echo ${wifibssid}
}

connectwifi(){
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
	echo -e "\nFound WiFi BSSID match! It is: ${wifibssid}\n"

	nmcli connection add type wifi con-name ${networkssid} ifname ${ifname} ssid ${networkssid}
	nmcli connection modify ${networkssid} wifi-sec.key-mgmt wpa-psk wifi-sec.psk ${wifipassword}
	nmcli dev set ${ifname} autoconnect yes
	nmcli connection up ${networkssid}

	
	if [ $? -eq 0 ]; then
		echo -e "\nConnection successful!  Continuing..\n"
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
	else
		# We disable ethernet preferentially if we have two active connections
		# This prevents some of the IP detection automation from having issues.
		# This should have been done already once the decoder provisioned and successfully connected to wifi.
		# Add another filter to exclude veth interfaces
		for interface in $(ip link show | awk '{print $2}' | grep ":$" | cut -d ':' -f1); do
			if [[ $(nmcli dev show "${interface}" | grep "connected") ]] && \
			[[ $(nmcli dev show "${interface}" | grep "ethernet") ]] && \
			[[ $(nmcli device status | grep -a 'wifi.*connect') ]] && \
			[[ $(nmcli dev show "${interface}") != *"veth"* ]]; then
				echo -e "${interface} is an ethernet connection, active WiFi connection also detected..."
				wifiFound="1"
				ethernetFound="1"
				ethernetInterface="${interface}"
			fi
		done
		nmcli device disconnect "${ethernetInterface}"
		echo -e "Interface ${ethernetInterface} has been disabled.\n\nTo re-enable, you can use:\nnmcli device up ${ethernetInterface}\nOr:\nnmtui\nFor a gui interface."
	fi
}

set_ethernet_mtu(){
	for interface in $(nmcli dev show | grep ethernet -B1 | head -n 1 | awk '{print $2}'); do
		if [[ $(ip link show dev "${interface}" | grep "link/ether") ]]; then 
			echo ${interface}
			ip link set dev ${interface} mtu 9000
		fi
	done
}

#####
#
# Main
#
#####

#set -x
exec >/home/wavelet/connectwifi.log 2>&1

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