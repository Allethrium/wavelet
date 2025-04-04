#!/bin/bash

# Called from one of three systemd watcher units polling for any changes under the UI prefixes
# parses arg from the systemd unit activated, concats with a timestamp
# updates /UI/POLL_UPDATE with the timestamp+type value
# the value will be polled by index.js+poll_etcd_key.php 
# the JS frontend will compare the values, if any change occurs
# updates the area-of-interest defined by the second part of the returned value


# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
write_etcd_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name: ${KEYNAME} set to: ${KEYVALUE} for Global value\n"
}


set_poll_key(){
	# generates a timestamp, concats with with the type
	KEYNAME="/UI/POLL_UPDATE"; KEYVALUE="$(date +%s)|${1}"; write_etcd_global
	echo "/UI/POLL_UPDATE key updated with ${KEYVALUE}, UI should pick up changes on next polling cycle!"
}


###
#
# Main
#
###

#set -x
# Check for pre-existing log file
logName=/var/home/wavelet/logs/poll_watcher.log
exec >> "${logName}" 2>&1

# Parse input options (I.E if called by promote service)
echo -e "Called from SystemD unit, parsing input options: ${@}.."
hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
set_poll_key ${@}