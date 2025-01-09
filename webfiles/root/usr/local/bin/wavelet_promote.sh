
#!/bin/bash 
#
# This script resets the appropriate flag back to 0 and then calls hostname change.

detect_self(){
	systemctl --user daemon-reload
	echo -e "Hostname is ${hostNamePretty} \n"
	case ${hostNamePretty} in
		enc*)                                   echo -e "I am an Encoder \n"           				;		event_encoder
		;;
		dec*)                                   echo -e "I am a Decoder \n"                 	    ;		event_decoder
		;;
		svr*)                                   echo -e "I am a Server, ending process \n"			;		exit 0
		;;
		*)                                      echo -e "This device is other, ending process\n"	;		exit 0
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
	echo -e "\nPromotion from Decoder to Encoder flag change detected, resetting flag and calling host name change module..\n"
	systemctl --user disable UltraGrid.AppImage.service --now
	KEYNAME="PROMOTE"; KEYVALUE=0; write_etcd
	KEYNAME="RELABEL"; KEYVALUE=1; write_etcd
	systemctl --user enable wavelet_promote.service --now
	/usr/local/bin/wavelet_device_relabel.sh "dec"
	exit 0
}

event_encoder(){
	echo -e "\nPromotion from Encoder to Decoder flag change detected, resetting flag and calling host name change module..\n"
	systemctl --user disable UltraGrid.AppImage.service --now
	KEYNAME="/${hostNameSys}/PROMOTE"; KEYVALUE=0; write_etcd_global
	KEYNAME="/${hostNameSys}/RELABEL"; KEYVALUE=1; write_etcd_global
	systemctl --user enable wavelet_promote.service --now
	/usr/local/bin/wavelet_device_relabel.sh "enc"
	exit 0
}

###
#
# Main 
#
###

#set -x
exec >/var/home/wavelet/logs/promote.log 2>&1
hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)

KEYNAME="/$(hostname)/PROMOTE"; read_etcd_global
if [[ "${printvalue}" == 1 ]]; then
	echo -e "\nPROMOTE key is set to 1, continuing with task.. \n"
	detect_self
else
	echo -e "\nPROMOTE key is set to 0, doing nothing.. \n"
	exit 0
fi