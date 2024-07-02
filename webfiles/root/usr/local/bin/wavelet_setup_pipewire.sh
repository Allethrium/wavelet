#!/bin/bash
# This module sets the pipewire audio source to be the same as the video source, or a best guess.
# Would it make more sense with the new webUI to try and do this with an audio togglebutton?


etcd_get_currentvideosource(){
	currentInputHash=$(etcdctl --endpoints=192.168.1.32:2379 get "uv_hash_select")
	long_interface_path=$(etcdctl  --endpoints=192.168.1.32:2379 get "/hash/${currentInputHash}")
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
