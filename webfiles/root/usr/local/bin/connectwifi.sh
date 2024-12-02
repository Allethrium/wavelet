#!/bin/bash
# Attempts to find and join a Wavelet network if it's available

connectwifi(){
	# 5/28/2024 - fix echo to cat so connectwifi spits out proper values and connects appropriately.
	# These are now defined by inline files in ignition so they can be "securely" customized ahead of time
	networkssid=$(cat /var/home/wavelet/wifi_ssid)
	wifipassword=$(cat /var/home/wavelet/wifi_pw)
	wifi_ap_mac=$(cat /var/home/wavelet/wifi_bssid)

	echo -e "802-11-wireless-security.psk:${wifipassword}" > /home/wavelet/wpa_psk.file

	nmcli dev wifi rescan
	sleep 5
	nmcli dev wifi rescan
	sleep 3
	wifibssid=$(nmcli -f BSSID device wifi | grep ${wifi_ap_mac} | head -n 1 | xargs )

	nmcli dev wifi connect ${networkssid} hidden yes password ${wifipassword} bssid ${wifibssid}
	
	if [ $? -eq 0 ]; then
		echo -e "\nConnection successful!  Continuing..\n"
	else
		if [[ $? = *"Error: bssid argument is missing"* ]]; then
			echo -e "SSID is broadcast, retrying without BSSID argument..\n"
			nmcli dev wifi connect ${networkssid} password ${wifipassword}
		fi
			echo -e "Continuing to connect for three more tries..\n"
			nmcli dev wifi connect ${networkssid} hidden yes password ${wifipassword} bssid ${wifibssid}
			sleep 2
			nmcli dev wifi connect ${networkssid} hidden yes password ${wifipassword} bssid ${wifibssid}
			sleep 2
			nmcli dev wifi connect ${networkssid} hidden yes password ${wifipassword} bssid ${wifibssid}
	fi
}

connectwifi_enterprise(){          
	# Generates an nmcli connection with the appropriate certificates
	nmcli dev wifi rescan
	sleep 3
	nmcli dev wifi rescan
	sleep 3
	wifiCACert=/etc/ipa/ca.crt
	wifiClientCert=/etc/pki/tls/certs/wificlient.crt
	wifiClientKey=/etc/pki/tls/private/wificlient.crt
	# Some nmcli examples.  We would just be using certificates for our intended setup without any identity passwords.
	#nmcli connection add type wifi con-name "MySSID" ifname wlp3s0 ssid "MySSID" -- wifi-sec.key-mgmt wpa-eap 802-1x.eap ttls 802-1x.phase2-auth mschapv2 802-1x.identity "USERNAME" 
	#nmcli connection add type wifi con-name "MySSID" ifname wlp3s0 ssid "MySSID" -- wifi-sec.key-mgmt wpa-eap 802-1x.eap tls 802-1x.identity "USERNAME" 802-1x.ca-cert ~/ca.pem 802-1x.client-cert ~/cert.pem  802-1x.private-key-password "..." 802-1x.private-key ~/key.pem
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
		nmcli device down "${ethernetInterface}"
		echo -e "Interface ${ethernetInterface} has been disabled.\n\nTo re-enable, you can use:\nnmcli device up ${ethernetInterface}\n\nor:\nnmtui\n"
	fi
}

if [[ $(hostname) = *"svr"* ]]; then
	echo -e "This script enables wifi and disables other networking devices.  It is highly recommended to have the server running on a wired link."
	echo -e "If you want to run the server off of a WiFi connection, this should be configured and enabled manually via nmtui or nmcli."
	echo -e "Not that performance will likely suffer as a result."
	exit 0
fi

if [[ -f /var/no.wifi ]]; then
	echo -e "The /var/no.wifi flag is set.  Please remove this file if this host should utilize wireless connectivity."
	exit 0
fi

#####
#
# Main
#
#####


#set -x
exec >/home/wavelet/connectwifi.log 2>&1
connectwifi
detect_disable_ethernet