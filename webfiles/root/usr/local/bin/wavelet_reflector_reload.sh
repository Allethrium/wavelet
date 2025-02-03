#!/bin/bash
# This script is launched from systemd and acts as a detection sense for alive/dead hosts.  Originally part of the reflector logic in the controller,
# Currently as of 8/1/23 it's called by a systemd etcdctl watch unit every time the IP list changes.


reflector_monitor() {
# Runs in the background pinging clients and updating the reflector list if they are not alive
# This is designed to kill streams to dead clients in order to save system bandwidth
# Combined with the self-registration/connection logic on the subordinate devices, it forms a limited self-healing capability within the system
	reflector_generate_lists() {
	# CURL's reflector list every second and updates client list if inconsistent with existing IPs
		FILE=/home/wavelet/reflector_clients_ip.txt
		if test -f "$FILE"; then
			echo "$FILE Exists, reflector is running and proceeding to test against monitor_list.txt..."
	       	diff=$(diff /home/wavelet/monitor_list.txt /home/wavelet/reflector_clients_ip.txt)
        	read_etcd_clients_ip
        	echo ${return_etcd_clients_ip} > /home/wavelet/monitor_list.txt &>/dev/null
        	reflector_testisalive
        else
        	echo "$FILE does not exist.  Reflector is not running, or something went wrong.  Doing nothing..."
        	:
        fi
	}

	reflector_testisalive() {
	# This runs every n seconds as define by "while sleep $;"" above.  It doesn't need to happen too fast because this is just for housekeeping to avoid the reflector generating too many unicast streams.
	# First, tests whether the etcd flag is already set, if so does nothing because the reflector will be reloaded the next time the system state changes.
	# It tests the etcd master list with the monitor list, if there's a discrepancy it will set an etcd flag for the wavelet_kill_all routine to restart the reflector to reflect the client IP pool changes
	# Otherwise, this component sends a single ping with a 2 second TTL, returns an alive or dead value.
		KEYNAME="reload_reflector"; read_etcd_global
		if [[ "$printvalue" -eq 1 ]]; then
			:
		else
	    	if [[ "$diff" != '' ]] ; then
        		echo -e "IP Address(es) have changed, setting reflector reload flag.  Stream may be momentarily interrupted."
        		KEYNAME="reload_reflector"; KEYVALUE="1"; write_etcd_global
            else 
            	reflector_pingme
            fi
        fi
	}

	reflector_pingme() {
	# Pings the current list of IP addresses associated with Decoders, Livestreams or other clients.
	# If a ping comes back unreachable, it deletes the host registration key from ETCD and the next generate_lists pass will register it as dead,
    # then set the Reflector reload flag.
	exec 3</home/wavelet/monitor_list.txt
	while read -u3 line
	do
	    if [ "$line" == "" ]; then
        	# skip empty lines
        	continue
    	fi
    	ping -W 2 -c1 $(echo "$line"| awk '{print $1}') > /dev/null
    	if [ $? = 0 ]; then
	        echo "$line=ALIVE"
	    else
        	echo "$line=DEAD"
        	# Get hostname from $line value by querying against DNS
        	deadhostkeyname=$(dig +short -x $line | cut -d"." -f1)
        	KEYNAME="/DECODERIP/$deadkeyhostname"; delete_etcd_key
        	echo -e "${deadhostkeyname} has been deleted from /DECODERIP/ list in etcd \n"
        	sleep 2
        	systemctl --user restart wavelet_reflector.service
        	echo -e "Wavelet reflector service restarted via systemd"
    	fi
	done
	}
reflector_generate_lists
}

service_exists() {
    local n=$1
    if [[ $(systemctl list-units --user -t service --full --no-legend "$n.service" | sed 's/^\s*//g' | cut -f1 -d' ') == $n.service ]]; then
        return 0
    else
        return 1
    fi
}

# Main - test for reload flag before we do anything else!
#set -x

hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)

exec >/var/home/wavelet/logs/wavelet_reflector_reload.log 2>&1

if service_exists wavelet_reflector; then
    KEYNAME="reload_reflector"; read_etcd_global
    if [[ "$printvalue" -eq 1 ]]; then
    	echo -e "Reflector reload key is already set!  Restarting reflector service"
    	systemctl --user restart wavelet_reflector.service
    else
    reflector_monitor
    fi
else
echo -e "Reflector isn't currently active, starting the reflector service"
systemctl --user start wavelet_reflector.service
fi