#!/bin/bash

# Wavelet network sense script

# This script is designed to be called with an IP address argument every time DNSmasq hands out an IP address lease on the wavelet network.  
# Because it runs as a restricted user, we can only do some very basic things here.  
# intermediary before userspace scripts step in and read the lease file.

dnsmasq_operation_type=$1
dnsmasq_mac=$2
dnsmasq_ipAddr=$3
dnsmasq_hostName=$4

detect_self(){
	# hostname.local populated by run_ug.sh on system boot
	# necessary because this script is spawned with restricted privileges, it can't call hostname or dnsdomainname
	# This isn't a problem because once set the hostname of the server is static.
	UG_HOSTNAME=hostnamegoeshere
	echo -e "Hostname is ${UG_HOSTNAME} \n"
	case ${UG_HOSTNAME} in
	svr*)			echo -e "I am a Server."; event_server
	;;
	*)				echo -e "This device Hostname is not set approprately for network sense, exiting \n"	;	exit 0
	;;
	esac
}

event_server(){
	# It seems we need to parse to a new script as we can't run ping or curl here?
	parse_input_opts
}

parse_input_opts(){
	# Scan for injection attacks
	# ignore if null
	case ${dnsmasq_operation_type} in
	add)		echo -e "Dnsmasq argument indicates a new lease for a new MAC, proceeding to detection"			;	event_detect_networkDevice
	;;
	old)		echo -e "Dnsmasq has noted a change in the hostname or MAC of an existing lease, redetecting"	;	event_detect_networkDevice
	;;
	del)		echo -e "Dnsmasq has noted that a lease has been deleted, setting device as inactive"			;	event_inactive_networkDevice
	;;
	*)			echo -e "Input doesn't seem to be valid, doing nothing"											;	exit 0
	esac
}

event_detect_networkDevice(){
	# We write out a lease file to /var/tmp/
	# Inotifywait will monitor this directory and process the most recent .lease file.  The actual device setup will be launched as the wavelet user.
	echo -e "Writing lease file for ${dnsmasq_ipAddr} and ${dnsmasq_mac}\n"
	touch /var/tmp/${dnsmasq_ipAddr}_${dnsmasq_mac}.lease
	sleep .5
	# we remove the file .5 seconds later so that the device can be re-detected once dnsmasq hands out a new lease I.E on system reboot
	rm -rf /var/tmp/${dnsmasq_ipAddr}_${dnsmasq_mac}.lease
	# If security layer is enabled, dnsmasq won't handle DNS and we must update FreeIPA's BIND server manually;
}

event_inactive_networkDevice(){
	# If security layer is enabled, dnsmasq won't handle DNS and we must update FreeIPA's BIND server manually;
	echo -e "WIP function that will clean up entries if the lease is expired and the device is no longer on the network..."
	exit 0
}

###
#
# Main
#
###

#set -x
exec >/var/tmp/network_sense.log 2>&1
# check to see if I'm a server or an encoder
echo -e "\n\n********Begin network detection and registration process...********\n\n"
detect_self