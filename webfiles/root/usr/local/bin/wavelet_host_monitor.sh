#!/bin/bash

# Simple ping-based health check for clients
# Called by systemd service on interval

ETCDINTERACTIONHOOKS=""
if [[ -f /var/wavelet_ramfs/etcd_interaction_hooks.sh ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source /usr/local/bin/etcd_interaction_hooks.sh
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
	local printvalue
	# Get list of hostkeys
    KEYNAME="/HOSTS/"; read_etcd_prefix_list
    while read -r key; do
       	if [[ -n "$key" ]] && [[ "$key" =~ ^/HOSTS/[^/]+/IP$ ]]; then
           	# Read the IP value from the next line
           	read -r ip
           	if [[ -z "$ip" ]]; then
      			continue
      		fi
      		if ! valid_ipv4 "$ip"; then
      			continue
      		fi
           	# Extract hostname from /HOSTS/hostname/IP
           	hostname="${key#/HOSTS/}"
           	hostname="${hostname%/IP}"
            # Check if this IP key already exists
			if [[ -z "${hostList[$ip]+isset}" ]]; then
				# Store IP as key, hostname as value
				hostList["$ip"]="$hostname"
			fi
       	fi
	done <<<"$printvalue"
	for ip_addr in "${!hostList[@]}"; do
   		(# Get the hostname from the value
   		hostname="${hostList[$ip_addr]}"
    	if check_host_health "$ip_addr"; then
			log_message "Host network test passed: $hostname"
		else
			log_message "Host network test failure: $hostname, $ip_addr"
			KEYNAME="/HOSTS/$hostname/control/healthStatus"
			KEYVALUE="UNR: Ping failure!"
			write_etcd_global &
       	fi
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