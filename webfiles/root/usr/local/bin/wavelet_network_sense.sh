#!/bin/bash

# Wavelet network sense script

# This script is designed to be called with an IP address argument every time DNSmasq hands out an IP address lease on the wavelet network.  
# From there on, it should function in much the same way as detectv4l.sh insofar as it queries the connected device, sets common settings
# and then adds the device as an input for the system in the WebUI, and stores appropriate input strings for the device

dnsmasq_operation_type=$1
dnsmasq_mac=$2
dnsmasq_ipAddr=$3
dnsmasq_hostName=$4


#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
ETCDCTL_API=3
read_etcd(){
		printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get $(hostname)/${KEYNAME} --print-value-only)
		echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for host $(hostname)"
}

read_etcd_global(){
		printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
		echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for Global value"
}

write_etcd(){
		etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
		echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}

write_etcd_global(){
		etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
		echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
}

write_etcd_clientip(){
		etcdctl --endpoints=${ETCDENDPOINT} put decoderip/$(hostname) "${KEYVALUE}"
		echo -e "$(hostname) set to ${KEYVALUE} for Global value"
}
read_etcd_clients_ip() {
		return_etcd_clients_ip=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix decoderip/ --print-value-only)
}


detect_self(){
	# hostname.local populated by run_ug.sh on system boot
	# necessary because this script is spawned with restricted privileges
	UG_HOSTNAME=$(cat /var/lib/dnsmasq/hostname.local)
	echo -e "Hostname is ${UG_HOSTNAME} \n"
	case ${UG_HOSTNAME} in
	svr*)				echo -e "I am a Server."; event_server
	;;
	*)					echo -e "This device Hostname is not set approprately for network sense, exiting \n"; exit 0
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
	add)			echo -e "Dnsmasq argument indicates a new lease for a new MAC, proceeding to detection"			;	event_detect_networkDevice
	;;
	old)			echo -e "Dnsmasq has noted a change in the hostname or MAC of an existing lease, redetecting"	;	event_detect_networkDevice
	;;
	del))			echo -e "Dnsmasq has noted that a lease has been deleted, setting device as inactive"			;	event_inactive_networkDevice
	;;
	*)				echo -e "Input doesn't seem to be valid, doing nothing"											;	exit 0
	esac
}

event_detect_networkDevice(){
	# Detects network device and tries to configure it, then add it to wavelet as a video source
	# Worked out primarily from sources such as https://maclookup.app
	# To support a new network device, I'll need the manufacturer assigned MAC Space and then add it here along with adding the appropriate module.
	# Some vendors have multiple MAC spaces, so some of these will parse to the same config process
	echo -e "Detect network device function called with the following data:\nOperation: ${dnsmasq_operation_type},\nMAC: ${dnsmasq_mac},\nIP Address: ${dnsmasq_ipAddr},\nHostname: ${dnsmasq_hostName}\n"
	# Convert input to all uppercase with ^^
	case ${dnsmasq_mac^^} in
	D0:C8:57:8*)					echo -e "Nanjing (Magewell) device matched, proceeding to attempt configuration"						;	event_magewell_ndi
	;;
	70:B3:D5:75:D*)					echo -e "Nanjing (Magewell) device matched, proceeding to attempt configuration"						;	event_magewell_ndi
	;;
	D4:E0:8E*)						echo -e "ValueHD Corporation (PTZ Optics) matched, proceeding to attempt configuration"					;	event_ptz_ndiHX
	;;
	# This one might need different config as the camera is of a different design
	DC:ED:84*)						echo -e "PTZ Optics NDI Cam (HAverford Systems Inc.) matched, proceeding to attempt configuration"		;	event_ptz_ngiHX
	;;
	whateverAnothersupportDevIs)	echo -e "Device matched, proceeding to attempt configuration"											;	event_vendorDevice4
	;;
	*)								echo -e "Device not supported at current time, doing nothing."											;	exit 0
	esac
}

event_inactive_networkDevice(){
	# use this to remove interface buttons for the device in question *but store configuration data to match the MAC* - use same hash function as used in detectv4l
	echo -e "Archiving configuration data for device ${dnsmasq_mac}, and removing from webUI\n"
	echo -e "\n* Copied config data to backup key under device MAC/Hashed UUID\n"
	echo -e "\n* Copied UI to backup key under device MAC/Hashed UUID/UI\n"
	echo -e "\n* Deleting from webUI..\n"
	exit 0
}

# Device processing blocks - these are basically the 'driver' as far as this module is concerned.

