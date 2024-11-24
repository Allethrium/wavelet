#!/bin/bash
# Attempts to find and join a Wavelet network if it's available

# These are now defined by inline files in ignition so they can be "securely" customized ahead of time
networkssid=$(cat /var/home/wavelet/wifi_ssid)
wifipassword=$(cat /var/home/wavelet/wifi_pw)
wifi_ap_mac=$(cat /var/home/wavelet/wifi_bssid)

connectwifi(){
# 5/28/2024 - fix echo to cat so connectwifi spits out proper values and connects appropriately.
	nmcli dev wifi rescan
	sleep 5
	nmcli dev wifi rescan
	sleep 3
	wifibssid=$(nmcli -f BSSID device wifi | grep ${wifi_ap_mac} | head -n 1)
	nmcli dev wifi connect ${networkssid} hidden yes password ${wifipassword} bssid ${wifibssid}
	while read i; do
		if [[ $i = "Error: bssid argument is missing" ]]; then
			echo -e "SSID is broadcast, retrying without BSSID argument..\n"
			nmcli dev wifi connect ${networkssid} password ${wifipassword}
		fi
	done
	sleep 3
	nmcli dev wifi connect ${networkssid} hidden yes password ${wifipassword} bssid ${wifibssid}
	sleep 3
	nmcli dev wifi connect ${networkssid} hidden yes password ${wifipassword} bssid ${wifibssid}
}

# If security layer is enabled and we aren't running with a PSK, this will wind up looking quite different

connectwifi_enterprise(){          
	nmcli dev wifi rescan
	sleep 5
	nmcli dev wifi rescan
	sleep 3
	wifiCACert=/etc/ipa/ca.crt
	wifiClientCert=/etc/pki/tls/certs/wificlient.crt
	wifiClientKey=/etc/pki/tls/private/wificlient.crt
	#nmcli <blablabla>
}

# Main
#if curl 'https://192.168.1.32:8080' > HTML_Output # curl the provioning httpd server succeeds
#  echo "we have connectivity"
#else
if [[ $(hostname) = *"svr"* ]]; then
	echo -e "This script enables wifi and disables other networking devices.  It is highly recommended to have the server running on a wired link.  Exiting."
	exit 1
fi
connectwifi
#fi