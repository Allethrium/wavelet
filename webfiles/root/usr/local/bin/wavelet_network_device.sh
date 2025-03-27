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
	echo -e "Key Name: {$KEYNAME} read from etcd for value: $printvalue for host: ${hostNameSys}\n"
}
read_etcd_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}") 
	echo -e "Key Name: {$KEYNAME} read from etcd for Global Value: $printvalue\n"
}
read_etcd_prefix(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_prefix" "${KEYNAME}")
	echo -e "Key Name: {$KEYNAME} read from etcd for value $printvalue for host: ${hostNameSys}\n"
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
	echo -e "Key Name: ${KEYNAME} set to ${KEYVALUE} under /${hostNameSys}/\n"
}
write_etcd_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name: ${KEYNAME} set to: ${KEYVALUE} for Global value\n"
}
write_etcd_client_ip(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_client_ip" "${KEYNAME}" "${KEYVALUE}"
}
delete_etcd_key(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key" "${KEYNAME}"
}
delete_etcd_key_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key_global" "${KEYNAME}"
}
delete_etcd_key_prefix(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key_prefix" "${KEYNAME}"
}
generate_service(){
	# Can be called with more args with "generate_servier" ${keyToWatch} 0 0 "${serviceName}"
	/usr/local/bin/wavelet_etcd_interaction.sh "generate_service" "${serviceName}"
}

parse_macaddr() {
	echo -e "argument 1: ${1}\n"
	echo -e "argument 2: ${2}\n"
	echo -e "Detect network device function called with the following data:\nMAC: ${2}\nIP Address: ${1}\n"
	ipAddr="${1}"
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
		*)                              echo -e "Device not supported at current time, attempting to configure anyway.."                                ;       event_unsupportedDevice
		;;
		esac
}


#
# Device processing blocks - these are the 'driver' as far as this module is concerned.
#

