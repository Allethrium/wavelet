#!/bin/bash
# Monitors etcd for output and restarts the encoder as necessary
#

ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
KEYNAME=encoder_restart

read_etcd_global(){
		printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
		echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for Global value"
}

write_etcd(){
		etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
		echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}

read_etcd(){
		printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get /$(hostname)/${KEYNAME} --print-value-only)
		echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for host $(hostname)"
}

write_etcd_global(){
		etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
		echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
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
	KEYNAME="encoder_restart"
	read_etcd
	if [[ "${printvalue}" -eq 1 ]]; then
		echo -e "Encoder restart bit is set! continuing..\n"
		detect_self
		if [[ "${self}" = "encoder" ]]; then		
			systemctl --user restart run_ug.service
			echo -e "Encoder restart flag is enabled, restarting encoder.."
		elif [[ "${self}" = "server" ]]; then
			# we check whether an input device has been added via detectv4l.sh to this  server
			KEYNAME=INPUT_DEVICE_PRESENT
			read_etcd
				if [[ "$printvalue" -eq 1 ]]; then
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
		KEYNAME=encoder_restart
		KEYVALUE=0
		write_etcd
	fi
}

set -x
exec >/home/wavelet/monitor_encoderflag.log 2>&1
main
