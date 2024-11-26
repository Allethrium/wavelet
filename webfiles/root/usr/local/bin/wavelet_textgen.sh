#!/bin/bash

# ImageMagick caption generator script
# we use this to generate our notification banners as necessary

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

banner_onoff(){
# Runs first to determine if the banner/watermark flag is enabled
	KEYNAME=/banner/enabled; read_etcd_global
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
	KEYNAME=uv_islivestreaming; read_etcd_global
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
		KEYNAME=uv_input; read_etcd_global
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
	KEYNAME=uv_filter_cmd; KEYVALUE="--capture-filter logo:/home/wavelet/banner.pam:25:25"; write_etcd_global
	exit 0
}

###
#
# Main
#
###

rm -rf /home/wavelet/banner.bmp, /home/wavelet/banner.pam
#set -x
exec >/home/wavelet/textgen.log 2>&1
banner_onoff