event_magewell_ndi(){
	# Interrogates Magewell device, attempts preconfigured username and password, then tries to set appropriate settings for streaming into UltraGrid.
	# We assume the preconfigured username/pass combo of admin/Admin here.  If this is different, you should set it here ( might need a credentials file for this )
	defaultAdminUsername="Admin"
	defaultAdminPassword="Admin"
	echo -e "Waiting for two seconds, then attempting to connect to device on ${ipAddr}.."
	sleep 2
	echo -e "Calling curl with GET request for Default Username and Password.."
	md5sumAdminPassword=$(echo -n "${defaultAdminPassword}" | md5sum | cut -d' ' -f1)
	result=$(curl --cookie-jar /var/tmp/sid.txt "http://${ipAddr}/mwapi?method=login&id=${defaultAdminUsername}&pass=${md5sumAdminPassword}" | jq .[] | head -n 1)
	if [[ ${result} -ne 0 ]]; then
		echo -e "\nConnection to MageWell device failed!  Reset the device to FACTORY DEFAULTS and try again!\n"
		exit 1
	else
		echo "Connection with default credentials succeeded! proceeding.."
	fi
 	create_magewell_wavelet_user() {
 		# sub-function to delete/recreate wavelet user
 		# Delete wavelet user if already exists
 		curl -b /var/tmp/sid.txt "http://${ipAddr}/mwapi?method=del-user&id=wavelet"
		waveletUserPass=$(cat /home/wavelet/config/networkdevice_userpass)
		echo "Attempting to add Wavelet user.."
		md5sumWaveletPassword=$(echo -n "${waveletUserPass}" | md5sum | cut -d' ' -f1)
		curl -b /var/tmp/sid.txt "http://${ipAddr}/mwapi?method=add-user&id=wavelet&pass=${md5sumWaveletPassword}"
		# Now we login with the Wavelet User to save the cookie
		curl --cookie-jar /var/tmp/wavelet_sid.txt "http://${ipAddr}/mwapi?method=login&id=wavelet&pass=${md5sumWaveletPassword}"
		# Further security settings for these devices are really the responsibility of the installation engineer
		echo -e "\nRecommend changing the device default Admin password for security reasons.\n"
	}
	# Perhaps we should autogen an admin password and store it in etcd here for security purposes?
	# This network device username and password should be generated by the wavelet installer script
	# at the same time as the wavelet_root and wavelet user passwords, mod ignition and installer scripts
	# Check for existing user
	result=$(curl -b /var/tmp/sid.txt "http://${ipAddr}/mwapi?method=get-users")
	if 	[[ $result = *"wavelet"* ]] && \
		[[ -f /var/tmp/wavelet_sid.txt ]]; then
		echo "Wavelet user already generated, testing.."
		result=$(curl -b /var/tmp/wavelet_sid.txt "http://${ipAddr}/mwapi?method=login&id=wavelet&pass=${md5sumWaveletPassword}" | jq .[] | head -n 1)
		if [[ ${result} == "0" ]]; then
			echo "Curl returns status 0, success!"
		else
			echo "Failed, resetting wavelet user."
			create_magewell_wavelet_user
		fi
	else
		create_magewell_wavelet_user
	fi
	# LibNDI should be installed on wavelet by default along with avahi mDNS (DEPENDENCY)
	# This needs to be run because NDI ports are often not stable, and can change resulting in unsuccessful streaming.
	# We need to set the magewell card to raw framerate 30fps, AV1 compression had pauses at 60FPS!
	magewellCommands=(	"mwapi?method=set-video-config&out-fr-convertion=frame-rate-half" \
						"mwapi?method=set-video-config&out-raw-resolution=false&out-cx=1920&out-cy=1080" \
						"mwapi?method=set-video-config&in-auto-quant-range=false&in-quant-range=full" \
						"mwapi?method=set-video-config&in-auto-color-fmt=false&in-color-fmt=rgb" \
						"mwapi?method=set-video-config&bit-rate-ratio=150" \
						"mwapi?method=set-ndi-config&enable=true")
	for i in "${magewellCommands[@]}"; do
		echo "Command: curl -b /var/tmp/wavelet_sid.txt http://${ipAddr}/$i"
		curl -b /var/tmp/wavelet_sid.txt "http://${ipAddr}/$i"
	done
	echo -e "MageWell ProConvert device should now be fully configured.."
	echo -e "Attempting to match with NDI devices found by UltraGrid..\n"
	ndiSource=$(/usr/local/bin/UltraGrid.AppImage --tool uv -t ndi:help | grep "${ipAddr}" | cut -d '(' -f1 | awk '{print $1}')
	ndiIPAddr=$(/usr/local/bin/UltraGrid.AppImage --tool uv -t ndi:help | grep "${ipAddr}" | awk '{print $5}')
	# Generate UG Stream command from the appropriate NDI Source
	deviceHostName="$(curl -b /var/tmp/wavelet_sid.txt http://${ipAddr}/mwapi?method=get-summary-info | jq '.device.name' | tr -d '"')"
	UGdeviceStreamCommand="ndi:url=${ndiIPAddr}:color=100"
	populate_to_etcd
	# Call a new module to populate the DHCP lease into FreeIPA BIND (does nothing if security layer is off)
	/usr/local/bin/wavelet_ddns_update.sh ${deviceHostName} ${ipAddr}
}

