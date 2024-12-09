#!/bin/bash
#
# Upon the connection of a new USB device, this script is called by Udev rules.  
# Note Udev calls a bootstrap script which THEN calls this script,
# because the usb subsystem is locked until the rule execution is completed!
# It will attempt to make sense of available v4l devices and update etcd
# WebUI updates, and is updated from, many of these keys.

# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
read_etcd(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd" ${KEYNAME})
	echo -e "Key Name: {$KEYNAME} read from etcd for value: $printvalue for host: $(hostname)\n"
}
read_etcd_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}") 
	echo -e "Key Name: {$KEYNAME} read from etcd for Global Value: $printvalue\n"
}
read_etcd_prefix(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_prefix" "${KEYNAME}")
	echo -e "Key Name: {$KEYNAME} read from etcd for value: $printvalue for host: $(hostname)\n"
}
read_etcd_clients_ip() {
	return_etcd_clients_ip=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_clients_ip")
}
read_etcd_clients_ip_sed() {
	# We need this to manage the \n that is returned from etcd.
	# the above is useful for generating the reference text file but this parses through sed to string everything into a string with no newlines.
	processed_clients_ip=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_clients_ip" | sed ':a;N;$!ba;s/\n/ /g')
}
read_etcd_json_revision(){
	# Special case used in controller
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_json_revision" uv_hash_select | jq -r '.header.revision')
}
read_etcd_lastrevision(){
	# Special case used in controller
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_lastrevision")	
}
read_etcd_keysonly(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_keysonly" "${KEYNAME}")
	echo -e "Key Name {$KEYNAME} read from etcd for key values: $printvalue\n"
}
write_etcd(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name: ${KEYNAME} set to: ${KEYVALUE} under: /$(hostname)/.\n"
}
write_etcd_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name ${KEYNAME} set to ${KEYVALUE} for Global value.\n"
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
generate_service(){
	# Can be called with more args with "generate_servier" ${keyToWatch} 0 0 "${serviceName}"
	/usr/local/bin/wavelet_etcd_interaction.sh "generate_service" "${serviceName}"
}

