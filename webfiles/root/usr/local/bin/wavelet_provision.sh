#!/bin/bash
# Calls etcd_interaction in order to provision a client
# This is the only service that runs from wavelet-root on the server side, because it needs root privs to the etcd cluster
# I didn't want those to be accessible from the wavelet user in an effort to be more secure, nor did I want this stuff running as root.

step1() {
	if [[ "$EUID" -ne 9337 ]]; then 
		echo "This step should only run under wavelet-root."
		exit 1
	fi
	KEYNAME="/PROV/REQUEST"; printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}")
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
}

step2() {
	if [[ "$EUID" -ne 1337 ]]; then 
		echo "This step should only run as the wavelet user on the client machine and responds to the key bring re-written with the provision data."
		exit 1
	fi
	echo "Getting client provision data.."
	/usr/local/bin/wavelet_etcd_interaction.sh "client_provision_data"
}


#####
#
# Main
#
#####

#set -x
user=$(whoami)
mkdir -p /var/home/${user}/logs
exec > /var/home/${user}/logs/provision_request.log 2>&1
inputargs=$@

if [[ $@ = "2" ]]; then
	echo "step 2 provisioning activated"
	step2
else
	step1
fi