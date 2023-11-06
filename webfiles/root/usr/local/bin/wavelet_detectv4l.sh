#!/bin/bash
#
# Upon the connection of a new USB device, this script is called by Udev rules.  
# Note Udev calls a bootstrap script which THEN calls this script,
# because the usb subsystem is locked until the rule execution is completed!
# It will attempt to make sense of available v4l devices and update etcd
# It will then call another set of services to update the WebUI.

#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=http://192.168.1.32:2379
read_etcd(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get $(hostname)/${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for host $(hostname)"
}

read_etcd_global(){
        printvalueglobal=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for Global value"
}

write_etcd(){
        etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}

write_etcd_inputs(){
        etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/inputs/${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname) /inputs/"
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


sense_devices_ug() {
# Another alternate method that calls and parses UltraGrid's input to generate a list of available devices.
# MIGHT work better with multiple devices from the same vendor
	sleep .25
	# ls latest in v4l/dev/by-id, tail last two, awk for /dev/video path and SED for even numbered lines only.
	device_string_latest=$(ls -Artl /dev/v4l/by-id | tail -n 2 | awk '{print $9,$11}' | sed -n 'n;p')
	echo -e "Last device plugged in is: ${device_string_latest}" 
	# select lowest value (usually correct device)
	# store device path in a variable 
	latest_v4l_device_path=$(ls -Artl /dev/v4l/by-id | tail -n 2 | awk '{print $11}' | sort -nk 2 | head -1 | awk -F/ '{print $3}')
	echo $latest_v4l_device_path
	string=$(/usr/local/bin/UltraGrid.AppImage --tool uv -t v4l2:help | grep /dev/video)
	string=$(echo ${string} | sed 's|(usb*):||g')
	readarray -td '' array< <(awk '{ gsub(/Device /,"\0"); print; }' <<<"$string, "); unset 'array[0]';
	        for i in "${array[@]}"
	        do
				v4l_device_path=$(echo $i | awk '/dev/video {match($0, /video/); print substr($0, RSTART - 5, RLENGTH + 6);}')
				v4lshort=$(echo $v4l_device_path | sed 's|/dev/||g')
				echo -e "\n v4l Device path ${v4l_device_path} located for: \n $i \n"
				device_string_long=${i}
				if [[ "${latest_v4l_device_path}" == "${v4lshort}" ]]; then
					echo -e "The latest attached device matches the listed device path from v4l2, running device detection. \n"
					# Run detection on the matched new device
					detect
				else
					echo -e "The latest attached device does not match this device path from v4l2, doing nothing."
					# Device is already setup, therefore we end here
					:	
				fi
	        done
}

detect() {
# we still need this fairly simple approach, as the Logitech screen share USB devices have no serial number, making multiple inputs hard to handle.
# is called in a foreach loop from detect_ug devices, therefore it is already instanced for each device
	echo -e "\n Device string is ${device_string_long} \n"
	case $device_string_long in
	# This will always be a document camera
	*IPEVO*)					echo -e "IPEVO Document Camera device detected \n"		&& event_ipevo
	;;
	# This will always be "Logitech HDMI input" incrementing in number, because we do not know how it will be used
	*"Logitech Screen Share"*)	echo -e "Logitech HDMI-USB Capture device detected \n"	&& event_logitech_hdmi
	;;
	# Everything else we will trust the new process, and try to set caps + dynamic update the UI
	*)							echo -e "Wavelet will try to set reasonable device caps and utilize this device.\n"	&& event_unknowndevice
	;;
	esac
}

event_ipevo() {
# each of these blocks contains specific configuration options that must be preset for each device
# IPEVO document cameras have no identifiable serial number fields either, so it's pointless attempting do anything except randomly increment additions.
	KEYVALUE="-t v4l2:codec=MJPG:size=1920x1080:tpf=1/30:convert=RGB:device=${v4l_device_path}"
	KEYNAME=${device_string_long}
	write_etcd_inputs
	KEYNAME=INPUT_DEVICE_PRESENT
	KEYVALUE=1
	write_etcd
	# In this case we do something silly, which is just hash the entire output.  The hash will basically change
	# every second due to the USEC_INITIALIZED fields and also the pci/usb hub/port configuration.
	# So we are dependent on the remove script to clean up, and a "new" input device would be generated each time it's plugged in.
	devicehash=$(udevadm info ${v4l_device_path} | sha256sum)
	echo -e "IPEVO document cameras have no identifiable data, hash will be random.  Storing hash.\n"
	# This data is acted upon by the interface watcher service, which will update the webui every time something changes for anything inside of the /interface/* prefix
	KEYNAME="/interface${device_string_long}"
	KEYVALUE="${device_hash}"
	write_etcd_global
	echo -e "\n Device hash ${devicehash} created for ${device_string_long}\n"
}

