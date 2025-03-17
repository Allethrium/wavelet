#!/bin/bash
# Monitors etcd for the ENCODER_QUERY master key
# Checks the input label for the device hostname
# If hostname is on this machine, we restart run_ug.service, calling the encoder process to validate and verify further
# The encoder process should not be called by anything other than this module, or wavelet_init

# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
read_etcd_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}") 
	echo -e "Key Name {$KEYNAME} read from etcd for Global Value $printvalue\n"
}
write_etcd_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name ${KEYNAME} set to ${KEYVALUE} for Global value\n"
}

main() {
	# Checks to see if this host is referenced
	KEYNAME="ENCODER_QUERY";				read_etcd_global;	hashValue=${printvalue}
	KEYNAME="/UI/short_hash/${hashValue}"	read_etcd_global;   targetHost="${printvalue%/*}"
	# Determine what kind of device we are dealing with
	if [[ ${targetHost} == *"network_interface"* ]]; then
		echo -e "Target Hostname is a network device."
		detect_self
	elif [[ "${targetHost}" == *"${hostNamePretty}"* ]]; then
		echo -e "Target hostname references this host!"
		systemctl --user restart run_ug.service
	else 
		echo -e "Device is hosted on another host, checking to see if I'm the server.."
		detect_self
		exit 0
	fi
}

detect_self(){
	HOSTNAME=$(hostname)
	case $HOSTNAME in
	svr*)					echo -e "I am a Server. Restarting run_ug.service."						;	systemctl --user restart run_ug.service
	;;
	*) 						echo -e "This isn't a server, stopping encoder task."					;	systemctl --user disable UltraGrid.AppImage.service --now; exit 0
	;;
	esac
}

hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
#set -x
exec >/var/home/wavelet/logs/watch_encoderflag.log 2>&1
main