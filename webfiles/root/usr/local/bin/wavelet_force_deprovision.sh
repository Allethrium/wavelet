#!/bin/bash
#
# This module is run exclusively on the server, and activated by the /HOSTS/ deprovision flag in that prefix.
# This does result in two prefix watchers on hosts, regrettably.

# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
ETCDINTERACTIONHOOKS=""
if [[ -f "/var/wavelet_ramfs/etcd_interaction_hooks.sh" ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source /usr/local/bin/etcd_interaction_hooks.sh
	ETCDINTERACTIONMOD="/usr/local/bin/etcd_interaction_hooks.sh"
fi

ETCD_CREDENTIALS_MOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_secure_credentials.sh" ]]; then
	source "/var/wavelet_ramfs/wavelet_secure_credentials.sh"
	ETCD_CREDENTIALS_MOD="/var/wavelet_ramfs/wavelet_secure_credentials.sh"
else
	source /usr/local/bin/wavelet_secure_credentials.sh
	ETCD_CREDENTIALS_MOD="/usr/local/bin/wavelet_secure_credentials.sh"
fi


# This task runs inside of the root user context
# Therefore it somewhat replicates the functions of the orchestrator

event_server(){
	# Filter our trigger env
	triggerKey="$ETCD_WATCH_KEY"
	triggerValue="$ETCD_WATCH_VALUE"
	if [[ "$triggerKey" != *"/DEPROVISION"* ]] && [[ "$triggerValue" != 1 ]]; then
		exit 0
	fi
	keyHostName="${triggerKey#*/HOSTS/}"; keyHostName="${keyHostName%%/*}"
	if [[ -z "$keyHostName" ]]; then
	  exit 0
	fi
	KEYNAME="/HOSTS/$keyHostName"; read_etcd_global; hostHash="$printvalue"
	KEYNAME="/HOSTS/$keyHostName/control/GROUP"; read_etcd_global; hostGroup="$printvalue"
	# If this isn't a deprovision key, do nothing.
	if [[ "$triggerKey" == *"svr"* ]]; then
		echo "	Removing the server would be silly!"
		exit 0
	fi
	check_and_wait
}

check_and_wait(){
	# Checks the deprovision flag is 1, then checks the system deprovision active flag.  If no changes occur in 30s, move to next step.
	echo "UI deprovision key is set to 1, setting the system deprovision key and waiting"
	# Get the target host name from our watch key
	etcdKey="${ETCD_WATCH_KEY//\"}"
	etcdValue="${ETCD_WATCH_VALUE//\"}"
	targetHostKey=${etcdKey%/*}
	KEYNAME="$targetHostKey"; read_etcd_global
	if [[ -z "$printvalue" ]]; then
		echo "	ERROR could not resolve host hash!  Exiting."
		KEYNAME="$targetHostKey/control/healthStatus"; KEYVALUE="FTL:  DEPROVISION FAILURE!"; write_etcd_global &
		exit 1
	fi
	# We have the host hash and update health status with the current stage of the process
	targetHostHash="$printvalue"
	KEYNAME="$targetHostKey/DEPROVISION_ACTIVE"; KEYVALUE=1; write_etcd_global &
	KEYNAME="$targetHostKey/control/healthStatus"; KEYVALUE="INFO:  DEPROVISIONING"; write_etcd_global &
	# Check if this host is currently an encoder and running a video signal, if it is, we'll need to reset the group source elsewhere.
	KEYNAME="/UI/HOSTS/$targetHostHash/control/GROUP"; read_etcd_global; groupHash="$printvalue"
	KEYNAME="/UI/HOSTS/$groupHash/control/sourceHash"; read_etcd_global; targetGroupVideoSourceHash="$printvalue"
	KEYNAME="/UI/HOSTS/$targetHostHash/inputs/"; read_etcd_prefix_keys
	inputs=()
	if [[ -n "$printvalue" ]]; then
		while IFS= read -r line; do
            inputs+=("${line#*/inputs/}")
            break
        done <<<"$printvalue"
        for input in "${inputs[@]}"; do
        	if [[ "$input" == "$targetGroupVideoSourceHash" ]]; then
        		# We write the group's sourceHash back to the static image by default.
        		# N.B - This will also logically reset video sources on any chained groups, also.
        		KEYVALUE="1"; write_etcd_global
        	fi
        done
	fi
	# After thirty seconds of giving the host time to clean its own keys up, we step in to remove anything else that may still remain:
	sleep 30
	echo "	Cleaning up serverside.."
	targetHostName="${targetHostKey##*/}"
	destroy_host_role
	deleteHostFromDomain
	KEYNAME="/UI/HOSTS/$targetHostHash"; delete_etcd_key_prefix_global
	KEYNAME="/HOSTS/$targetHostName"; delete_etcd_key_prefix_global
	exit 0
}

execute_etcd_cmd() {
	local cmd="$1"
	echo "Executing: $cmd" >> "/var/home/$user/logs/etcdlog.log"
	eval "etcdctl $cmd"
}

destroy_host_role() {
	# Destroys the etcd role + credentials for the selected host
	# Called from wavelet_force_deprovision
	if [[ "$EUID" -ne 9337 ]]; then
		echo "	Please run as wavelet-root" >> "/var/home/$user/logs/etcdlog.log"
		exit
	fi
	# Log directory setup
	user="wavelet-root"
	mkdir -p "/var/home/$user/logs"
	mkdir -p "/var/home/$user/config"
	# Get user arguments from secure credentials (will fail if run without etcd root user)
	export ETCDCTL_ENDPOINTS="https://$(cat /var/serverhostname.txt):2379"
	export ETCDCTL_CACERT="/etc/ipa/ca.crt"
	generate_etcd_userarg "user=wavelet-root" "extraargs=root"
	if [[ "$ETCDCTL_USER" != "root" ]]; then
		echo "	Etcd user incorrect, please check env!"
		exit 1
	fi
	clientHostNameShort="${targetHostName:0:7}"
	if [[ -z $clientHostNameShort ]]; then
		echo "	ERR:  Client host name isn't present!  Attempting fallback.."

	fi
	echo "  Cleaning up user+Roles.." >> "/var/home/$user/logs/etcdlog.log"
	cmd="user del $clientHostNameShort"; execute_etcd_cmd "$cmd"
	cmd="role del $clientHostNameShort"; execute_etcd_cmd "$cmd"
	local file="/var/home/wavelet-root/config/.$clientHostNameShort.enc"
	shred "$file" && rm -rf "$file"
	echo "  Host ETCD credentials removed from the server!" >> "/var/home/$user/logs/etcdlog.log"
}

deleteHostFromDomain() {
	# Performs a full host deletion from the IPA domain, automatically revoking certificates.
	kinit admin < "/var/secrets/ipaadmpw.secure"
	ipa host-del "$targetHostName" --updatedns --continue
}


#####
#
# Main 
#
#####

set -x
logName=/var/home/wavelet-root/logs/force_deprovision.log
exec >> "${logName}" 2>&1
event_server