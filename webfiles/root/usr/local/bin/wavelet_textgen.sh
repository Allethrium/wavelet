#!/bin/bash

# ImageMagick caption generator script
# we use this to generate our notification banners as necessary


#Etcd Interaction
ETCDENDPOINT=192.168.1.32:2379
read_etcd(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get $(hostname)/${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_global(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for Global value"
}

write_etcd(){
        etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}

write_etcd_global(){
        etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
}


filter_is_livestreaming(){
	KEYNAME=uv_islivestreaming
	read_etcd_global
		if [[ "$printvalue" -eq 1 ]]; then
			lsflag=':  Livestreaming Enabled'
			color="rgba(255, 0, 0, 0.2)"
		else
			lsflag=''
		fi
}


read_uv_filter() {
	# reads the control key for filter and sets appropriate values in this table directly, then adds livestream notification as appropriate
	# Capture filter is set on REFLECTOR or on DECODERS, it is too expensive/finnicky to work properly on Encoders.
		KEYNAME=uv_input
		read_etcd_global
		filterselection=${printvalue}
			case $filterselection in
			BLANK) 					color="rgba(65, 105, 225, 0.2)"
									filter_is_livestreaming
									filter="○ BLANK ${lsflag}"
									generate_image
			;;
			SEAL)					color="rgba(65, 105, 225, 0.2)"
									filter_is_livestreaming
									filter="○ State Seal ${lsflag}"
									generate_image
			;;
			EVIDENCECAM1)				color="rgba(65, 105, 225, 0.2)"
									filter_is_livestreaming
									filter="☺ Evidence Cam ${lsflag}"
									generate_image
			;;
			HDMI1)					color="rgba(65, 105, 225, 0.2)"
									filter_is_livestreaming
									filter="○ HDMI In 1 ${lsflag}"
									generate_image
			;;
			HDMI2)					color="rgba(65, 105, 225, 0.2)"
									filter_is_livestreaming
									filter="○ HDMI In 2 ${lsflag}"
									generate_image
			;;
			HYBRID) 				color="rgba(65, 105, 225, 0.2)"
									filter_is_livestreaming
									filter="○ Hybrid ${lsflag}"
									generate_image
			;;
			WITNESS) 				color="rgba(65, 105, 225, 0.2)"
									filter_is_livestreaming
									filter="○  Witness Camera ${lsflag}"
									generate_image
			;;
			COURTROOM) 				color="rgba(65, 105, 225, 0.2)"
									filter_is_livestreaming
									filter="○  Courtroom ${lsflag}"
									generate_image
			;;
			FOURSPLIT) 	color="rgba(65, 105, 225, 0.2)"
									filter_is_livestreaming
									filter="○  4-panel mixdown ${lsflag}"
									generate_image
			;;
			TWOSPLIT) 	color="rgba(65, 105, 225, 0.2)"
									filter_is_livestreaming
									filter="○  2-panel mixdown ${lsflag}"
									generate_image
			;;
			PIP1) 				color="rgba(65, 105, 225, 0.2)"
									filter_is_livestreaming
									filter="○  Picture-in-Picture 1 ${lsflag}"
									generate_image
			;;
			PIP2) 				color="rgba(65, 105, 225, 0.2)"
									filter_is_livestreaming
									filter="○  Picture-in-Picture 2 ${lsflag}"
									generate_image
			;;
			*) 						echo -e "Input Key is incorrect, quitting"; :
			;;
			esac
	}

generate_image(){
	We MUST generate a BMP - generating a PNG or other format does horrible things when converted to PAM.
	convert -size 600x50 --pointsize 30 -background "${color}" -bordercolor "rgba(25, 65, 185, 0.1)" -border 1 -gravity West -fill white label:"%-  ${filter}" -colorspace sRGB /home/wavelet/banner.bmp
	mogrify -format pam /home/wavelet/banner.bmp
	echo -e "\n banner.pam generated for value ${filter}. \n"
	KEYNAME=uv_filter_cmd
	KEYVALUE="--capture-filter logo:/home/wavelet/banner.pam:25:25"
	write_etcd_global
	exit 0
}

# Main
set -x
exec >/home/wavelet/textgen.log 2>&1
read_uv_filter
