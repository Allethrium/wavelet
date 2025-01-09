#!/bin/bash
#
# /usr/local/bin/removedevice.sh
# This script queries etcd for a device and tries to see if it matches what was just removed.
# If this is true, we remove the key from etcd for this hostname and run a further check to see if video devices remain.
# If no video devices remain, we set the input flag to 0.


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


detect_etcd(){
# Generates an array from the available inputs on this host
# our challenge here is to blindly compare what is configured in etcd against what is currently in /dev/video*
	# clear etcd_array of old data and repopulate
	etcd_array=()
	read_etcd_inputs_array
	for i in "${etcd_array[@]}"; do 
		if [[ "$(ls /dev/video* | awk '/dev/video {match($0, /video/); print substr($0, RSTART - 5, RLENGTH + 6);}')" = "${i}" ]]; then
			echo -e "\n Device ${i} found with valid path, is alive.  Ending loop. \n"
			:
		else
			echo -e "\n Device ${i} not found with valid path.  Device is dead, performing removal. \n"
	fi
}


detect(){
	# The detection loop in this script runs against the array generated in sense_device
	# not against a single line item, as in the case with detectv4l.sh
	# To further simplify and make it easier to manage between here and detectv4l.sh, it might be good idea to generate
	# a supported devices table in etcd.   This way entries can be added and removed on the controller.
	shopt -s nullglob
	declare -A input
	FOLDERS=(/dev/v4l/by-id/*)
	for folder in "${FOLDERS[@]}"; do
	[[ -d "$folder" ]] && echo "$folder"
	done
	shopt -u nullglob
	echo -e "\n testing values..\n"
	IFS=@
	case "@${FOLDERS[*]}@" in
		(*"IPEVO"*)							echo -e "IPEVO Document Camera device detected, ending detection \n"; exit 0
		;;
		(*"Logitech_Screen_Share"*)			echo -e "Logitech HDMI-USB Capture device detected, ending detection \n"; exit 0
		;;
		(*"Magewell"*)						echo -e "Magewell USB Capture HDMI device detected, ending detection \n"; exit 0
		;;
		(*)									echo -e "No supported video devices have been detected.  Setting input device presence to disabled. \n"; KEYNAME="/${hostNameSys}/INPUT_DEVICE_PRESENT"; KEYVALUE=1; write_etcd_global; echo -e "etcd entries cleaned up for this device and input flag set to 0."
		;;
	esac
}

#####
#
# Main 
#
#####

hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
set -x
exec >/var/home/wavelet/logs/removedevice.log 2>&1
detect_etcd