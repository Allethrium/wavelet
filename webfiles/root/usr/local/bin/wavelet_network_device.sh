#!/bin/bash

# Wavelet network sense script

# This script is called by an inotifywait service monitoring /var/lib/dnsmasq/leases/
# reads out the most recently modified lease file, then processes the IpAddr/MAC combination

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

#
# Device processing blocks - these are basically the 'driver' as far as this module is concerned.
#

event_event_magewell_ndi(){
	# Interrogates Magewell device, attempts preconfigured username and password, then tries to set appropriate settings for streaming into UltraGrid.
}

event_ptz_ndiHX(){
	# Interrogates PTZ Cam device, attempts preconfigured username and password, then tries to set appropriate settings for streaming into UltraGrid.
	echo -e "Attempting to connect to device..\n"
		if ping -c 1 ${pAddr} &> /dev/null
			then
  				echo -e "Successful!\nProceeding to parse device data..\n"
				# stuff to set the stream target to RTP/RTSP 192.168.1.32 on appropriate port
				# Generate JSON config object from the device webserver
				input=$(curl -X GET -H "Content-type: application/json" -H "Accept: application/json" http://${ipAddr}/cgi-bin/param.cgi?get_device_conf | tr -d '"' | jq -Rs 'split("\n")[:-1][]')
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
        		# do something here with array data to reliably parse info out for difference devices (search array islike= serial, then =serial, hostname islike host, then hostname=)
        		#
        		#
        		#
        		#
				echo -e "\nPopulating ETCD with discovery data..\n"
				KEYNAME="/network_interface/short/${deviceHostName}"
				KEYVALUE="${deviceHash}"
				write_etcd_global
				KEYNAME="/network_shorthash/${deviceHash}"
				KEYVALUE="${deviceHostName}"
				write_etcd_global
				KEYNAME="/network_long/${leasefile}"
				KEYVALUE="${devhash}"
				write_etcd_global
				KEYNAME="/network_longhash/${devHash}"
				KEYVALUE="${leasefile}"
				echo -e "Device successfully configured, finishing up..\n"
				exit 0
			else
  				echo -e "error, the device is not responding to ping.  This may mean that the device is improperly configured and did not receive a DHCP IP lease from DNSMasq.\n"
  				exit 1
		fi
}

event_vendorDevice3(){
	# Interrogates Example device, attempts preconfigured username and password, then tries to set appropriate settings for streaming into UltraGrid.
	echo -e "Attempting to connect to device\n"
	echo -e "Successful!\nProceeding to parse REST data to stream into Wavelet..\n"
		# stuff to set the stream target to RTP/RTSP 192.168.1.32 on appropriate port
	echo -e "Generating device hash and creating WebUI interface components..\n"
		# stuff to generate the webUI interface components, stream will only be enabled when device is selected!!
		# NDI cameras may have focus data in addition to other stuff, we may want to eventually add a config box on the webUI to input useful settings and store them!
	echo -e "Device successfully configured, finishing up..\n"
	exit 0
}

generate_device_info() {
	# This is all that's left after moving the hashing functions to each device block.. perhaps we want that stuff here as its portable..
	output_return=$(etcdctl --endpoints=http://192.168.1.32:2379 get "/network_hash/${deviceHash}")
	if [[ $output_return == "" ]] then
		echo -e "\n${deviceHash} not located within etcd's /network_hash/* keyspace, assuming we have a new device and continuing with process to set parameters..\n"
	else
		echo -e "\n${deviceHash} located in etcd:\n\n${output_return}\n\n, terminating process.\nIf you wish for the device to be properly redetected from scratch, please move it to a different USB port.\n"
		# we run device_cleanup regardless!!
		device_cleanup
	fi
}


read_leasefile(){
	# Here we read in the leasefile and generate a devicehash from the IP:MAC combination.
	# Key Legend:
	#	/network_interface/#UIlabel		$deviceHash
	#	/network_shorthash/$deviceHash	$UIlabel
	#	/network_longhash/$devFull		$deviceHash
	#	/network_devicehash/$deviceHash	#devFull
	#
	#	UILabel		= the device label set on the WebUI button.  This might be most appropriately automated to set the device HostName
	#	deviceHash	= the hash generated from the deviceIP and MAC.  This is somewhat dependent on DNSmasq but should be stable as DNSmasq will not hand out different IPaddr to a recognized 'stale' MAC in most cases.
	#	devFull		= a "full" devicename, basically the concatenated IP:MAC combination and also the filename of the generated leasefile
	#	
	#	Like DetectV4L, this gives us three independent values - a label which can change, a device hash which is a UUID, and a full device ID for state tracking
	leasefile=$(ls -t /var/tmp/dnsmasq/leases/ | head -n1)
	deviceHash=$(echo $leasefile | sha256sum)
	ipAddr=${leasefile%_*}
	macAddr=${leasefile#*_}
	echo -e "\nDetected IP Address: ${ipAddr}\n"
	echo -e "\nDetected MAC Address: ${macAddr}\n"
}

#####
#
# Main
#
####

set -x
exec >/var/tmp/network_device.log 2>&1
read_leasefile