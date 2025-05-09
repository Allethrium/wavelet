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
	KEYNAME="/UI/short_hash/${hashValue}"	read_etcd_global;   target="${printvalue}"
	# Target will be the packed value in HostName;hostnamepretty;devLabel;devPath for local
	# IP;name;ip for network device
	# Get our IP Subnet for checking on network devices
	case ${hashValue} in
		"1")					echo "Static Input, checking for server status..";		detect_self
		;;
		"2")					echo "Static Input, checking for server status..";		detect_self
		;;
		"T")					echo "Static Input, checking for server status..";		detect_self
	esac
	# Not a static input? next steps:
	ipAddrSvr=$(cat /var/home/wavelet/config/etcd_ip)
	A=(${ipAddrSvr//./ })
	ipAddrSubnet=$(echo "${A[0]}.${A[1]}.${A[2]}")
	# trim target of anything after first ; delimiter
	target=${target%%;*}
	case ${target} in
		*${hostNameSys}*)		echo "Target hostname references this host!";			systemctl --user restart run_ug.service
		;;
		*${hostNameSys#*.})		echo "Same domain but not this hostname, exiting.";		exit 0
		;;
		*${ipaddrSubNet}*)  	echo "Network device, checking for server status..";	detect_self
		;;
		*)						echo "This host is not referenced/invalid selection";	exit 0
	esac

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
exec >/var/home/wavelet/logs/encoderquery.log 2>&1
main