sense_devices() {
	shopt -s nullglob
	declare -a v4lArray=(/dev/v4l/by-id/*)
	for index in "${!v4lArray[@]}" ; do
		[[ ${v4lArray[$index]} =~ -index1$ ]] && unset -v 'v4lArray[$index]';
	done
	array=("${v4lArray[@]}")
	for i in "${v4lArray[@]}"; do
		device_string_long=$i
		v4l_device_path="/dev/$(ls -Artl $i* | awk '{print $11}' | awk -F/ '{print $3}')"
		echo -e "Device path ${v4l_device_path} located for ${device_string_long} \n"
		# generate device hashes and proceed to next step
		generate_device_info
	done
	shopt -u nullglob
}


generate_device_info() {
	echo -e "\n \n \n Now generating device info for each item presently located in /dev/v4l/by-id.. \n"
	echo -e "Working on ${device_string_long}\n"
	device_string_short=$(echo $(hostname)/"${device_string_long}" | sed 's/.*usb-//')
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
	KEYNAME="/hash/${deviceHash}"; read_etcd_global; output_return=${printvalue}
	if [[ $output_return == "" ]] then
		echo -e "${deviceHash} not located within etcd, assuming we have a new device and continuing with process to set parameters..\n"
		isDevice_input_or_output
	else
		echo -e "\n${deviceHash} located in etcd:\n\n${output_return}\n\n, terminating process.\nIf you wish for the device to be properly redetected from scratch, please move it to a different USB port.\n"
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
	# called from generate_device_info from the nested if loop checking for pre-existing deviceHash in etcd /hash/
	# populated device_string_short with hash value, this is used by the interface webUI component
	# device_string_short is effectively the webui Label / banner text.
	# Because we cannot query etcd by keyvalue, we must create a reverse lookup prefix for everything we want to be able to clean up!!
	KEYNAME="/interface/$(hostname)/${device_string_short}"; KEYVALUE="${deviceHash}"; write_etcd_global	
	# And the reverse lookup prefix - N.B this is updated from set_label.php when the webUI changes a device label/banner string! 
	KEYNAME="/short_hash/${deviceHash}"; KEYVALUE=$(hostname)/${device_string_short}; write_etcd_global
	# We need this to perform cleanup "gracefully"
	KEYNAME="/long_interface${device_string_long}"; KEYVALUE=${deviceHash}; write_etcd_global
	# This will enable us to find the device from its hash value, along with the registered host encoder, like a reverse DNS lookup..
	# GLOBAL value
	echo -e "Attempting to set keyname ${deviceHash} for $(hostname)${device_string_long}"
	KEYNAME="/hash/${deviceHash}"
	# Stores the device data under hostname/inputs/device_string_long
	KEYVALUE="/$(hostname)/inputs${device_string_long}"; write_etcd_global
	# notify watcher that input device configuration has changed
	KEYNAME=new_device_attached; KEYVALUE=1; write_etcd_global
	echo -e "resetting variables to null."
	deviceHash=""
	device_string_short=""
	KEYNAME=INPUT_DEVICE_PRESENT; KEYVALUE=1; write_etcd
	detect
}


device_cleanup() {
	# always the last thing we do here, compares /dev/v4l/by-id to /hash/ and /interface/, removes "dead" devices.  
	# These dead devices could also be other inputs supported by existing USB devices, but with a different interface (IE /dev/video0 and /dev/video1 might be the same device, one UVC video, one audio)
	# Get a clean list of devices in populated etcd
	KEYNAME="/long_interface/"
	activeInterfaceDevices=$(read_etcd_keysonly | sed 's|/long_interface||g')
	IFS=' ' read -a interfaceLongArray <<< ${activeInterfaceDevices}
	unset IFS
	#$(etcdctl --endpoints=${ETCDENDPOINT} get /long_interface/ --prefix --keys-only | sed 's|/long_interface||g')
	# Iterate through array and try to find it in v4lArray, if found we REMOVE it from interfaceLongArray, so we end up with only devices which don't physically exist on this system
	for i in ${interfaceLongArray[@]}; do
		if [[ "${v4lArray[*]}" =~ "${i}" ]]; then
			interfaceLongArray=("${interfaceLongArray[*]/$i}")
			echo -e "$i removed"
		fi
	done

	# After this process is completed we will wind up with a pared down array, and hopefully nothing
	if (( ${#interfaceLongArray[@]} == 0 )); then
		echo -e "Array is empty, there is no discrepancy between detected device paths and available devices in Wavelet.\n"
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
					# delete the input caps key for the missing device
					echo -e "Deleting $(hostname)/inputs${cleanupStringLong}  entry"
					KEYNAME="/$(hostname)/inputs${cleanupStringLong}"; delete_etcd_key_global
					# find the device hash 
					KEYNAME="/long_interface${cleanupStringLong}"; cleanupHash=$(read_etcd)
					echo -e "Device hash located as ${cleanupHash}"
					# delete from long_interface prefix
					echo -e "Deleting /long_interface${cleanupStringLong} entry"
					delete_etcd_key
					# delete from hash prefix
					echo -e "Deleting /hash/${cleanupHash} entry"
					KEYNAME="/hash/${cleanupHash}"; delete_etcd_key_global
					# finally, find and delete from interface prefix - Guess we need ANOTHER lookup table to manage to keep all of this straight..
					KEYNAME="/short_hash/${cleanupHash}"; read_etcd_global; cleanupInterface=${printvalue}
					echo -e "Device UI Interface label located in /short_hash/${cleanupHash} for the value ${cleanupInterface}"
					echo -e "Deleting /short_hash/${cleanupHash}  entry"
					delete_etcd_key
					echo -e "Deleting /interface/${cleanupInterface} entry"
					KEYNAME="/interface/$${cleanupInterface}"; delete_etcd_key_global
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
	*IPEVO*)						echo -e "IPEVO Document Camera device detected.. \n"				&& event_ipevo
	;;
	*"Logitech Screen Share"*)		echo -e "Logitech HDMI-USB Capture device detected.. \n"			&& event_logitech_hdmi
	;;
	*Magewell*)						echo -e "Magewell HDMI-USB Capture device detected.. \n"			&& event_magewell
	;;
	*EPSON*)						echo -e "EPSON Capture device detected.. \n"						&& event_epson
	;;
	*Dell_Webcam_WB3023*)			echo -e "Dell WB3023 Webcam	device detected.. \n"					&& event_dellWB3023
	;;
	*)								echo -e "Unknown device detected, attempting to process..\n"		&& event_unknowndevice
	;;
	esac
}

# VIDEO output device blocks
# each of these blocks contains specific configuration options that must be preset for each device in order for them to work.  
# We will have to add to this over time to support more devices appropriately.
event_ipevo() {
	echo -e "IPEVO Camera detection running..\n"
	KEYNAME="inputs${device_string_long}"; KEYVALUE="-t v4l2:codec=MJPG:convert=RGB:size=1920x1080:tpf=1/30:device=${v4l_device_path}"; write_etcd
	echo -e "\nDetection completed for IPEVO device..\n"
}
event_logitech_hdmi() {
	KEYNAME="inputs${device_string_long}"; KEYVALUE="-t v4l2:codec=MJPEG:convert=RGB:size=1920x1080:tpf=1/30:device=${v4l_device_path}"; write_etcd
	echo -e "\nDetection completed for Logitech HDMI Capture device..\n"
}
event_magewell() {
	echo -e "Setting up Magewell USB capture card..\n"
	KEYNAME="inputs${device_string_long}"; KEYVALUE="-t v4l2:codec=YUYV:size=1920x1080:tpf=1/30:convert=RGB:device=${v4l_device_path}"; write_etcd
	echo -e "\nDetection completed for device..\n"
}
event_epson() {
	echo -e "Setting up EPSON Document camera device...\n"
	KEYNAME="inputs${device_string_long}"; KEYVALUE="-t v4l2:codec=MJPG:size=1920x1080:tpf=1/24:device=${v4l_device_path}"; write_etcd
	echo -e "\nDetection completed for device..\n"
}
event_dellWB3023(){
	echo -e "Setting up Dell WB3023 webcam..\n"
	KEYNAME="inputs${device_string_long}"; KEYVALUE="-t v4l2:codec=MJPG:size=640x480:tpf=1/30:device=${v4l_device_path}"; write_etcd
	echo -e "\nDetection completed for device..\n"
}
event_unknowndevice() {
# 30fps is a compatibility setting, catch all for other devices we will leave at 30.  Try YUYV with RGB conversion..
	echo -e "The connected device has not been previously assigned an input ID for the UI component.  Storing hash.\n"
	KEYNAME="inputs${device_string_long}"; KEYVALUE="-t v4l2:codec=YUYV:size=1920x1080:tpf=1/30:convert=RGB:device=${v4l_device_path}"; write_etcd
	echo -e "\n Detection completed for device..\n"
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
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*) 					echo -e "I am an Encoder, allowing device sense to proceed..\n"; encoder_checkNetwork 1
	;;
	decX.wavelet.local)		echo -e "I am a Decoder, but my hostname is generic.  An error has occurred at some point, and needs troubleshooting.\nTerminating process."; exit 0
	;;
	dec*)					echo -e "I am a Decoder \n"; exit 0
	;;
	livestream*)			echo -e "I am a Livestream ouput gateway \n"; exit 0
	;;
	gateway*)				echo -e "I am an input Gateway for another video streaming system \n"; exit 0
	;;
	svr*)					echo -e "I am a Server, allowing device sense to proceed.."; sense_devices
	;;
	*) 						echo -e "This device Hostname is not set approprately, I don't know what I am.  Exiting \n"; exit 0
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
	ping -c 3 192.168.1.32
	if [[ $? -eq 0 ]]; then
		echo -e "Online and connected to Wavelet Server, continuing..\n"
		sense_devices
	else
		echo -e "No network connection, device registration will be unsuccessful, sleeping for 5 seconds and trying again..\n"
		sleep 5
		let "$1=$1++"
		encoder_checkNetwork 
	fi
}


#####
#
# Main
#
#####

exec >/home/wavelet/detectv4l.log 2>&1

# Check RD flag set here, if it's on we need to reset the device_redetect global flag first.
if [[ "${1}" = "RD" ]]; then
	echo -e "Called by refresh devices, hanging watcher for two seconds whilst we reset the key.."
	systemctl --user disable wavelet_device_redetect.service --now
	KEYNAME="DEVICE_REDETECT"; KEYVALUE="0"; write_etcd_global
	sleep 2
	systemctl --user enable wavelet_device_redetect.service --now
fi

# check to see if I'm a server or an encoder
echo -e "\n********Begin device detection and registration process...********"
detect_self
device_cleanup
