#!/bin/bash
# Attempts to find and join a Wavelet network if it's available

# These are now defined by inline files in ignition so they can be "securely" customized ahead of time
networkssid=$(echo /var/home/wavelet/wifi_ssid)
wifipassword=$(echo /var/home/wavelet/wifi_ssid)
wifi_ap_mac=$(echo /var/home/wavelet/wifi_pw)

connectwifi(){
	nmcli dev wifi rescan
	sleep 5
	nmcli dev wifi rescan
	sleep 3
	wifibssid=$(nmcli -f BSSID device wifi | grep ${wifi_ap_mac} | head -n 1)
	nmcli dev wifi connect ${networkssid} hidden yes password ${wifipassword} bssid ${wifibssid}
	sleep 3
	nmcli dev wifi connect ${networkssid} hidden yes password ${wifipassword} bssid ${wifibssid}
	sleep 3
	nmcli dev wifi connect ${networkssid} hidden yes password ${wifipassword} bssid ${wifibssid}
}

# Main
if nc -zw1 http://192.168.1.32:8180; then
  echo "we have connectivity"
else
 connectwifi
fi