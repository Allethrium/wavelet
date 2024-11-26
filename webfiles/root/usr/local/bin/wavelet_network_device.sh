#!/bin/bash

# Wavelet network sense script

# This script is called by an inotifywait service monitoring /var/tmp
# reads out the most recently modified lease file, then processes the IpAddr/MAC combination

# We need to change how this works.  Currently if a lease is created in /var/tmp that file is unmodifiable by wavelet since it's not root
# This means that we need to modify the monitor service to call this script in some other manner, because the even-driven approach won't work
# 1) on boot since we have multiple lease files
# 2) if we need to add a previously existing and leased device
# So this only currently works for NEW devices, and we can't even delete the old lease files.  

# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
read_etcd(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd" ${KEYNAME})
	echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)\n"
}
read_etcd_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}") 
	echo -e "Key Name {$KEYNAME} read from etcd for Global Value $printvalue\n"
}
read_etcd_prefix(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_prefix" "${KEYNAME}")
	echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)\n"
}
read_etcd_clients_ip() {
	return_etcd_clients_ip=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_clients_ip")
}
read_etcd_clients_ip_sed() {
	# We need this to manage the \n that is returned from etcd.
	# the above is useful for generating the reference text file but this parses through sed to string everything into a string with no newlines.
	processed_clients_ip=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_clients_ip" | sed ':a;N;$!ba;s/\n/ /g')
}
write_etcd(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name ${KEYNAME} set to ${KEYVALUE} under /$(hostname)/\n"
}
write_etcd_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name ${KEYNAME} set to ${KEYVALUE} for Global value\n"
}
write_etcd_client_ip(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_client_ip" "${KEYNAME}" "${KEYVALUE}"
}
delete_etcd_key(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key" "${KEYNAME}"
}

parse_macaddr() {
	echo -e "argument 1: ${1}\n"
	echo -e "argument 2: ${2}\n"
	echo -e "Detect network device function called with the following data:\nMAC: ${2},\nIP Address: ${1}\n"
	# We put ^^ after the var to convert to uppercase!
	case ${2^^} in
		# Convert input to all uppercase with ^^i
		D0:C8:57:8*)                    echo -e "Nanjing (Magewell) device matched, proceeding to attempt configuration"                                ;       event_magewell_ndi
		;;
		70:B3:D5:75:D*)                 echo -e "Nanjing (Magewell) device matched, proceeding to attempt configuration"                                ;       event_magewell_ndi
		;;
		D4:E0:8E*)                      echo -e "ValueHD Corporation (PTZ Optics) matched, proceeding to attempt configuration"                         ;       event_ptz_ndiHX
		;;
		whateverNDIis)                  echo -e "NDI matched, proceeding to attempt configuration"                                                      ;       event_vendorDevice3
		;;
		# This one might need different config as the camera is of a different design
		DC:ED:84*)                      echo -e "PTZ Optics NDI Cam (Haverford Systems Inc.) matched, proceeding to attempt configuration"              ;       event_ptz_ngiHX
		;;
		whateverAnothersupportDevIs)    echo -e "Device matched, proceeding to attempt configuration"                                                   ;       event_vendorDevice3
		;;
		*)                              echo -e "Device not supported at current time, doing nothing."                                                  ;       exit 0
		;;
		esac
}


#
# Device processing blocks - these are the 'driver' as far as this module is concerned.
#