event_logitech_hdmi() {
	KEYNAME=${device_string_long}
	KEYVALUE="-t v4l2:codec=YUYV:size=1920x1080:tpf=1/30:convert=RGB:device=${v4l_device_path}"
	write_etcd_inputs
	KEYNAME=INPUT_DEVICE_PRESENT
	KEYVALUE="1"
	write_etcd
	# We will implement another etcd watcher service that will update the webui every time something changes
	# The Logitech Screen share cards are problematic, because they don't have serials or UID's available
	# This Means we will just be getting random devices and the user will have to make sense of them, 
	# and they won't be persistent across disconnects/reconnects
	# Trying to generate a hash on them is pointless beyond tying a /dev/videoX to a UI button, as excluding ephemeral data like USB port/bus and time,
	# it would always be the same.
	KEYNAME="/interface${device_string_long}"
	KEYVALUE="enabled"
	write_etcd
	devicehash=$(udevadm info ${v4l_device_path} | sha256sum)
	echo -e "Logitech HDMI capture cards have no identifiable data, hash will be random.  Storing hash.\n"
	KEYNAME="/interface${device_string_long}"
	KEYVALUE="${device_hash}"
	write_etcd_global
}

event_unknowndevice() {
	# 10/27/2023 - new idea - just use the actual device string as the key and find some way to update it directly in the webUI?
	# We generate a device hash (or try to) so that the device will be assigned the same input tasks next time it's plugged in.
	device_hash=$(udevadm info ${v4l_device_path} | grep ID_SERIAL_SHORT | sha256sum)
	KEYNAME="/interface${device_string_long}"
	read_etcd_global
	if [[ "${device_hash}" == "${printvalue}" ]]; then
		echo -e "The connected device already has a unique hash previously generated. \n It will be assigned to the same UI button as before. \n"
		:
	else
		echo -e "The connected device has not been previously assigned an input ID for the UI component.  Storing hash.\n"
	        # This data is acted upon by the interface watcher service 
	        # This will update the webui every time something changes for anything inside of the /interface/* prefix
	        KEYNAME="/interface${device_string_long}"
        	KEYVALUE="${device_hash}"
	        write_etcd_global
	fi
	KEYNAME=${device_string_long}
	KEYVALUE="-t v4l2:codec=YUYV:size=1920x1080:tpf=1/30:convert=RGB:device=${v4l_device_path}"
	write_etcd_inputs
	KEYNAME=INPUT_DEVICE_PRESENT
	KEYVALUE="1"
	write_etcd
	# notify watcher configuration has changed
	KEYNAME=new_device_attached
	KEYVALUE=1
	write_etcd_global
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

event_magewellhdmi() {
# The Magewell supports 1080p @ 60FPS, so we will set that here
# This is now depreciated, as the Magewells are handled fine by the generic ? script due to their serial#s. 
# Leaving this here for example.
	KEYNAME=hdmi_magewell
	read_etcd
	if [ -n "${printvalue}" ]; then
    	echo "there is already a MageWell HDMI capture device attached, incrementing inputs"
    	KEYVALUE="-t v4l2:codec=YUYV:size=1920x1080:tpf=1/60:convert=RGB:device=${v4l_device_path}"
		KEYNAME=hdmi_magewell_1
		write_etcd_inputs
		# We do not need to write INPUT_DEVICE_PRESENT, as this should already be tagged
	else
    	echo "This etcd key is empty, therefore no MageWell HDMI device is present and we can continue normally.."
		KEYVALUE="-t v4l2:codec=YUYV:size=1920x1080:tpf=1/60:convert=RGB:device=${v4l_device_path}"
		KEYNAME=hdmi_magewell
		write_etcd_inputs
		KEYNAME=INPUT_DEVICE_PRESENT
		KEYVALUE="1"
		write_etcd
	fi
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
	write_etcd_inputs
	KEYNAME=INPUT_DEVICE_PRESENT
	KEYVALUE="1"
	write_etcd	
}

exec >/home/wavelet/detectv4l.log 2>&1
set -x
sense_devices_ug