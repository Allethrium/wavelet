#!/bin/bash

# This module is called from wavelet_network_device.sh and is designed to update BIND if the security layer is enabled.
# We can have DNS resolution of additional non-domain devices
# Since it's pointless attempting to track devices without valid hostnames, it's only called once a device has been properly parsed
# The other option is dumping DNSMASQ and rebasing DHCP/PXE on to DHCPD or Kea, 
# However, the fact dhcpd isn't supported and the Kea JSON config files are a pain to edit programatically are putting me off that route..

deviceHostName=$1
dnsmasq_ipAddr=$2

if [[ -f /var/tmp/prod.security.enabled ]]; then
	echo -e "security layer enabled, FreeIPA/BIND are handling DNS on this system!\n"
	if [[ ${4} == "" ]]; then
		echo "hostname field is empty, using MAC address instead..\n"
		deviceHostName="noHostName_${dnsmasq_mac}"
	else
		deviceHostName="${4}"
	fi
	echo -e "Generating DNS Record data..\n"
	ipa dnsrecord-add $(dnsdomainname) $(deviceHostName) --a-ip-address=${dnsmasq_ipAddr} --a-create-reverse
fi