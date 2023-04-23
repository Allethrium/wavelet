#!/bin/bash
#
#
#What does this file do?
#Upon the connection of a new USB device, this script is called by Udev rules.
#It will attempt to list the most recently installed v4l device
#and then it will attempt to symlink it to a static device based off a keyword match.
#There are problems with this approach - the Logitech screen capture devices, for instance, are indistinguishable.

# Example ls of
# /dev/v4l/by-id
#lrwxrwxrwx. 1 root root 12 Apr 19 14:25 usb-Alpha_Imaging_Tech._Corp._Logitech_Screen_Share-video-index0 -> ../../video4
#lrwxrwxrwx. 1 root root 12 Apr 19 14:25 usb-Alpha_Imaging_Tech._Corp._Logitech_Screen_Share-video-index1 -> ../../video5
#lrwxrwxrwx. 1 root root 12 Apr 19 14:26 usb-IPEVO_Corp._IPEVO_VZ-R-video-index0 -> ../../video6
#lrwxrwxrwx. 1 root root 12 Apr 19 14:26 usb-IPEVO_Corp._IPEVO_VZ-R-video-index1 -> ../../video7
#lrwxrwxrwx. 1 root root 12 Apr 18 16:16 usb-IPEVO_Inc._IPEVO_Ziggi-HD_Plus-video-index0 -> ../../video0
#lrwxrwxrwx. 1 root root 12 Apr 18 16:16 usb-IPEVO_Inc._IPEVO_Ziggi-HD_Plus-video-index1 -> ../../video1

# After bring triggered, this runs first.  It will list available devices in /dev/v4l/by-id, and select the newest, lowest-numbered
# device.   This is USUALLY the correct device for video output.

#monitor() {
#	inotifywait -m --exclude "[^j].$|[^s]$" /dev/v4l/by-id/ -e create -e moved_to |
#		while read directory action; do
#				echo "Change detected in '$dir' via '$action'"
#				sense_device
#				detect
#			done
#}

sense_device() {
	sleep 1
	device_string_long=$(ls -Artl /dev/v4l/by-id | tail -n 2 | awk '{print $9,$11}')
	echo 'Last device plugged in is:'
	echo '$device_string' 
	# select lowest value (usually correct device)
	# store device path in a variable 
	v4l_device_path=$(ls -Artl /dev/v4l/by-id | tail -n 2 | awk '{print $11}' | sort -nk 2 | head -1 | awk -F/ '{print $3}')
}

# Here we detect valid devices, and need to maintain a database of usable devices and their appropriate types
detect() {
	echo "Device string is $device_string_long"
	case $device_string_long in
	*IPEVO*) 			echo "IPEVO Document Camera Device detected" && event_ipevo
	;;
	*Logitech_Screen_Share*)	echo "Logitech HDMI-USB Capture Device detected" && event_lghdmi
	;;
	*) 				echo "This device is not documented or not a video USB device" && exit 0
	;;
	esac
	
}

event_ipevo() {
	DEVPATH=/dev/v4l_document_camera_0
		if test -f "$DEVPATH"; then
			echo "$DEVPATH already exists, linking $v4l_device_path to /dev/v4l_document_camera_1" 
			ln -sf /dev/"$v4l_device_path" /dev/v4l_document_camera_1
			DEVPATH=/dev/v4l_document_camera_1
			else
				echo "New device, Document camera linked to /dev/v4l_document_camera_0"
				ln -sf /dev/"$v4l_device_path" /dev/v4l_document_camera_0
		fi
}

event_elmo() {
        DEVPATH=/dev/v4l_document_camera_0
                if test -f "$DEVPATH"; then
                        echo "$DEVPATH already exists, linking $v4l_device_path to /dev/v4l_document_camera_1"
                        ln -sf /dev/"$v4l_device_path" /dev/v4l_document_camera_1
			DEVPATH=/dev/v4l_document_camera_1
                else
                        echo "New device, Document camera linked to /dev/v4l_document_camera_0"
                        ln -sf /dev/"$v4l_device_path" /dev/v4l_document_camera_0
		fi
}

event_lghdmi() {
        DEVPATH=/dev/v4l_lghdmi_0
                if test -f "$DEVPATH"; then
                        echo "$DEVPATH already exists, linking $v4l_device_path to /dev/v4l_lghdmi_1"
                        ln -sf /dev/"$v4l_device_path" /dev/v4l_lghdmi_1
			DEVPATH=/dev/v4l_lghdmi_1
	                else
        	                echo "New device, HDMI Capture linked to /dev/v4l_lghdmi_0" 
	                        ln -sf /dev/"$v4l_device_path" /dev/v4l_lghdmi_0
		fi
}

event_wth() {
        DEVPATH=/dev/v4l_wth_0
                if test -f "$DEVPATH"; then
                        echo "$DEVPATH already exists, linking $v4l_device_path to /dev/v4l_wth_1" 
                        ln -s /dev/"$v4l_device_path" /dev/v4l_wth_1
			DEVPATH=/dev/v4l_wth_1
	                else
        	                echo "New device, Document camera linked to /dev/v4l_wth_0" 
	                        ln -s /dev/"$v4l_device_path" /dev/v4l_wth_0
		fi
}
id
whoami
exec >/home/wavelet/v4ldevices.log 2>&1
set -x
sense_device
detect
