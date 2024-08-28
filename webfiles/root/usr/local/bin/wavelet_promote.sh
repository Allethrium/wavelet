#!/bin/bash 
#
# This script resets the appropriate flag back to 0 and then calls hostname change.

detect_self(){
systemctl --user daemon-reload
UG_HOSTNAME=$(hostname)
				echo -e "Hostname is $UG_HOSTNAME \n"
				case $UG_HOSTNAME in
				enc*)                                   echo -e "I am an Encoder \n"           				;		event_encoder
				;;
				dec*)                                   echo -e "I am a Decoder \n"                 	    ;		event_decoder
				;;
				svr*)                                   echo -e "I am a Server, ending process \n"			;		exit 0
				;;
				*)                                      echo -e "This device is other, ending process\n"	;		exit 0
				;;
				esac
}

#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
ETCDCTL_API=3

read_etcd_global(){
	ETCDCTL_API=3 printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
	echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for Global value"
}

event_decoder(){
	echo -e "\nPromotion from Decoder to Encoder flag change detected, resetting flag and calling host name change module..\n"
	systemctl --user disable UltraGrid.AppImage.service --now
	etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/PROMOTE" -- "0"
	etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/RELABEL" -- "1"
	systemctl --user enable wavelet_promote.service --now
	/usr/local/bin/wavelet_device_relabel.sh "dec"
	exit 0
}

event_encoder(){
	echo -e "\nPromotion from Encoder to Decoder flag change detected, resetting flag and calling host name change module..\n"
	systemctl --user disable UltraGrid.AppImage.service --now
	etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/PROMOTE" -- "0"
	etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/RELABEL" -- "1"
	systemctl --user enable wavelet_promote.service --now
	/usr/local/bin/wavelet_device_relabel.sh "enc"
	exit 0
}

###
#
# Main 
#
###

exec >/home/wavelet/promote.log 2>&1

KEYNAME=/$(hostname)/PROMOTE
read_etcd_global
if [[ "${printvalue}" == 1 ]]; then
	echo -e "\nPROMOTE key is set to 1, continuing with task.. \n"
	detect_self
else
	echo -e "\nPROMOTE key is set to 0, doing nothing.. \n"
	exit 0
fi