event_magewell_ndi(){
	# Interrogates Magewell device, attempts preconfigured username and password, then tries to set appropriate settings for streaming into UltraGrid.
	echo -e "Waiting for two seconds, then attempting to connect to device..\n"
	sleep 2
	echo -e "\nCalling curl with GET request for Default Username and Password..\n"
	defaultPassword="Admin"
	md5sumAdminPassword=$(echo -n "${defaultPassword}" | md5sum | cut -d' ' -f1)
	curl --cookie-jar /var/tmp/sid.txt "http://${ipAddr}/mwapi?method=login&id=Admin&pass=${md5sumAdminPassword}"
	if [ $? -ne 0 ]; then
	echo "\nConnection to MageWell device failed!  Reset the device to FACTORY DEFAULTS and try again!\n"
	exit 1
	fi
	# Perhaps we should autogen an admin password and store it in etcd here for security purposes?
	
	# This network device username and password should be generated by the wavelet installer script
	# at the same time as the wavelet_root and wavelet user passwords, mod ignition and installer scripts
	# Mental watts are low, so I couldn't think of another elegant way to set it up beyond generating rando and storing it in etcd..
	waveletUserPass=$(echo /home/wavelet/networkdevice_userpass)
	echo -e "\nAttempting to add Wavelet user..\n"
	md5sumWaveletPassword=$(echo -n "${waveletUserPass}" | md5sum | cut -d' ' -f1)
	curl --cookie /var/tmp/sid.txt "http://${ipAddr}/mwapi?method=add-user&id=Wavelet&pass=${md5sumWaveletPassword}"
	# Now we login with the Wavelet User to save the cookie
	curl --cookie-jar /var/tmp/wavelet_sid.txt "http://${ipAddr}/mwapi?method=login&id=Admin&pass=${md5sumAdminPassword}"
	# LibNDI should be installed on wavelet by default (DEPENDENCY)
	ndiSource=$(/usr/local/bin/UltraGrid.AppImage --tool uv -t ndi:help | grep ${ipAddr} | cut -d '(' -f1 | awk '{print $1}')
	ndiIPAddr=$(/usr/local/bin/UltraGrid.AppImage --tool uv -t ndi:help | grep ${ipAddr} | awk '{print $5}')
	# We need to set the magewell card to raw framerate 30fps, AV1 compression had pauses at 60FPS!
	declare -a magewellCommands=('mwapi?method=set-video-config&out-fr-convertion=frame-rate-half',	'mwapi?method=set-video-config&out-raw-resolution=false&out-cx=1920&out-cy=1080', 'mwapi?method=set-video-config&in-auto-quant-range=false&in-quant-range=full', 'mwapi?method=set-video-config&in-auto-color-fmt=false&in-color-fmt=rgb', 'mwapi?method=set-video-config&bit-rate-ratio=150', 'mwapi?method=out-quant-range=full', 'http://ip/mwapi?method=set-ndi-config&enable=true')
	for i in "${magewellCommands[@]}"
	do
		curl --cookie /var/tmp/wavelet_sid.txt http://"${ipAddr}"/"$i"
	done
	echo -e "\nMageWell ProConvert device should now be fully configured..\n"
	# Generate UG Stream command from the appropriate NDI Source
	deviceHostName="Magewell Proconvert HDMI $(curl --cookie /var/tmp/wavelet_sid.txt 'http://192.168.1.27/mwapi?method=get-summary-info' | jq '.ndi.name' | tr -d '"')"
	UGdeviceStreamCommand="ndi:url=${ndiIPAddr}"
	populate_to_etcd
	# Call a new module to populate the DHCP lease into FreeIPA BIND (does nothing if security layer is off)
	/usr/local/bin/wavelet_ddns_update.sh ${deviceHostName} ${ipAddr}
}

