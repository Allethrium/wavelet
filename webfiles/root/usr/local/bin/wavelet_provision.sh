#!/bin/bash
# Calls etcd_interaction in order to provision a client
# This runs from wavelet-root on the server side, because it needs root privs to the etcd cluster
# We don't want those to be accessible from the wavelet user in an effort to be more secure

step1() {
	if [[ "$EUID" -ne 9337 ]]; then 
		echo "This step should only run under wavelet-root."
		exit 1
	fi
	echo "Reading etcd provision request.."
	# Now that we have domain enrollment for the client at this point, perhaps we could perform a lookup against IPA?
	if [[ "$ETCD_WATCH_VALUE" == *"$(dnsdomainname)"* ]]; then
		echo "Client request domain name correct, proceeding"
	else
		echo "Domain name $ETCD_WATCH_VALUE incorrect for client machine, exiting."
	exit 1
	fi
	if [[ "$ETCD_WATCH_VALUE" == *"svr"* ]]; then
		echo "Provision request cannot be a server!"
		exit 1
	fi
	# call etcd interaction to generate the host role
	echo "Calling etcd module to generate host role.."
	# This command should be run without inheritance.
	env -i bash -c "$ETCDMANAGEMENTMOD generate_etcd_host_role"
}

step2() {
	if [[ "$EUID" -ne 1337 ]]; then 
		echo "This step should only run as the wavelet user on the client machine, and responds to the key bring re-written with the expected provision data."
		exit 1
	fi
	if [[ $ETCD_WATCH_EVENT == "PUT" ]] && [[ "$ETCD_WATCH_VALUE" != "$(hostname)" ]]; then
		echo " ETCD_WATCH_VALUE env does not match this machine hostname."
		exit 0
	fi
	echo "Getting client provision data.."
	sleep 2
	"$ETCDMANAGEMENTMOD" "client_provision_get_data"
}


#####
#
# Main
#
#####

ETCDMANAGEMENTMOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_etcd_management.sh" ]]; then
	ETCDMANAGEMENTMOD="/var/wavelet_ramfs/wavelet_etcd_management.sh"
else
	ETCDMANAGEMENTMOD="/usr/local/bin/wavelet_etcd_management.sh"
fi

user="$(whoami)"
mkdir -p "/var/home/${user}/logs"
exec > "/var/home/${user}/logs/provision_request.log" 2>&1

if [[ "$1" = "2" ]]; then
	echo "step 2 provisioning activated"
	step2
else
	step1
fi