#!/bin/bash
# This module ensures a running encoder displays an appropriate screensaver to tell us what it is doing.

read_etcd_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}") 
	echo -e "Key Name: {$KEYNAME} read from etcd for Global Value: $printvalue\n"
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
        # Add a volume > 0 option here so that we stop any audio output from the device when it's blanked.
        # This will be necessary to blank off a team call or overflow if audio were being processed.
        swayimg /var/home/wavelet/config/enc_blank.bmp -f --config=info.show=no &
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