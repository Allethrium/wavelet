#!/bin/bash
# Called by a watcher service which will pull the new device label as set from the web interface 
# It will change this device's PRETTY hostname accordingly.  The device ACTUAL hostname remains the same.


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
detect_self(){
	echo -e "Hostname is ${hostNamePretty} \n"
	case $UG_HOSTNAME in
	enc*) 					echo -e "I am an Encoder \n" 											;	devType="enc"	;	getNewHostname ${devType}
	;;
	decX.wavelet.local)		echo -e "I am a Decoder, and my hostname needs to be randomized. \n" 	;	exit 0
	;;
	dec*)					echo -e "I am a Decoder\n"												;	devType="dec"	;	getNewHostname ${devType}
	;;
	svr*)					echo -e "I am a Server.\n"												;	echo -e "The server hostname should not be modified.\nExiting process.\n"	;	exit 0
	;;
	*) 						echo -e "This device Hostname is not set appropriately.\n"				;	exit 0
	;;
	esac
}

getNewHostName(){
	# record my old label
	echo -e "${hostNamePretty}" > /home/wavelet/old_host_label.txt
	KEYNAME="/hostHash/label"; read_etcd_global
	# Check the promotion bit for this host
	KEYNAME="/${hostNameSys}/PROMOTE"; read_etcd_global
	if [[ "${printvalue}" -eq "1" ]]; then
		echo -e "Promotion bit is set to one, the decoder has been instructed to become an encoder..\n"
		KEYVALUE=0; write_etcd_global
		encHostName=$(echo ${hostNamePretty} | sed 's/dec/enc/g' input.txt)
		KEYNAME="/${hostNameSys}/IS_PROMOTED"; KEYVALUE=1; write_etcd_global
		hostnamectl --pretty hostname "${encHostName}.$(dnsdomainname)"
	fi
	echo -e "Promotion bit is not set to 1, proceeding with hostname change instead.."
	# Set the hostname
	hostnamectl --pretty hostname "${prefix}${newHostnameValue}.wavelet.local"
	# let's skip the reboot and re-register with build_ug
	/usr/local/bin/build_ug.sh "--R"
}



#####
#
# Main
#
#####


logName="/var/home/wavelet/logs/hostnamechange.log"
if [[ -e $logName || -L $logName ]] ; then
	i=0
	while [[ -e $logName-$i || -L $logName-$i ]] ; do
		let i++
	done
	logName=$logName-$i
fi
#set -x
exec >${logName} 2>&1


echo -e "Called with arguments:\n${1}\n${2}\n${3}\n"
hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
detect_self