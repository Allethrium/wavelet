#!/bin/bash
# Monitors etcd for input device changes over the prefix and updates as necessary
#

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
delete_etcd_key(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key" "${KEYNAME}"
}

detect_self(){
	# We only care if this host is provisioned as an encoder or a server here.
	UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*)				echo -e "I am an Encoder \n"; 										self="encoder"
	;;
	svr*)				echo -e "I am a Server.  Launching encoder detection \n";			self="server"
	;;
	*) 					echo -e "This device is not an encoder or a server. Exiting \n";	exit 0
	;;
	esac
}

main() {
# main thread, checks new_device_attached flag in etcd
	# New device available is a GLOBAL flag that notifies the entire system.
	KEYNAME=new_device_attached; read_etcd_global
	if [[ "$printvalue" -eq 1 ]]; then
		detect_self
		if [[ "${self}" = "encoder" ]]; then		
			echo -e "This is an encoder, so it is valid for us to proceed.  Regenerating input list.."
			event_inputdevice_update
		elif [[ "${self}" = "server" ]]; then
			# we check whether an input device has been added via detectv4l.sh to this host
			KEYNAME=INPUT_DEVICE_PRESENT; read_etcd
				if [[ "$printvalue" -eq 1 ]]; then
					echo -e "An input device is present on this server, and it is running as an encoder, regenerating input list.."
					event_inputdevice_update
				else
					echo "I am not running an encoder, doing nothing"
					:
			fi
		else 
			echo -e "It seems the hostname is not correctly set, ending task.."
			:
		fi
		echo -e "Resetting encoder restart flag to 0.."
		KEYNAME=encoder_restart; KEYVALUE=0; write_etcd_global
	fi
}


event_inputdevice_update() {
	# Run detectV4l.sh to properly register new device with the system
	/usr/local/bin/wavelet_detectv4l.sh
}

#set -x
exec >/home/wavelet/monitor_encoderflag.log 2>&1
main