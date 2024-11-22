#!/bin/bash
# Called by a watcher service which will pull the new device label as set from the web interface and change this device hostname accordingly.


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


detect_self(){
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*) 					echo -e "I am an Encoder \n" 											;	devType="enc"	;	getNewHostname ${devType}
	;;
	decX.wavelet.local)		echo -e "I am a Decoder, and my hostname needs to be randomized. \n" 	;	exit 0
	;;
	dec*)					echo -e "I am a Decoder\n"												;	devType="dec"	;	getNewHostname ${devType}
	;;
	livestream*)			echo -e "I am a Livestreamer \n"										;	devType="lvstr"	;	getNewHostname ${devType}
	;;
	gateway*)				echo -e "I am a Gateway\n"												;	devType="gtwy"	;	getNewHostname ${devType}
	;;
	svr*)					echo -e "I am a Server.\n"												;	echo -e "The server hostname should not be modified.\nExiting process.\n"	;	exit 0
	;;
	*) 						echo -e "This device Hostname is not set appropriately.\n"				;	exit 0
	;;
	esac
}

getNewHostName(){
	prefix="dec"
	# create an oldhostname file for next reboot
	echo -e $(hostname) > /home/wavelet/oldhostname.txt
	# get the hash of the device from the watcher via etcd
	# HOW?

	#  get the NEW label of the device
	KEYNAME="/hostHash/label"; read_etcd_global
	# parse the label and make sure we have a valid one and can generate a proper fqdn from it
		# validation stuff here


	# Check the promotion bit for this host
	KEYNAME="PROMOTE"; read_etcd
	if [[ "${printvalue}" -eq "1" ]]; then
		echo -e "Promotion bit is set to one, the decoder has been instructed to become an encoder..\n"
		KEYVALUE=0; write_etcd
		encHostname=$(echo $(hostname) | sed 's/dec/enc/g' input.txt)
		KEYNAME="IS_PROMOTED"; KEYVALUE=1; write_etcd
		hostnamectl hostname "${encHostname}.wavelet.local"
	fi
	echo -e "Promotion bit is not set to 1, proceeding with hostname change.."
	# Set the hostname
	hostnamectl hostname "${prefix}${newHostnameValue}.wavelet.local"
	# reboot system, build_ug/run_ug will pick everything up from here.
	systemctl reboot
}


###
#
# Main
#
###

echo -e "Called with arguments:\n${1}\n${2}\n${3}\n"
detect_self