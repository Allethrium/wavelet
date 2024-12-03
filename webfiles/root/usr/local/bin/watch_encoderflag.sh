#!/bin/bash
# Monitors etcd for output and restarts the encoder as necessary
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
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*) 					echo -e "I am an Encoder \n" 													&& self="encoder"
	;;
	dec*)					echo -e "I am a Decoder \n"														&& self="decoder"
	;;
	livestream*)			echo -e "I am a Livestreamer \n"												&& self="livestream"
	;;
	gateway*)				echo -e "I am an input Gateway for another video streaming system \n" 			&& self="input_gateway"
	;;
	svr*)					echo -e "I am a Server.  Launching encoder detection \n" 						&& self="server"
	;;
	*) 						echo -e "This device Hostname is not set approprately, exiting \n"				&& exit 0
	;;
	esac
}

main() {
# main thread, checks encoder restart flag in etcd
	KEYNAME="encoder_restart"; read_etcd
	if [[ "${printvalue}" -eq 1 ]]; then
		echo -e "Encoder restart bit is set! continuing..\n"
		detect_self
		if [[ "${self}" = "encoder" ]]; then		
			systemctl --user stop UltraGrid.AppImage.service
			systemctl --user restart run_ug.service
			echo -e "Encoder restart flag is enabled, restarting encoder process on this host.."
		elif [[ "${self}" = "server" ]]; then
			# we check whether an input device has been added via detectv4l.sh to this  server
			KEYNAME=INPUT_DEVICE_PRESENT; read_etcd
				if [[ "$printvalue" -eq 1 ]]; then
					systemctl --user disable UltraGrid.AppImage.service --now
					systemctl --user restart run_ug.service
					echo -e "An input device is present on this server, and it is running as an encoder, restarting encoder component.."
				else
					echo "I am not running an encoder, doing nothing"
					:
			fi
		else 
			echo -e "It seems the hostname is not correctly set, ending task.."
			:
		fi
		echo -e "Resetting encoder restart flag to 0.."
		KEYNAME=encoder_restart; KEYVALUE=0; write_etcd
	fi
}

#set -x
exec >/home/wavelet/watch_encoderflag.log 2>&1
main
