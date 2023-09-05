#!/bin/bash
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
echo "Ethernet connection configuration applied.."
