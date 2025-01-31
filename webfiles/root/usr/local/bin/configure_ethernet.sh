#!/bin/bash

detect_self(){
systemctl --user daemon-reload
	echo -e "Hostname is ${hostNameSys}\n"
	case ${hostNameSys} in
	enc*) 					event_subordinate
	;;
	dec*)					event_subordinate
	;;
	svr*)					event_server
	;;
	*) 					echo -e "This device Hostname is not set approprately, exiting \n" && exit 0
	;;
	esac
}

event_server(){
# Ensures static IP is set on the server
VAR=$(nmcli -g name connection show | grep "Wired" | head -1)
nmcli connection mod '${VAR}' \
        ipv4.method manual \
        ipv4.addresses 192.168.1.32/24 \
        ipv4.gateway 192.168.1.1 \
        ipv4.dns 192.168.1.32 \
        +ipv4.dns 192.168.1.1 \
        +ipv4.dns 9.9.9.9 \
        connection.autoconnect yes
nmcli con down ${VAR}
nmcli con up ${VAR}
echo "Static Ethernet connection configuration applied.."
}

event_subordinate(){
VAR=$(nmcli -g name connection show | grep "Wired" | head -1)
# Forces DNS configuration 
nmcli connection mod '${VAR}' \
        ipv4.method auto \
        ipv4.dns 192.168.1.32 \
        +ipv4.dns 192.168.1.1 \
        +ipv4.dns 9.9.9.9 \
        connection.autoconnect yes
nmcli con down ${VAR}
nmcli con up ${VAR}
echo "Static Ethernet connection configuration applied.."
}

hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
detect_self