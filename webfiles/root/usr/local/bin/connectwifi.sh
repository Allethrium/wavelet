#!/bin/bash
# Attempts to find and join a Wavelet network if it's available

# DEFAULTS - edit these to your system's specs
networkssid="Wavelet-1"
wifipassword="xnSLvFKyyzNXd0wuN79lfC0oEBzdhsg4"
wifi_ap_mac="70:47:"

connectwifi(){
	#read -p "Please enter WiFi SSID" networkssid
	#read -p "Please enter Wifi Network Password:" wifipassword
	# noticed on the test systems it takes a couple of tries to successfully connect
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

