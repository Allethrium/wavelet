#!/bin/bash
# This module ensures a running encoder displays an appropriate screensaver to tell us what it is doing.

read_etcd_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}") 
	echo -e "Key Name: {$KEYNAME} read from etcd for Global Value: $printvalue\n"
}
write_etcd_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name: ${KEYNAME} set to: ${KEYVALUE} for Global value\n"
}


detect_self(){
	# Detect_self in this case relies on the etcd type key
	KEYNAME="/UI/hosts/${hostNameSys}/type"; read_etcd_global
	echo -e "Host type is: ${printvalue}\n"
	case "${printvalue}" in
		enc*)                                   echo -e "I am an Encoder \n"            ;       event_encoder_blank
		;;
		dec*)                                   echo -e "I am a Decoder \n"             ;       exit 0
		;;
		svr*)                                   echo -e "I am a Server \n"              ;       exit 0
		;;
		*)                                      echo -e "This device is other \n"       ;       exit 0
		;;
	esac
}

event_encoder_blank(){
	echo -e "\nDecoder Blank flag change detected, switching host to blank input...\n\n\n"
	# this should be a blank image
	if [[ ! -f /var/home/wavelet/config/enc_blank.bmp ]]; then
		echo "Blank display isn't available, generating.."
			color="rgb(.2, .2, .2, 0)"
			backgroundcolor="rgb(.2, .2, .2, 0)"
		magick -size 1920x1080 -pointsize 50 -background "${color}" -bordercolor "${backgroundcolor}" \
		-gravity Center -fill white label:'TRANSMITTING AS ENCODER.\nThis screen is intentionally blank.' \
		-colorspace RGB /var/home/wavelet/config/enc_blank.bmp
	fi
	pactl set-sink-mute $(pactl get-default-sink) 1
	export XDG_RUNTIME_DIR=/run/user/$(id -u)
	WAYLAND_DISPLAY=wayland-1
	SWAYSOCK=/run/user/${UID=$(id -u)}/sway-ipc.$UID.$(pgrep -x sway).sock
	swaymsg -s $SWAYSOCK exec "swayimg /var/home/wavelet/config/enc_blank.bmp -f --config=info.show=no" & sleep 5
	# Generate activity on hosts update so that UI will function as intended.
	KEYNAME="/UI/hosts/${hostNameSys}/UPDATEUI"; KEYVALUE="1"; write_etcd_global
}


###
#
# Main 
#
###

#set -x
exec >/var/home/wavelet/logs/wavelet_encoder_blank.log 2>&1

hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)

detect_self