event_ptz_ndiHX(){
		# Interrogates PTZ Cam device, attempts preconfigured username and password, then tries to set appropriate settings for streaming into UltraGrid.
		echo -e "Waiting for three seconds, then attempting to connect to device..\n"
		sleep 3
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
		tput -T linux setaf 2
		ndiSource=$(/usr/local/bin/UltraGrid.AppImage --tool uv -t ndi:help | grep ${ipAddr} | cut -d '(' -f1 | awk '{print $1}')
		if [ -n ${ndiSource} ]; then
			echo -e "NDI source for this IP address not found, configuring for RTSP..\n"
			UGdeviceStreamCommand="rtsp://${ipAddr}:554/1:decompress"
			if [[ $(ffprobe -v quiet -show_streams rtsp://${ipAddr}:554/1) ]]; then
				populate_to_etcd
				echo -e "Device RTSP configured, however it may not work without further settings.\n"
				# Call a new module to populate the DHCP lease into FreeIPA BIND (does nothing if security layer is off)
				/usr/local/bin/wavelet_ddns_update.sh ${deviceHostName} ${ipAddr}
				exit 0
			else
				echo "ffmpeg could not probe this device for a valid video stream! RTSP is not valid for this device"
				exit 0
			fi
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

event_unsupportedDevice(){
		# We could do something here to attempt to connect to the device and parse whatever looks like a string to a proper value?
		echo -e "Waiting for three seconds, then attempting to connect to device..\n"
		sleep 3
		# Check to see if this device is a wavelet decoder or encoder
		read_etcd_clients_ip_sed
		if [[ "${printvalue}" == *"${ipAddr}"* ]]; then
			echo "This IP is registered in the reflectors list, so it is a wavelet encoder/decoder device. Ignoring."
			exit 0
		else
			# Check to see if this device is NDI enabled
			echo "Checking for NDI capability.."
			deviceHostName=$(nslookup ${ipAddr} | awk '{print $4}')
			ndiSource=$(/usr/local/bin/UltraGrid.AppImage --tool uv -t ndi:help | grep ${ipAddr} | cut -d '(' -f1 | awk '{print $1}')
			if [ -n ${ndiSource} ]; then
				echo -e "NDI source for this IP address: ${ipAddr} not found, attempting RTSP.."
				UGdeviceStreamCommand="rtsp://${ipAddr}:554/1:decompress"
				# Do a test here to see if RTSP is successful, if not, this probably isn't a video device and we don't want to go further.
				if [[ $(ffprobe -v quiet -show_streams ${UGdeviceStreamCommand}) ]]; then
  					populate_to_etcd
					echo -e "Device RTSP configured, however it may not work without further settings.\n"
					# Call a new module to populate the DHCP lease into FreeIPA BIND (does nothing if security layer is off)
					/usr/local/bin/wavelet_ddns_update.sh ${deviceHostName} ${ipAddr}
					exit 0
				else
					echo "ffmpeg could not probe this device for a valid video stream! RTSP is not valid for this device"
  					exit 0
				fi
			else
				echo -e "\nNDI is available for this device, querying for NDI ports and defaulting to NDI..\n"
				ndiIPAddr=$(/usr/local/bin/UltraGrid.AppImage --tool uv -t ndi:help | grep "${ipAddr}" | awk '{print $5}')
				UGdeviceStreamCommand="ndi:url=${ndiIPAddr}"
			fi
		fi
}

generate_device_info() {
	# This is all that's left after moving the hashing functions to each device block.. perhaps we want that stuff here as its portable..
	KEYNAME="/UI/short_hash/${deviceHash}"; output_return=$(read_etcd_global)
	if [[ $output_return == "" ]] then
		echo -e "\n${deviceHash} not located within etcd's /network_hash/* keyspace, assuming we have a new device and continuing with process to set parameters..\n"
	else
		echo -e "\n${deviceHash} located in etcd:\n${output_return}\n, terminating process.\nIf you wish for the device to be properly redetected from scratch, please move it to a different USB port.\n"
		# we run device_cleanup regardless!!
		device_cleanup
	fi
}

#read_commandfile(){
	# WIP
	# Commandfile generated from dnsmasq to update NS records.
	# cat $(basename $(ls -t /var/tmp/*.command | head -n1)) | `xargs`
#}

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
	ipAddr=${leasefile%_*}
	interimMacAddr=${leasefile#*_}
	macAddr=$(echo ${interimMacAddr} | cut -d . -f 1)
	echo -e "\nDetected IP Address: ${ipAddr}\n"
	echo -e "\nDetected MAC Address: ${macAddr^^}\n"
	deviceHash=$(echo "${ipAddr}:${macAddr}" | sha256sum | tr -d "[:space:]-")
	parse_macaddr "${ipAddr}" "${macAddr}"
}

populate_to_etcd(){
	# Now we populate the appropriate keys for webUI labeling and tracking:
	deviceHash=$(echo "${ipAddr}:${macAddr}" | sha256sum | tr -d "[:space:]-")
	echo -e "Checking for the device hash.."
	KEYNAME="/UI/short_hash/${packaged}"; read_etcd_global
	if [[ ${printvalue} = ${deviceHash} ]]; then
		echo "Device hash already appears to be populated, doing nothing."
		exit 0
	fi
	echo -e "Populating ETCD with discovery data..\n"
	# Packed format IP;DEVICE_LABEL(attempts to set the device hostname!);IP -- $HASH
	packaged="${ipAddr};${deviceHostName};${ipAddr}"
	KEYNAME="/UI/network_interface/${packaged}"; KEYVALUE="${deviceHash}"; write_etcd_global
	KEYNAME="/UI/short_hash/${deviceHash}"; KEYVALUE="${packaged}"; write_etcd_global
	# Values used by the controller inaccessible to UI
	KEYNAME="/network_ip/${deviceHash}"; KEYVALUE="${ipAddr}"; write_etcd_global
	KEYNAME="/network_uv_stream_command/${ipAddr}"; KEYVALUE="${UGdeviceStreamCommand}"; write_etcd_global
	echo -e "Device successfully configured, finishing up..\n"
	# since we now have a network device active on the system, we need to setup an IP ping watcher to autoremove it or note it as bad
		# This would give us a status field in UI by input hash, along with a statuscode (Good, Bad, Unhealthy) and a float tooltip for log entries perhaps?
		# KEYNAME="/UI/status/${deviceHash}"; KEYVALUE="${STATUSCODE};${LOGbase64}"; write_etcd_global
		# Read current IP subscription list
		# find this device in the IP Subscription list
		# if is not already there, append it
		# restart ping watcher service, which will set a "PROBLEM" flag if the device has network issues.  We can use this later on for the webui
		# etcd  /network_health/${ipAddr} --  GOOD or BAD
		# Finally, set and configure a watcher service for this device so that it will reconfigure the device hostname if the label is changed on the webUI
		# /usr/local/bin/wavelet_network_device_relabel.sh
	# Finally we tell wavelet there is a new input device in town so the server encoder task will regenerate next click..
	KEYNAME="GLOBAL_INPUT_DEVICE_NEW"; KEYVALUE="1"; write_etcd_global
	exit 0
}

probe_ip(){
	# Probes a specific IP.  Can be called from CLI or more commonly from detectv4l.sh
	echo -e "Detected IP Address: ${1}"
	# Checks to see if IP is decoder/encoder or other wavelet host
	wavelet_ip=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_prefix_global" "/DECODERIP/")
	if [[ "${1}" == *"{wavelet_ip}"* ]]; then
		echo "IP is registered in wavelet, it's probably a host! ignoring."
		exit 0
	else
		KEYNAME="/network_ip/${deviceHash}"; read_etcd_global
		if [[ ${printvalue} = ${$1} ]]; then
			echo "This device is already populated in network IP, doing nothing"
			exit 0
		fi
		macAddr=$(cat /var/lib/dnsmasq/dnsmasq.leases | grep ${1} | awk '{print $2}')
		parse_macaddr "${1}" "${macAddr}"
	fi
}


#####
#
# Main
#
####


logName=/var/tmp/network_device.log
if [[ -e $logName || -L $logName ]] ; then
	i=0
	while [[ -e $logName-$i || -L $logName-$i ]] ; do
		let i++
	done
	logName=$logName-$i
fi
hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)

# Process input args (if any)
for i in "$@"; do
		case $i in
			"--p")		echo "Probing $2"; probe_ip "$2"
			;;
			*)			echo "no input, called from wavelet_network sense";
			;;
		esac
done

#set -x
exec >${logName} 2>&1
read_leasefile