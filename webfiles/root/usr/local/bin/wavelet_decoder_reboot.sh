#!/bin/bash
#
# This script resets the appropriate flag back to 0 and then reboots the system.
# Encoders and the entire System reset flag are a different deal
# Decoders don't set the system reboot flag at all, that waits until the Server reboots.


detect_self(){
	# Detect_self in this case relies on the etcd type key
	KEYNAME="/hostLabel/${hostNameSys}/type"; read_etcd_global
	echo -e "Host type is: ${printvalue}\n"
	case "${printvalue}" in
	enc*) 					echo -e "I am an Encoder \n"		;	event_encoder
	;;
	dec*)					echo -e "I am a Decoder \n"			;	event_decoder
	;;
	svr*)					echo -e "I am a Server \n"			;	event_server
	;;
	*) 						echo -e "This device is other \n"	;	event_other
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
	KEYNAME="/${hostNameSys}/DECODER_REBOOT"; read_etcd_global; rebootflag=${printvalue}
	if [[ "${rebootflag}" -eq 1 ]]; then
		echo -e "\nSystem Reboot flag reset to 0\n\n\n\n***SYSTEM IS GOING DOWN FOR REBOOT IMMEDIATELY***\n\n\n"
		# we wait 12 seconds so that the server has time to get out ahead and come back up before the decoders start doing anything.
		wait 12
		systemctl reboot -i
	else
		echo -e "\ninput_update key is set to 0, doing nothing.. \n"
		exit 0
	fi
}
event_encoder(){
	KEYNAME="/${hostNameSys}/ENCODER_RESTART"; KEYVALUE=0; write_etcd_global
	echo -e "\nEncoder Reboot flag reset to 0\n\n\n\n***SYSTEM IS GOING DOWN FOR REBOOT IMMEDIATELY***\n\n\n"
	# we wait 12 seconds so that the server has time to get out ahead and come back up before the decoders start doing anything.
	wait 12
	systemctl reboot -i
}
event_server(){
	echo -e "\nSystem Reboot flag is set, waiting 5 Seconds for other machines to reboot or set appropriate flags..\n"
	# Remember, the server houses the keypair store, so it must be available for the system to operate when everything has rebooted!
	wait 5
	KEYNAME="SYSTEM_RESTART"; KEYVALUE=0; write_etcd_global
	echo -e "\nSystem Reboot flag reset to 0\n\n\n\n***SYSTEM IS GOING DOWN FOR REBOOT IMMEDIATELY***\n\n\n"
	systemctl reboot -i
}
event_other(){
	KEYNAME="/${hostNameSys}/DECODER_RESTART"; KEYVALUE=0; write_etcd_global
	systemctl reboot -i
}

###
#
# Main 
#
###

hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
detect_self