event_event_magewell_ndi(){
	# Interrogates Magewell device, attempts preconfigured username and password, then tries to set appropriate settings for streaming into UltraGrid.
	echo -e "Attempting to connect to device..\n"
		if ping -c 1 ${dnsmasq_ipAddr} &> /dev/null
			then
  				echo -e "Successful!\nProceeding to parse REST data to stream into Wavelet..\n"
				# stuff to set the stream target to RTP/RTSP 192.168.1.32 on appropriate port
				# Generate JSON config object from the device webserver
				input=$(curl -X GET -H "Content-type: application/json" -H "Accept: application/json" http://192.168.1.16/cgi-bin/param.cgi?get_device_conf | tr -d '"' | jq -Rs 'split("\n")[:-1][]')
				cleaned=$(echo "$input" | tr -d ' ' |sed -e 's/=/:/' -e 's/\"//g')
				declare -A output_array
				index=0
				while read -r line; do
        			keyname=$(printf "%s" "$line" | cut -d':' -f1)
			        value=$(printf "%s" "$line" | cut -d':' -f2)
			        output_array[${keyname}]=${value}
        			((index++))
				done <<< "$cleaned"
				device_json=$(
		        printf '{\n'
        		for key in "${!output_array[@]}"; do
                	printf '"%s": "%s",\n' "$key" "${output_array[$key]}"
        		done
        		printf "}\n")

        		# 
				echo -e "Generating device hash and creating WebUI interface components..\n"
					# could just be lazy and generate a device hash from the array we already created?
					deviceHash=$(echo "${output_array[@]}" | sha256sum)
					# Write JSON object to etcd for this device
        			KEYNAME=/network_sense_device/${deviceHash}/JSONConf
        			KEYVALUE=${device_json}
        			write_etcd_global
					# etcdctl parse this hash into a NEW /networkInputs subfolder, which the javascript ui will populate with an EXTRA php script.
					generate_network_device_info
					set_network_device_input
					# everything else will work the same as detectv4l etc.
					# SET the device up as most appropriate for wavelet data ingest - this might take some labbing to find optimal settings.
				echo -e "Device successfully configured, finishing up..\n"
				exit 0
			else
  				echo -e "error, the device is not responding to ping.  This may mean that the device is improperly configured and did not receive a DHCP IP lease from DNSMasq.\n"
  				exit 1
		fi
}

event_ptz_ndiHX(){
	# Interrogates PTZ Cam device, attempts preconfigured username and password, then tries to set appropriate settings for streaming into UltraGrid.
	echo -e "Attempting to connect to device..\n"
		if ping -c 1 ${dnsmasq_ipAddr} &> /dev/null
			then
  				echo -e "Successful!\nProceeding to parse REST data to stream into Wavelet..\n"
				# stuff to set the stream target to RTP/RTSP 192.168.1.32 on appropriate port
				echo -e "Generating device hash and creating WebUI interface components..\n"
				# stuff to generate the webUI interface components, stream will only be enabled when device is selected!!
				echo -e "Device successfully configured, finishing up..\n"
			else
  				echo -e "error, the device is not responding to ping.  This may mean that the device is improperly configured and did not receive a DHCP IP lease from DNSMasq.\n"
  				exit 0
		fi
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



set_network_device_input() {
	# Taken from detectv4l.sh - TO BE modded for use
	# called from generate_device_info from the nested if loop checking for pre-existing deviceHash in etcd /hash/
	# populated device_string_short with hash value, this is used by the interface webUI component
	# device_string_short is effectively the webui Label / banner text.
	# Because we cannot query etcd by keyvalue, we must create a reverse lookup prefix for everything we want to be able to clean up!!
	KEYNAME="/network_interface/$(hostname)/${device_string_short}"
	KEYVALUE="${deviceHash}"
	write_etcd_global	
	# And the reverse lookup prefix - N.B this is updated from set_label.php when the webUI changes a device label/banner string! 
	KEYNAME="/network_short_hash/${deviceHash}"
	KEYVALUE=$(hostname)/${device_string_short}
	write_etcd_global
	# We need this to perform cleanup "gracefully"
	KEYNAME="/network_long_interface${device_string_long}"
	KEYVALUE=${deviceHash}
	write_etcd_global
	# This will enable us to find the device from its hash value, along with the registered host encoder, like a reverse DNS lookup..
	# GLOBAL value\
	echo -e "Attempting to set keyname ${deviceHash} for $(hostname)${device_string_long}"
	KEYNAME="/network_hash/${deviceHash}"
	# Stores the device data under hostname/inputs/device_string_long
	KEYVALUE="/network_sense_inputs${device_string_long}"
	write_etcd_global
	# notify watcher that input device configuration has changed
	KEYNAME=new_device_attached
	KEYVALUE=1
	write_etcd_global
	echo -e "resetting variables to null."
	deviceHash=""
	device_string_short=""
	KEYNAME=INPUT_DEVICE_PRESENT
	KEYVALUE=1
	write_etcd
	detect
}

generate_device_info() {
	# This is all that's left after moving the hashing functions to each device block.. perhaps we want that stuff here as its portable..
	output_return=$(etcdctl --endpoints=http://192.168.1.32:2379 get "/hash/${deviceHash}")
	if [[ $output_return == "" ]] then
		echo -e "\n${deviceHash} not located within etcd, assuming we have a new device and continuing with process to set parameters..\n"
	else
		echo -e "\n${deviceHash} located in etcd:\n\n${output_return}\n\n, terminating process.\nIf you wish for the device to be properly redetected from scratch, please move it to a different USB port.\n"
		# we run device_cleanup regardless!!
		device_cleanup
	fi
}



####
#
# Main
#
####

# Create log - note DNSmasq doesn't run as wavelet and can't log to wavelet homedir!
set -x
exec >/var/tmp/network_sense.log 2>&1
# check to see if I'm a server or an encoder

echo -e "\n \n \n ********Begin network detection and registration process...******** \n \n \n"
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

