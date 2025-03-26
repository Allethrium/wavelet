#!/bin/bash
#
# Upon the connection of a new USB device, this script is called by Udev rules.  
# Note Udev calls a bootstrap script which THEN calls this script,
# because the usb subsystem is locked until the rule execution is completed!
# It will attempt to make sense of available v4l devices and update etcd
# The WebUI updates, and is updated from, many of these keys.


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
read_etcd_keysonly(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_keysonly" "${KEYNAME}")
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

sense_devices_local() {
	# we're just looking at what's in /dev/v4l here, effectively.
	# Might be a good idea to try and compare this against UG's output and add selection logic in future though..
	# forEach > ug -t v4l2:{i} | process output here, select appropriate pxl/res | test dev for validation via UG | done
	shopt -s nullglob
	declare -a v4lArray=(/dev/v4l/by-id/*)
	for index in "${!v4lArray[@]}" ; do
		[[ ${v4lArray[$index]} =~ -index1$ ]] && unset -v 'v4lArray[$index]';
	done
	
	array=("${v4lArray[@]}")
	for i in "${v4lArray[@]}"; do
		device_string_long=$i
		v4l_device_path="/dev/$(ls -Artl $i* | awk '{print $11}' | awk -F/ '{print $3}')"
		echo -e "Device path ${v4l_device_path} located for ${device_string_long}"
		# generate device hashes and proceed to next step
		generate_device_info
	done
	shopt -u nullglob
}

generate_device_info() {
	echo -e "Now generating device info for each item presently located in /dev/v4l/by-id.."
	echo -e "Working on ${device_string_long}"
	device_string_short=$(echo ${hostNameSys}/"${device_string_long}" | sed 's/.*usb-//')
	info=$(v4l2-ctl -D -d ${v4l_device_path})
	# here we parse this information
	cardType=$(echo "${info}" | awk -F ":" '/Card type/ { print $2 }')
	# Bus info (first instance only, it's repeated oftentimes)
	bus_info=$(echo "${info}" | awk -F ":" '/Bus info/ { print $4;exit; }')
	# Serial (if exists)
	serial=$(echo "${info}" | awk -F ":" '/Serial/ { print $2 }')
	echo -e "device name is: ${device_string_short}"
	echo -e "card type is: $cardType"
	echo -e "bus address is: $bus_info"
	echo -e "device serial is: $serial"
	deviceHash=$(echo "$device_string_short, $cardType , $bus_info, $serial" | sha256sum | tr -d "[:space:]-")
	echo -e "generated device hash: $deviceHash \n"
	device_string_short=$(echo "${device_string_long}" | sed 's/.*usb-//')
	# Let's look for the device hash in the /interface prefix to make sure it doesn't already exist!
	KEYNAME="/UI/short_hash/${deviceHash}"; read_etcd_global; output_return=${printvalue}
	if [[ $output_return == "" ]] then
		echo -e "${deviceHash} not located within etcd, assuming we have a new device and continuing with process to set parameters.."
		isDevice_input_or_output
	else
		echo -e "${deviceHash} located in etcd:\n${output_return}\nIf you wish for the device to be properly redetected from scratch, please move it to a different USB port."
		# we run device_cleanup regardless!!
		device_cleanup
	fi
}

isDevice_input_or_output() {
	# Are we outputting audio/video signals someplace or is this an input?  we determine this here
	case ${device_string_long} in 
		*BiAmp*)				echo -e "BiAmp HDMI-USB Capture device detected..\n"						&&	event_biAmp
		;;
		*audio*)				echo -e "Audio out device detected..\n"										&&	echo -e "an audio output selection event would be called here\n"
		;;
		*)						echo -e "Not a biAmp, we are probably connecting video capture dev.\n"		&&	set_device_input
		;;
	esac
}

set_device_input() {
	# called from generate_device_info from the nested if loop checking for pre-existing deviceHash in etcd /UI/short_hash
	# device_string_short is effectively the webui Label / banner text.
	# Because we cannot query etcd by keyvalue, we must create a reverse record in order to clean up
	# This forms a character delimited packed format that we utilize in the PHP module to extract data.
	# This can be modified from the UI, hence we need to track the device by a more immutable hash value elsewhere
	#
	# Packed format:
	#	HOSTNAME;HOSTNAMEPRETTY;DEVICE LABEL;DEVICE_FULLPATH -- $HASH
	#
	#
	interfaceEntry="${hostNameSys};${hostNamePretty};${device_string_short};${device_string_long}"
	KEYNAME="/UI/interface/${interfaceEntry}"; KEYVALUE="${deviceHash}"; write_etcd_global	
	# And the reverse lookup prefix. This is updated from set_label.php when the webUI changes a device label
	KEYNAME="/UI/short_hash/${deviceHash}"; KEYVALUE="${interfaceEntry}"; write_etcd_global
	# This is necessary for the owning encoder to know what to test against, along with the reverse value
	KEYVALUE="/${hostNameSys}/inputs${device_string_long}"; KEYNAME="${deviceHash}"; write_etcd_global
	# Hash - short path lookup
	KEYNAME="/${hostNameSys}/devpath_lookup/${deviceHash}"; KEYVALUE="${v4l_device_path}"; write_etcd_global
	# notify watcher that input device configuration has changed
	KEYNAME=NEW_DEVICE_ATTACHED; KEYVALUE=1; write_etcd_global
	echo -e "resetting variables to null."
	deviceHash=""
	device_string_short=""
	KEYNAME="/${hostNameSys}/INPUT_DEVICE_PRESENT"; KEYVALUE="1"; write_etcd_global
	# This flag is necessary to tell the wavelet_encoder module to regenerate the switcher list, the value is "consumed"
	# I.E set back to 0 once this is done.
	KEYNAME="/${hostNameSys}/INPUT_DEVICE_NEW"; KEYVALUE="1"; write_etcd_global
	KEYNAME="GLOBAL_INPUT_DEVICE_NEW"; KEYVALUE="1"; write_etcd_global
	detect
}


device_cleanup() {
	# always the last thing we do here, compares /dev/v4l/by-id to /UI/short_hash and /UI/interface/, removes "dead" devices.  
	# These dead devices could also be other inputs supported by existing USB devices, but with a different interface (IE /dev/video0 and /dev/video1 might be the same device, one UVC video, one audio)
	# Get a clean list of devices in populated etcd
	KEYNAME="/${hostNameSys}/inputs/"
	activeInterfaceDevices=$(read_etcd_keysonly | sed 's|/${hostnameSys}/inputs||g')
	IFS=' ' read -a interfaceLongArray <<< ${activeInterfaceDevices}
	unset IFS
	# Iterate through array and try to find it in v4lArray, if found we REMOVE it from interfaceLongArray, so we end up with only devices which don't physically exist on this system
	for i in ${interfaceLongArray[@]}; do
		if [[ "${v4lArray[*]}" =~ "${i}" ]]; then
			interfaceLongArray=("${interfaceLongArray[*]/$i}")
			echo -e "$i removed"
		fi
	done

	# After this process is completed we will wind up with a pared down array, and hopefully nothing
	if (( ${#interfaceLongArray[@]} == 0 )); then
		echo -e "Array is empty, there is no discrepancy between detected device paths and available devices in Wavelet."
		:
	else
		echo -e "Orphaned devices located:\n"
		printf "%s\n" "${interfaceLongArray[@]}"
		for i in "${interfaceLongArray[@]}"; do
			if [ ! -z "$i" ]; then
				:
			else
				cleanupStringLong="${i}"
				echo -e "\nCleanup device is ${cleanupStringLong}"
				# find the device hash 
				KEYNAME="/${hostNameSys}/inputs${cleanupStringLong}"; cleanupHash=$(read_etcd)
				echo -e "Device hash located as ${cleanupHash}"
				# delete the input caps key for the missing device
				echo -e "Deleting /${hostNameSys}/inputs${cleanupStringLong}  entry"
				KEYNAME="/${hostNameSys}/inputs${cleanupStringLong}"; delete_etcd_key_global
				# finally, find and delete from interface prefix - Guess we need ANOTHER lookup table to manage to keep all of this straight..
				KEYNAME="/UI/interface/short_hash/${cleanupHash}"; read_etcd_global; cleanupInterface=${printvalue}
				echo -e "Device UI Interface label located in /UI/short_hash/${cleanupHash} for the value ${cleanupInterface}"
				echo -e "Deleting /UI/interface/short_hash/${cleanupHash} entry"
				delete_etcd_key
				echo -e "Deleting /UI/interface/${cleanupInterface} entry"
				KEYNAME="/UI/interface/${cleanupInterface}"; delete_etcd_key_global
				echo -e "Device entry ${cleanupStringLong} should be removed along with all references to ${cleanupHash}\n\n"
			fi
		done
	fi
}

detect() {
# we still need this fairly simple approach, as the Logitech screen share USB devices have no serial number, making multiple inputs is hard to handle.
# is called in a foreach loop from detect_ug devices, therefore it is already instanced for each device
# Because we have already run a case in for device type, this detection routine will be handling video output devices ONLY.
# If we need to support audio output devices, we need to do it via a different path branching from isDevice_input_or_output
	echo -e "Device string is ${device_string_long} \n"
	case ${device_string_long} in
	*IPEVO*)						echo -e "IPEVO Document Camera device detected.."				&& event_ipevo
	;;
	*"Logitech_Screen_Share"*)		echo -e "Logitech HDMI-USB Capture device detected.."			&& event_logitech_hdmi
	;;
	*Magewell*)						echo -e "Magewell HDMI-USB Capture device detected.."			&& event_magewell
	;;
	*EPSON*)						echo -e "EPSON Capture device detected.."						&& event_epson
	;;
	*Dell_Webcam_WB3023*)			echo -e "Dell WB3023 Webcam	device detected.."					&& event_dellWB3023
	;;
	*Integrated_Webcam_FHD*)		echo -e "Dell Integrated FHD device detected.."					&& event_dellIntFHD
	;;
	*)								echo -e "Unknown device detected, attempting to process.."		&& event_unknowndevice
	;;
	esac
}

# VIDEO output device blocks
# each of these blocks contains specific configuration options that must be preset for each device in order for them to work.  
# We will have to add to this over time to support more devices appropriately.
event_ipevo() {
	echo -e "IPEVO Camera detection running.."
	KEYNAME="inputs${device_string_long}"; KEYVALUE="-t v4l2:codec=MJPG:convert=RGB:size=1920x1080:tpf=1/30:device=${v4l_device_path}"; write_etcd
	echo -e "Detection completed for IPEVO device..\n"
}
event_logitech_hdmi() {
	echo -e "Setting up Logitech USB capture card.."
	KEYNAME="inputs${device_string_long}"; KEYVALUE="-t v4l2:codec=MJPG:convert=RGB:size=1920x1080:tpf=1/30:device=${v4l_device_path}"; write_etcd
	echo -e "Detection completed for Logitech HDMI Capture device..\n"
}
event_magewell() {
	echo -e "Setting up Magewell USB capture card.."
	KEYNAME="inputs${device_string_long}"; KEYVALUE="-t v4l2:codec=YUYV:size=1920x1080:tpf=1/30:convert=RGB:device=${v4l_device_path}"; write_etcd
	echo -e "Detection completed for device..\n"
}
event_epson() {
	echo -e "Setting up EPSON Document camera device..."
	KEYNAME="inputs${device_string_long}"; KEYVALUE="-t v4l2:codec=MJPG:size=1920x1080:tpf=1/24:device=${v4l_device_path}"; write_etcd
	echo -e "Detection completed for device..\n"
}
event_dellWB3023(){
	echo -e "Setting up Dell WB3023 webcam.."
	KEYNAME="inputs${device_string_long}"; KEYVALUE="-t v4l2:codec=NV12:size=640x480:tpf=1/30:device=${v4l_device_path}"; write_etcd
	echo -e "Detection completed for device..\n"
}
event_dellIntFHD(){
	echo -e "Setting up Dell Integrated Laptop Webcam.."
	KEYNAME="inputs${device_string_long}"; KEYVALUE="-t v4l2:codec=YUYV:size=640x480:tpf=1/30:device=${v4l_device_path}"; write_etcd
	echo -e "Detection completed for device..\n"
}
event_unknowndevice() {
# 30fps is a compatibility setting, catch all for other devices we will leave at 30.  Try YUYV with RGB conversion..
	echo -e "The connected device has not been previously assigned an input ID for the UI component.  Storing hash."
	KEYNAME="inputs${device_string_long}"; KEYVALUE="-t v4l2:codec=YUYV:size=1920x1080:tpf=1/30:convert=RGB:device=${v4l_device_path}"; write_etcd
	echo -e "Detection completed for device..\n"
}

#AUDIO output device block
event_biamp() {
# This should set the biAmp up as a Pipewire audio output sink by default, so Wavelet will stream any audio data the system receives into the biAmp
	echo -e "biAmp detection running..\n"
	KEYNAME="/inputs/${device_string_long}"; KEYVALUE="???"; KEYNAME=${device_string_long}; write_etcd
	# Set AUDIO_OUT flag so the UI does not generate an input button, but an audio OUT button instead?
	KEYVALUE="1"; KEYNAME=${device_string_long}/AUDIO_OUT; write_etcd
	echo -e "\n Detection completed for BiAmp audio device..\n"
}

detect_self(){
	systemctl --user daemon-reload
	# Detect_self in this case relies on the etcd type key
	KEYNAME="/${hostNameSys}/type"; read_etcd_global
	echo -e "Host type is: ${printvalue}\n"
	case "${printvalue}" in
		enc*)                                   echo -e "I am an Encoder\n"										;		encoder_checkNetwork 1
		;;
		dec*)                                   echo -e "I am a Decoder\n"										;		exit 0
		;;
		svr*)                                   echo -e "I am a Server, allowing device sense to proceed.."		;		sense_devices_local;	redetect_network_devices
		;;
		*)                                      echo -e "This device is other, ending process\n"				;		exit 0
		;;
	esac
}

encoder_checkNetwork(){
	# Checks for a network connection, without this detection may proceed too quickly and devices may not populate
	if [[ "$1" > 3 ]]; then
		echo -e "\nThree repeat tries exceeded, there may be a network configuration issue.  Please troubleshoot\n"
		touch /home/wavelet/NETWORK_ERROR_FLAG
		exit 0
	fi
	ping -c 3 $(cat /var/home/wavelet/config/etcd_ip)
	if [[ $? -eq 0 ]]; then
		echo -e "Online and connected to Wavelet Server, continuing..\n"
		sense_devices_local
	else
		echo -e "No network connection, device registration will be unsuccessful, sleeping for 5 seconds and trying again..\n"
		sleep 5
		let "$1=$1++"
		encoder_checkNetwork 
	fi
}

redetect_network_devices(){
	# Redetects network devices
	for i in $(cat /var/lib/dnsmasq/dnsmasq.leases | awk '{print $3}'); do
		echo "Probing IP Address: ${i}"
		# Check to see if we're a registered wavelet device
		wavelet_ip=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_prefix_global" "/DECODERIP/")
		if [[ $i == *"{wavelet_ip}"* ]]; then
			echo "IP is a wavelet host, ignoring."
			exit 0
		else
			echo "Calling network device sense for IP Address: ${i}"
			/usr/local/bin/wavelet_network_device.sh "--p" "${i}"
		fi
	done
}

#####
#
# Main
#
#####


#set -x
exec >/var/home/wavelet/logs/detectv4l.log 2>&1
hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
device_cleanup
detect_self