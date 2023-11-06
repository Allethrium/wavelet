#!/bin/bash
# Monitors etcd for input device changes over the prefix and updates as necessary
#

ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379

read_etcd_global() {
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for Global value"
}

read_etcd() {
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get $(hostname)/${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for host $(hostname)"
}

read_etcd_input_prefix() {
		printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get $(hostname)/interface/)
}

write_etcd_global() {
        etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
}

detect_self(){
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*) 					echo -e "I am an Encoder \n" && self="encoder"
	;;
	dec*)					echo -e "I am a Decoder \n" && self="decoder"
	;;
	livestream*)			echo -e "I am a Livestreamer \n" && self="livestream"
	;;
	gateway*)				echo -e "I am an input Gateway for another video streaming system \n"  && self="input_gateway"
	;;
	svr*)					echo -e "I am a Server.  Launching encoder detection \n"  && self="server"
	;;
	*) 						echo -e "This device Hostname is not set approprately, exiting \n" && exit 0
	;;
	esac
}

main() {
# main thread, checks new_device_attached flag in etcd
	KEYNAME=new_device_attached
	read_etcd_global
	if [[ "$printvalue" -eq 1 ]]; then
		detect_self
		if [[ "${self}" = "encoder" ]]; then		
			echo -e "This is an encoder, so it is valid for us to proceed.  Regenerating input list.."
			event_inputdevice_update
		elif [[ "${self}" = "server" ]]; then
			# we check whether an input device has been added via detectv4l.sh to this  server
			KEYNAME=INPUT_DEVICE_PRESENT
			read_etcd
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
		KEYNAME=encoder_restart
		KEYVALUE=0
		write_etcd_global
	fi
}


event_inputdevice_update() {
	# T
}

set -x
exec >/home/wavelet/monitor_encoderflag.log 2>&1
main
