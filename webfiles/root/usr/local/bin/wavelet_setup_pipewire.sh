#!/bin/bash
# This module sets the pipewire audio source to be the same as the video source, or a best guess.
# Would it make more sense with the new webUI to try and do this with an audio togglebutton?

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


etcd_get_currentvideosource(){
	KEYNAME="uv_hash_select"; read_etcd_global
	currentInputHash=${printvalue}
	KEYNAME="/hash/${currentInputHash}"; read_etcd_global
	long_interface_path=${printvalue}
	# use awk to clean long_interface var for matching
	# this should give us Magewell USB Capture, Magewell USB Capture+, Logitech Screen Share or IPEVO Ziggi, or whatever else we get
	return long_interface_var_cleaned
}

# create clean audio source list for array
cleaned_wpctl_output=$(wpctl status | sed -n '/Filters/q;p' | awk '/Sources:/ {p=1;next}p' | sed 's/^[[:space:]]*|\([[:blank:]]\)*\|[\(]//g' | sed 's/[| ]//g; s/\([^[\]]*\)//' | sed 's/\[\[[^[]]*\]\]//g' | sed 's/\[vol:1.00\]//' | sed 's/AnalogStereo//' | sed 's/\*//' | tr '\n' ' ')
# This gives us something like;
#	47.IPEVOZiggi-HDPlus
#	48.LogitechScreenShare
#	51.USBCaptureHDMI+

# create associative array and read out available detected audio sources from Pipewire
declare -A wpctl_audio_sources_array
IFS=$'\t' read -r "${wpctl_audio_sources_array[@]}" <<< "$cleaned_wpctl_output"
for key in "${!wpctl_audio_sources_array[@]}"; do
    echo "Key: $key Value: ${wpctl_audio_sources_array[$key]}"
done
# get active video source device from etcd
etcd_get_currentvideosource
echo -e "\nCurrent Video Source is: ${etcd_currentvideosource}\n"
# try to match the currentvideosource with something in the array
	#	for key in "${!wpctl_audio_sources_array[@]}"; do
    # 		if [[ ${etcd_currentvideosource} == *${wpctl_audio_sources_array[$key]}* ]]; then 
    #			echo "\nMatch found for $key\n"
    #		fi
	#	done
# set Pipewire to use device
wpctl set-default ${keyIndex}
