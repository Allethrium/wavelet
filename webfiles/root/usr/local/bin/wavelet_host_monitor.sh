#!/bin/bash
# Simple ping-based health check for clients
# Called by systemd service on interval

ETCDINTERACTIONHOOKS=""
if [[ -f "/var/wavelet_ramfs/etcd_interaction_hooks.sh" ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source "/usr/local/bin/etcd_interaction_hooks.sh"
fi

LOGFILE="/var/home/wavelet/logs/health_monitor.log"

# Configuration
PING_COUNT=2
PING_TIMEOUT=2
PING_INTERVAL="$2"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

check_host_health() {
    local ipAddr="$1"
    log_message "Checking health of: $ipAddr"
    # Perform ping
    if ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$ipAddr" > /dev/null 2>&1; then
        log_message "OK: $ipAddr is reachable"
        return 0
    else
        return 1
    fi
}

main(){
	declare -A hostList
	declare -A infraList
	local printvalue
	# Get list of hostkeys
    KEYNAME="/HOSTS/"; read_etcd_prefix_list
    while read -r key; do
       	if [[ -n "$key" ]] && [[ "$key" =~ ^/HOSTS/[^/]+/control/IP$ ]]; then
           	# Read the IP value from the next line
           	read -r ip
           	if [[ -z "$ip" ]]; then
      			continue
      		fi
      		if ! valid_ipv4 "$ip"; then
      			continue
      		fi
           	# Extract hostname from /HOSTS/hostname/control/IP
           	hostname="${key#/HOSTS/}"
           	hostname="${hostname%/control/IP}"
           	# Extract type
            # Check if this IP key already exists
			if [[ -z "${hostList[$ip]+isset}" ]]; then
				# Store IP as key, hostname as value
				hostList["$ip"]="$hostname"
			fi
       	fi
       	if [[ "$key" =~ ^/type$ ]]; then
       		# check the type and save it to a separate array if type == infra
       		KEYNAME="$key"; read_etcd_global
       		if [[ "$printvalue" == "infra" ]]; then
       			infraList["$ip"]="$hostname"
       		fi
       	fi
	done <<<"$printvalue"
	for ip_addr in "${!hostList[@]}"; do
   		(# Get the hostname from the value
   		hostname="${hostList[$ip_addr]}"
    	if check_host_health "$ip_addr"; then
			log_message "Host network test passed: $hostname"
			# Host is up: clear any accumulated ping-failure state so the unsubscribe counter starts fresh
			KEYNAME="/HOSTS/$hostname/control/badPing"; KEYVALUE="0"; write_etcd_global &
		else
			log_message "Host network test failure: $hostname, $ip_addr"
			KEYNAME="/HOSTS/$hostname/control/healthStatus"
			KEYVALUE="UNR: Ping failure!"
			write_etcd_global &
			# Increment the consecutive-failure counter (persisted in etcd so it
			# survives across timer runs). After 3 consecutive failures we issue
			# an unsubscribe request so the orchestrator drops this host from any
			# encoder's reflector, without deprovisioning the host itself.
			KEYNAME="/HOSTS/$hostname/control/badPing"; read_etcd_global
			badPing="${printvalue:-0}"
			badPing=$((badPing + 1))
			KEYNAME="/HOSTS/$hostname/control/badPing"; KEYVALUE="$badPing"; write_etcd_global &
			if (( badPing >= 3 )); then
				log_message "Host unreachable 3x, issuing unsubscribe request: $hostname"
				KEYNAME="/HOSTS/$hostname/control/unsubRequest"; KEYVALUE="host_down"; write_etcd_global &
				# Reset the counter so we only fire once per outage, not every run.
				KEYNAME="/HOSTS/$hostname/control/badPing"; KEYVALUE="0"; write_etcd_global &
			fi
       	fi
       	) &
	done
	for infraEntry in "${!infraList[@]}"; do
		# TODO - check and report SNMP traps from infra devices and update on a status change
		(
			# Get the SNMP data from secure storage
			# interrogate device
			# parse device through appropriate filter to format data
			# update host keys by verifying against prefix list if change
			echo "Placeholder"
		) &
	done
	wait
}


#####
#
# Main
#
#####


# Run main function
main