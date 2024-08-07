#!/bin/bash

# ImageMagick caption generator script
# we use this to generate our notification banners as necessary


#Etcd Interaction
ETCDENDPOINT=192.168.1.32:2379
read_etcd(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get /$(hostname)/${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_global(){
        printvalue="$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)"
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for Global value"
}

write_etcd(){
        etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}

write_etcd_global(){
        etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
}

banner_onoff(){
# Runs first to determine if the banner/watermark flag is enabled
	KEYNAME=/banner/enabled
	read_etcd_global
		if [[ "$printvalue" -eq 1 ]]; then
			echo -e "Banner is enabled, proceeding.."
			read_uv_filter
		else
			# Generate an image with 100% transparency
			echo -e "Banner is disabled on webUI, setting full alpha."
			filter=""
			color="rgba(255, 255, 255, 0.0)"
			backgroundcolor="rgba(255, 255, 255, 0.0)"
			generate_image
		fi	
}

filter_is_livestreaming(){
	KEYNAME=uv_islivestreaming
	read_etcd_global
		if [[ "$printvalue" -eq 1 ]]; then
			lsflag=':  Livestreaming Enabled'
			color="rgba(255, 0, 0, 0.2)"
			backgroundcolor="rgba(255, 0, 0, 0.3)"
		else
			lsflag=''
		fi
}


read_uv_filter() {
	# 11/2023  uv_input is now a textlabel set by the user from the webUI.  This is because the alternatives with the new dynamic system were nonsense like
	# deviceStringLong or deviceStringShort which all look like "IPEVO_Inc._IPEVO_Ziggi-HD_Plus" - which won't be presentable.
	# Capture filter is set on REFLECTOR or on DECODERS, it is too expensive/finnicky to work properly on Encoders.
		KEYNAME=uv_input
		read_etcd_global
		filterselection="${printvalue}"
		color="rgba(65, 105, 225, 0.2)"
		backgroundcolor="rgba(45, 85, 205, 0.3)"
		filter_is_livestreaming
		filter="○ ${filterselection} ${lsflag}"
		generate_image
	}

generate_image(){
	# We MUST generate a BMP - generating a PNG or other format does horrible things when converted to PAM.
	# working colorspace sRGB
	convert -size 600x50 --pointsize 30 -background "${color}" -bordercolor "${backgroundcolor}" -border 1 -gravity West -fill white label:"%-  ${filter}" -colorspace sRGB /home/wavelet/banner.bmp
	mogrify -format pam /home/wavelet/banner.bmp
	echo -e "\n banner.pam generated for value ${filter}. \n"
	KEYNAME=uv_filter_cmd
	KEYVALUE="--capture-filter logo:/home/wavelet/banner.pam:25:25"
	write_etcd_global
	exit 0
}

###
#
# Main
#
###

rm -rf /home/wavelet/banner.bmp, /home/wavelet/banner.pam
set -x
exec >/home/wavelet/textgen.log 2>&1
banner_onoff
