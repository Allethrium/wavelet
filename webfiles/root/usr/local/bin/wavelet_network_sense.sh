#!/bin/bash

# Wavelet network sense script

# This script is designed to be called with an IP address argument every time DNSmasq hands out an IP address lease on the wavelet network.  
# From there on, it should function in much the same way as detectv4l.sh insofar as it queries the connected device, sets common settings
# and then adds the device as an input for the system in the WebUI, and stores appropriate input strings for the device

dnsmasq_operation_type=$1
dnsmasq_mac=$2
dnsmasq_ipAddr=$3
dnsmasq_hostName=$4

detect_self(){
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	svr*)				echo -e "I am a Server."; event_server
	;;
	*)				echo -e "This device Hostname is not set approprately for network sense, exiting \n"; exit 0
	;;
	esac
}

event_server(){
	parse_input_opts
}

parse_input_opts(){
	# Scan for injection attacks
	# ignore if null
	case ${dnsmasq_operation_type} in
	add)			echo -e "Dnsmasq argument indicates a new lease for a new MAC, proceeding to detection"		;	event_detect_networkDevice
	;;
	old)			echo -e "Dnsmasq has noted a change in the hostname or MAC of an existing lease, redetecting"	;	event_detect_networkDevice
	;;
	del))			echo -e "Dnsmasq has noted that a lease has been deleted, setting device as inactive"		;	event_inactive_networkDevice
	;;
	*)			echo -e "Input doesn't seem to be valid, doing nothing"						;	exit 0
}

event_detect_networkDevice(){
	# Detects network device and tries to configure it, then add it to wavelet as a video source
	echo -e "Detect network device function called with the following data:\nOperation: ${dnsmasq_operation_type},\nMAC: ${dnsmasq_mac},\n IP Address: ${dnsmasq_ipAddr},\n Hostname: ${dnsmasq_hostName}\n"
	
	case ${dnsmasq_mac} in
	whateverMagewellis)		echo -e "Magewell device matched, proceeding to attempt configuration"	;	event_vendorDevice1
	;;
	whateverPTZis)			echo -e "PTZ matched, proceeding to attempt configuration"		;	event_vendorDevice2
	;;
	whateverNDIis)			echo -e "NDI matched, proceeding to attempt configuration"		;	event_vendorDevice3
	;;
	whateverAnothersupportDevIs)	echo -e "Device matched, proceeding to attempt configuration"		;	event_vendorDevice4
	;;
	*)				echo -e "Device not supported at current time, doing nothing."		;	exit 0
}

event_inactive_networkDevice(){
	# use this to remove interface buttons for the device in question *but store configuration data to match the MAC* - use same hash function as used in detectv4l
	echo -e "Archiving configuration data for device ${dnsmasq_mac}, and removing from webUI\n"
	exit 0
}

# Device processing blocks - these are basically the 'driver' as far as this module is concerned.

event_vendorDevice1(){
	# Interrogates Magewell device, attempts preconfigured username and password, then tries to set appropriate settings for streaming into UltraGrid.
	echo -e "Attempting to connect to device\n"
	echo -e "Successful!\nProceeding to parse REST data to stream into Wavelet..\n"
		# stuff to set the stream target to RTP/RTSP 192.168.1.32 on appropriate port
	echo -e "Generating device hash and creating WebUI interface components..\n"
		# stuff to generate the webUI interface components, stream will only be enabled when device is selected!!
	echo -e "Device successfully configured, finishing up..\n"
	exit 0
}

event_vendorDevice2(){
	# Interrogates PTZ Cam device, attempts preconfigured username and password, then tries to set appropriate settings for streaming into UltraGrid.
	echo -e "Attempting to connect to device\n"
	echo -e "Successful!\nProceeding to parse REST data to stream into Wavelet..\n"
		# stuff to set the stream target to RTP/RTSP 192.168.1.32 on appropriate port
	echo -e "Generating device hash and creating WebUI interface components..\n"
		# stuff to generate the webUI interface components, stream will only be enabled when device is selected!!
		# PTZ optics cameras may have focus data in addition to other stuff, we may want to eventually add a config box on the webUI to input useful settings and store them!
	echo -e "Device successfully configured, finishing up..\n"
	exit 0
}

event_vendorDevice3(){
	# Interrogates NDI Cam device, attempts preconfigured username and password, then tries to set appropriate settings for streaming into UltraGrid.
	echo -e "Attempting to connect to device\n"
	echo -e "Successful!\nProceeding to parse REST data to stream into Wavelet..\n"
		# stuff to set the stream target to RTP/RTSP 192.168.1.32 on appropriate port
	echo -e "Generating device hash and creating WebUI interface components..\n"
		# stuff to generate the webUI interface components, stream will only be enabled when device is selected!!
		# NDI cameras may have focus data in addition to other stuff, we may want to eventually add a config box on the webUI to input useful settings and store them!
	echo -e "Device successfully configured, finishing up..\n"
	exit 0
}

event_vendorDevice4(){
	# Interrogates ? device, attempts preconfigured username and password, then tries to set appropriate settings for streaming into UltraGrid.
	echo -e "Attempting to connect to device\n"
	echo -e "Successful!\nProceeding to parse REST data to stream into Wavelet..\n"
		# stuff to set the stream target to RTP/RTSP 192.168.1.32 on appropriate port
	echo -e "Generating device hash and creating WebUI interface components..\n"
		# stuff to generate the webUI interface components, stream will only be enabled when device is selected!!
		# NDI cameras may have focus data in addition to other stuff, we may want to eventually add a config box on the webUI to input useful settings and store them!
	echo -e "Device successfully configured, finishing up..\n"
	exit 0
}
####
#
# Main
#
####

detect_self


###########

# Whenever a new DHCP lease is created, or an old one destroyed, or a TFTP file transfer completes, the executable specified by this option is run. <path> must be an absolute pathname, no PATH search occurs. The arguments to the process are "add", "old" or "del", the MAC address of the host (or DUID for IPv6) , the IP address, and the hostname, if known. "add" means a lease has been created, "del" means it has been destroyed, "old" is a notification of an existing lease when dnsmasq starts or a change to MAC address or hostname of an existing lease (also, lease length or expiry and client-id, if --leasefile-ro is set and lease expiry if --script-on-renewal is set). If the MAC address is from a network type other than ethernet, it will have the network type prepended, eg "06-01:23:45:67:89:ab" for token ring. The process is run as root (assuming that dnsmasq was originally run as root) even if dnsmasq is configured to change UID to an unprivileged user.
# ...
# 
# The script is not invoked concurrently: at most one instance of the script is ever running (dnsmasq waits for an instance of script to exit before running the next). Changes to the lease database are which require the script to be invoked are queued awaiting exit of a running instance. If this queueing allows multiple state changes occur to a single lease before the script can be run then earlier states are discarded and the current state of that lease is reflected when the script finally runs.

# At dnsmasq startup, the script will be invoked for all existing leases as they are read from the lease file. Expired leases will be called with "del" and others with "old". When dnsmasq receives a HUP signal, the script will be invoked for existing leases with an "old" event.

####
# There are five further actions which may appear as the first argument to the script, "init", "arp-add", "arp-del", "relay-snoop" and "tftp". More may be added in the future, so scripts should be written to ignore unknown actions. "init" is described below in --leasefile-ro
####
###########