event_ptz_ndiHX(){
		# Interrogates PTZ Cam device, attempts preconfigured username and password, then tries to set appropriate settings for streaming into UltraGrid.
		echo -e "Waiting for five seconds, then attempting to connect to device..\n"
		sleep 5
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
		deviceHostName=$(echo ${output_array[devname]})
		# Check to see if this device is NDI enabled
		ndiSource=$(/usr/local/bin/UltraGrid.AppImage --tool uv -t ndi:help | grep ${ipAddr} | cut -d '(' -f1 | awk '{print $1}')
		if [ -n ${ndiSource} ]; then
			echo -e "\nNDI source for this IP address not found, configuring for RTSP..\n"
			UGdeviceStreamCommand="rtsp://${ipAddr}:554/1:decompress"
			populate_to_etcd
			echo -e "Device successfully configured, finishing up..\n"
			# Call a new module to populate the DHCP lease into FreeIPA BIND (does nothing if security layer is off)
			/usr/local/bin/wavelet_ddns_update.sh ${deviceHostName} ${ipAddr}
			exit 0
		else
			echo -e "\nNDI is available for this device, defaulting to NDI..\n"
			UGdeviceStreamCommand="ndi:url=${ndiIPAddr}"
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
	# Call a new module to populate the DHCP lease into FreeIPA BIND (does nothing if security layer is off)
	/usr/local/bin/wavelet_ddns_update.sh ${deviceHostName} ${ipAddr}
	exit 0
}

generate_device_info() {
	# This is all that's left after moving the hashing functions to each device block.. perhaps we want that stuff here as its portable..
	KEYNAME="/network_hash/${deviceHash}"; output_return=$(read_etcd_global)
	if [[ $output_return == "" ]] then
		echo -e "\n${deviceHash} not located within etcd's /network_hash/* keyspace, assuming we have a new device and continuing with process to set parameters..\n"
	else
		echo -e "\n${deviceHash} located in etcd:\n\n${output_return}\n\n, terminating process.\nIf you wish for the device to be properly redetected from scratch, please move it to a different USB port.\n"
		# we run device_cleanup regardless!!
		device_cleanup
	fi
}

read_commandfile(){
	# WIP
	# Commandfile generated from dnsmasq to update NS records.
	# cat $(basename $(ls -t /var/tmp/*.command | head -n1)) | `xargs`
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
	leasefile=$(basename $(ls -t /var/tmp/*.lease | head -n1))
	deviceHash=$(echo $leasefile | sha256sum | tr -d "[:space:]-")
	ipAddr=${leasefile%_*}
	interimMacAddr=${leasefile#*_}
	macAddr=$(echo ${interimMacAddr} | cut -d . -f 1)
	echo -e "\nDetected IP Address: ${ipAddr}\n"
	echo -e "\nDetected MAC Address: ${macAddr^^}\n"
	parse_macaddr "${ipAddr}" "${macAddr}"
}

populate_to_etcd(){
	# Now we populate the appropriate keys for webUI labeling and tracking:
	echo -e "\nPopulating ETCD with discovery data..\n"
	KEYNAME="/network_interface/short/${deviceHostName}"; KEYVALUE="${deviceHash}"; write_etcd_global
	KEYNAME="/network_shorthash/${deviceHash}"; KEYVALUE="${deviceHostName}"; write_etcd_global
	#KEYNAME="/network_long/${leasefile}"
	#KEYVALUE="${devicehash}"
	#write_etcd_global
	KEYNAME="/network_longhash/${deviceHash}"; KEYVALUE="${leasefile}"; write_etcd_global
	KEYNAME="/network_ip/${deviceHash}"; KEYVALUE="${ipAddr}"; write_etcd_global
	KEYNAME="/network_uv_stream_command/${ipAddr}"; KEYVALUE="${UGdeviceStreamCommand}"; write_etcd_global
	echo -e "Device successfully configured, finishing up..\n"
	# since we now have a network device active on the system, we need to setup an IP ping watcher to autoremove it or note it as bad
		# Read current IP subscription list
		# find this device in the IP Subscription list
		# if is not already there, append it
		# restart ping watcher service, which will set a "PROBLEM" flag if the device has network issues.  We can use this later on for the webui
		# etcd  /network_health/${ipAddr} --  GOOD or BAD
		# Finally, set and configure a watcher service for this device so that it will reconfigure the device hostname if the label is changed on the webUI
		# /usr/local/bin/wavelet_network_device_relabel.sh
	exit 0
}



#####
#
# Main
#
####

#set -x
exec >/var/tmp/network_device.log 2>&1
read_commandfile
read_leasefile