#!/bin/bash
# Calls etcd_interaction in order to provision a client
# This is the only service that runs from wavelet-root, because it needs root privs to the etcd cluster
# I didn't want those to be accessible from the wavelet user in an effort to be more secure, nor did I want this stuff running as root.

if [ "$EUID" -ne 9337 ]
	then echo "This module should not only run under wavelet-root."
	exit 1
fi

KEYNAME="/PROV/REQUEST"; /usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}"

if [[ ${printvalue} == *"$(dnsdomainname)" ]]; then
	echo "Client request domain name correct, proceeding"
else
	echo "Domain name incorrect for client machine, exiting."
	exit 1
fi

if [[ ${printvalue} == "*svr*" ]]; then
	echo "Provision request cannot be a server!"
	exit 1
fi

# call etcd interaction to generate the host role
/usr/local/bin/wavelet_etcd_interaction.sh "generate_etcd_host_role"