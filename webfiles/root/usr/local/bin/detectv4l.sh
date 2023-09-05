#!/bin/bash
#
# Upon the connection of a new USB device, this script is called by Udev rules.  Note Udev calls a bootstrap script which THEN calls this script,
# because the usb subsystem is locked until the rule execution is completed!
# It will attempt to list the most recently installed v4l device

# Can also call UltraGrid directly to try and use the same mechanism to parse available devices, explore this route..

#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=http://192.168.1.32:2379
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

sense_device() {
# Old, only here to laugh at.	
	sleep .25
	device_string_long=$(ls -Artl /dev/v4l/by-id | tail -n 2 | awk '{print $9,$11}')
	echo -e 'Last device plugged in is: \n'
	echo '${device_string_long}' 
	# select lowest value (usually correct device)
	# store device path in a variable 
	v4l_device_path=$(ls -Artl /dev/v4l/by-id | tail -n 2 | awk '{print $11}' | sort -nk 2 | head -1 | awk -F/ '{print $3}')
	echo $v4l_device_path
}

sense_devices() {
# Alternate sense which refreshes ALL usb devices every time something new is plugged in - may work better?
# Probably also here to laugh at, but is how it works currently.
	shopt -s nullglob
	declare -a array=(/dev/v4l/by-id/*)
	echo -e "\n \n Our array contains some duplicates which we don't want, so we'll remove them..\n"
	for index in "${!array[@]}" ; do 
		[[ ${array[$index]} =~ -index1$ ]] && unset -v 'array[$index]' ; done
	echo -e "\n reassign array indices so they make sense.. \n"
	array=("${array[@]}")
	echo -e "Looping through array.."
	for i in "${array[@]}"
	do
		device_string_long=$i
        echo -e "Finding /dev/video$ symlink for $i"
        v4l_device_path=$(ls -Artl $i* | awk '{print $11}' | awk -F/ '{print $3}')
        echo -e "Device path ${v4l_device_path} located for $i \n"
        detect
	done
	shopt -u nullglob
}


# Here we detect valid devices, and need to maintain a database of usable devices and their appropriate types
# The concept is just a string match from whatever was last plugged into a USB port, 
# which triggers a udev rule to call this script.
# Currently because of the way the logic works, we really only support a single device of each type.
# I.E. you can have an IPEVO document camera with a Logitech HDMI-USB input capture device, and a Magewell USB capture device
# You can't have two logitechs at once because the computer has no way of knowing which is which.
# NOTE - *Integrated_Webcam_HD*)  is IGNORED in the event you want to run a server off the laptop and 
# NOT have it run as an encoder.
detect() {
	echo "Device string is ${device_string_long}"
	case $device_string_long in
	*IPEVO*) 					echo -e "IPEVO Document Camera device detected \n" && event_ipevo
	;;
	*Logitech_Screen_Share*)			echo -e "Logitech HDMI-USB Capture device detected \n" && event_lghdmi
	;;
	*Magewell*)					echo -e "Magewell USB Capture HDMI device detected \n" && event_magewellhdmi
	;;
	usb-Intel_R__RealSense_TM__Depth_Camera_435*)	echo -e "Intel Realsense D435 Detected \n" && event_realsense_d435
	;;
	*) 						echo -e "This device is not yet documented, or not a video USB device. Unsupported. If you think the device should be supported, contact the project maintainers.\n" && exit 0
	;;
	esac
}

event_ipevo() {
# each of these blocks contains specific configuration options that must be preset for each device
	KEYVALUE="-t v4l2:codec=MJPG:size=1920x1080:tpf=1/30:convert=RGB:device=/dev/${v4l_device_path}"
	KEYNAME=v4lDocumentCam
	write_etcd
	KEYNAME=INPUT_DEVICE_PRESENT
	KEYVALUE=1
	write_etcd
}

event_elmo() {
# this is still here because 1)i don't have an elmo camera handy to test, 2) it's the old way I did it, as an example.
# because this is designed to run on an immutable filesystem, symlinks aren't persistent between reboots.
        DEVPATH=/dev/v4l_document_camera_0
		if test -f "$DEVPATH"; then
			echo "${DEVPATH} already exists, linking $v4l_device_path to /dev/v4l_document_camera_1"
			ln -sf /dev/"${v4l_device_path}" /dev/v4l_document_camera_1
			DEVPATH=/dev/v4l_document_camera_1
			DetectetcdValue=$DEVPATH
			etcdKeyName=v4lcam1
			write_etcd
			else
				echo "New device, Document camera linked to /dev/v4l_document_camera_0"
				ln -sf /dev/"${v4l_device_path}" /dev/v4l_document_camera_0
				DetectetcdValue=$DEVPATH
				etcKeyName=v4lcam0
				write_etcd
		fi
}

event_lghdmi() {
	KEYVALUE="-t v4l2:codec=YUYV:size=1920x1080:tpf=1/30:convert=RGB:device=/dev/${v4l_device_path}"
	KEYNAME=hdmi_logitech
	write_etcd
	KEYNAME=INPUT_DEVICE_PRESENT
	KEYVALUE="1"
	write_etcd
}

event_magewellhdmi() {
# The Magewell supports 1080p @ 60FPS, so we will set that here
	KEYVALUE="-t v4l2:codec=YUYV:size=1920x1080:tpf=1/60:convert=RGB:device=/dev/${v4l_device_path}"
	KEYNAME=hdmi_magewell
	write_etcd
	KEYNAME=INPUT_DEVICE_PRESENT
	KEYVALUE="1"
	write_etcd
}

event_realsense_d435() {
# The Intel RealSense webcam is a 3D depthsensing webcam.  It's not really useful here, but it's all I had at home to test..
# This is an example of how i'd add a new device
# 1) plug it in
# 2) determine what was added by v4l by ls /dev/v4l/by-id
# 3) clear && v4l2-ctl -d /dev/video$ -D --list-formats-ext
# 4) determine a reasonable resolution to utilize
# 5) test streaming with UG, with any luck there won't be any odd quirks.
# 6) took me about ten minutes for this..
# 7) the Controller script would need modding to actually utilize this..
	KEYVALUE="-t v4l2:codec=YUYV:size=1280x720:tpf=1/10:convert=RGB:device=/dev/video6"
	KEYNAME=realsensed435
	write_etcd
	KEYNAME=INPUT_DEVICE_PRESENT
	KEYVALUE="1"
	write_etcd	
}

event_unk() {
	# placeholder for future devices to be cut and pasted in - write_etc for input device present is disabled here
	# we don't want any old unknown device messing with operation.
	KEYVALUE="-t v4l2:codec=?:size=1920x1080:tpf=1/30:convert=RGB:device=/dev/${v4l_device_path}"
	KEYNAME=unknown_input_placeholder
	write_etcd
	KEYNAME=INPUT_DEVICE_PRESENT
	KEYVALUE="1"
	#write_etcd
}

id
whoami
exec >/home/wavelet/v4ldevices.log 2>&1
set -x
sense_devices
detect
