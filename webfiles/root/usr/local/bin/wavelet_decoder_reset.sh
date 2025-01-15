#!/bin/bash 
#
# This script resets the appropriate flag back to 0 and then restarts the AppImage service.  
# Useful for fixing POC errors introduced by changing the codec on the encoders.


detect_self(){
	# Detect_self in this case relies on the etcd type key
	KEYNAME="/hostLabel/${hostNameSys}/type"; read_etcd_global
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

event_decoder(){
echo -e "\nDecoder Reset flag change detected, resetting flag and restarting the UltraGrid service..\n\n\n"
systemctl --user restart UltraGrid.AppImage.service
KEYNAME="/$(hostname)/DECODER_RESET"
KEYVALUE="0"
write_etcd
#etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/DECODER_RESET" -- "0"
systemctl --user restart wavelet_monitor_decoder_reset.service --now
echo -e "\nTask Complete.\n"
exit 0
}

###
#
# Main 
#
###

#set -x
exec >/home/wavelet/wavelet_restart_decoder.log 2>&1


hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)

KEYNAME="/${hostNameSys}/DECODER_RESET"
read_etcd_global
if [[ "${printvalue}" == 1 ]]; then
	echo -e "\nReset key is set to 1, continuing with task.. \n"
	detect_self
else
	echo -e "\nReset key is set to 0, doing nothing.. \n"
	exit 0
fi