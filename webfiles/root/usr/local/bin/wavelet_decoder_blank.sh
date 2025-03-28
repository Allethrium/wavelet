#!/bin/bash
# This script resets the appropriate flag back to 0 and then resets the AppImage service.
# Should fix some errors and cheaper than a reboot.


detect_self(){
	# Detect_self in this case relies on the etcd type key
	KEYNAME="/UI/hosts/${hostNameSys}/type"; read_etcd_global
	echo -e "Host type is: ${printvalue}\n"
	case "${printvalue}" in
		enc*)                                   echo -e "I am an Encoder \n"            ;       exit 0
		;;
		dec*)                                   echo -e "I am a Decoder \n"             ;       event_decoder
		;;
		svr*)                                   echo -e "I am a Server \n"              ;       exit 0
		;;
		*)                                      echo -e "This device is other \n"       ;       event_decoder
		;;
	esac
}



# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
read_etcd(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd" ${KEYNAME})
	echo -e "Key Name: {$KEYNAME} read from etcd for value: $printvalue for host: ${hostNameSys}\n"
}
read_etcd_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}") 
	echo -e "Key Name: {$KEYNAME} read from etcd for Global Value: $printvalue\n"
}
read_etcd_prefix(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_prefix" "${KEYNAME}")
	echo -e "Key Name: {$KEYNAME} read from etcd for value $printvalue for host: ${hostNameSys}\n"
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
	echo -e "Key Name: ${KEYNAME} set to ${KEYVALUE} under /${hostNameSys}/\n"
}
write_etcd_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name: ${KEYNAME} set to: ${KEYVALUE} for Global value\n"
}
write_etcd_client_ip(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_client_ip" "${KEYNAME}" "${KEYVALUE}"
}
delete_etcd_key(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key" "${KEYNAME}"
}
delete_etcd_key_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key_global" "${KEYNAME}"
}
delete_etcd_key_prefix(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key_prefix" "${KEYNAME}"
}
generate_service(){
	# Can be called with more args with "generate_servier" ${keyToWatch} 0 0 "${serviceName}"
	/usr/local/bin/wavelet_etcd_interaction.sh "generate_service" "${serviceName}"
}
event_decoder_blank(){
        echo -e "\nDecoder Blank flag change detected, switching host to blank input...\n\n\n"
        # this should be a blank image
        if [[ ! -f /var/home/wavelet/config/blankscreen.png ]]; then
        	echo "Blank display isn't available, generating.."
			color="rgb(.2, .2, .2, 0)"
			backgroundcolor="rgb(.2, .2, .2, 0)"
        	magick -size 1920x1080 -pointsize 50 -background "${color}" -bordercolor "${backgroundcolor}" \
        	-gravity Center -fill white label:'This screen is intentionally blank.' \
        	-colorspace RGB /var/home/wavelet/config/blank.bmp
        fi
        swayimg /var/home/wavelet/config/blank.bmp -f --config=info.show=no &
}
event_decoder_unblank(){
        pid=$(ps ax | grep swayimg | awk '{print $1}' | head -n 1)
        kill -15 $pid
        sleep 1
        kill -6 $pid
        exit 0
}


###
#
# Main 
#
###

#set -x
exec >/var/home/wavelet/logs/wavelet_blank_decoder.log 2>&1

hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)

KEYNAME="/UI/hosts/${hostNameSys}/control/BLANK_PREV"; read_etcd_global; oldKeyValue=${printvalue}
KEYNAME="/UI/hosts/${hostNameSys}/control/BLANK"; read_etcd_global; newKeyValue=${printvalue}
	if [[ ${newKeyValue} == ${oldKeyValue} ]]; then
		echo -e "\n Blank setting and previous blank setting match, the webpage has been refreshed, doing nothing..\n"
		:
	else
		if [[ "${newKeyValue}" == 1 ]]; then
				echo -e "\ninput_update key is set to 1, setting blank display for this host, and writing prevKey \n"
				KEYNAME="/UI/hosts/${hostNameSys}/control/BLANK_PREV"; KEYVALUE="1";	write_etcd_global
				event_decoder_blank
				# use a switcher, have the decoders all running a blank in the background?
		else
				echo -e "\ninput_update key is set to 0, reverting to previous display, and writing prevKey.. \n"
				KEYNAME="/UI/hosts/${hostNameSys}/control/BLANK_PREV"; KEYVALUE="0"; write_etcd_global
				event_decoder_unblank
		fi
	fi