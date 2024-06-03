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
