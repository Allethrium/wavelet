#!/bin/bash
#
# /usr/local/bin/removedevice.sh
# This script queries etcd for a device and tries to see if it matches what was just removed.
# If this is true, we remove the key from etcd for this hostname and run a further check to see if video devices remain.
# If no video devices remain, we set the input flag to 0.


#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
read_etcd(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get $(hostname)/${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for host $(hostname)"
}

read_etcd_global(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for Global value"
}

write_etcd(){
        etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}

write_etcd_global(){
        etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
}

write_etcd_clientip(){
        etcdctl --endpoints=${ETCDENDPOINT} put decoderip/$(hostname) "${KEYVALUE}"
        echo -e "$(hostname) set to ${KEYVALUE} for Global value"
}
read_etcd_clients_ip() {
        return_etcd_clients_ip=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix decoderip/ --print-value-only)
}
delete_etcd(){
		printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} del $(hostname)/${KEYNAME})
        echo -e "Key Name {$KEYNAME} deleted from etcd for host $(hostname)"	
}


detect_etcd(){
	KEYNAME=v4lDocumentCam
	read_etcd
	echo -e "${printvalue} has been returned in etcd query \n"
	workingpath=$(echo $printvalue | awk -F 'device=' 'NF>1{ sub(/^ */,"",$NF); sub(/ .*/,"",$NF); print $NF }')
	echo -e "\n extracted ${workingpath} from detectv4l.sh set command line..\n"
	if [ ! -d ${workingpath} ]; then
		echo -e "${workingpath} does not exist, device has been physically removed.\n Removing the entry from etcd, and checking for other video devices.";
		KEYNAME=v4lDocumentCam;
		delete_etcd;
	else
		echo -e "${printvalue} exists in /dev/v4l directory, a different device has been plugged in/removed which triggered this event.\n  Terminating."; exit 0
	fi
}


detect(){
	# The detection loop in this script runs against the array generated in sense_device
	# not against a single line item, as in the case with detectv4l.sh
	# To further simplify and make it easier to manage between here and detectv4l.sh, it might be good idea to generate
	# a supported devices table in etcd.   This way entries can be added and removed on the controller.
	shopt -s nullglob
	declare -A input
	FOLDERS=(/dev/v4l/by-id/*)
	for folder in "${FOLDERS[@]}"; do
        	[[ -d "$folder" ]] && echo "$folder"
	done
	shopt -u nullglob
	echo -e "\n testing values..\n"
	IFS=@
        	case "@${FOLDERS[*]}@" in
                	(*"IPEVO"*)							echo -e "IPEVO Document Camera device detected, ending detection \n"; exit 0
                	;;
                	(*"Logitech_Screen_Share"*)			echo -e "Logitech HDMI-USB Capture device detected, ending detection \n"; exit 0
                	;;
                	(*"Magewell"*)						echo -e "Magewell USB Capture HDMI device detected, ending detection \n"; exit 0
                	;;
                	(*)									echo -e "No supported video devices have been detected.  Setting input device presence to disabled. \n"; 
                										inputpresence=0; 
                										KEYNAME=INPUT_DEVICE_PRESENT;
                										KEYVALUE=1;
														write_etcd;
														echo -e "etcd entries cleaned up for this device and input flag set to 0."
        	esac
}

# Main call
set -x
exec >/home/wavelet/removedevice.log 2>&1
detect_etcd