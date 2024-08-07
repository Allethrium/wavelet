#!/bin/bash 
#
# This script resets the appropriate flag back to 0 and then restarts the AppImage service.  Useful for fixing POC errors introduced by changing the codec on the encoders.
detect_self(){
systemctl --user daemon-reload
UG_HOSTNAME=$(hostname)
				echo -e "Hostname is $UG_HOSTNAME \n"
				case $UG_HOSTNAME in
				enc*)                                   echo -e "I am an Encoder \n"            ;       exit 0
				;;
				dec*)                                   echo -e "I am a Decoder \n"                     ;       event_decoder
				;;
				svr*)                                   echo -e "I am a Server \n"                      ;       exit 0
				;;
				*)                                              echo -e "This device is other \n"       ;       event_decoder
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
echo -e "\nDecoder Reset flag change detected, resetting flag and restarting the UltraGrid service..\n\n\n"
systemctl --user restart UltraGrid.AppImage.service
etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/DECODER_RESET" -- "0"
systemctl --user restart wavelet_monitor_decoder_reset.service --now
echo -e "\nTask Complete.\n"
exit 0
}

###
#
# Main 
#
###

set -x
exec >/home/wavelet/wavelet_restart_decoder.log 2>&1

KEYNAME=/$(hostname)/DECODER_RESET
								read_etcd_global
								if [[ "${printvalue}" == 1 ]]; then
																echo -e "\nReset key is set to 1, continuing with task.. \n"
																detect_self
								else
																echo -e "\nReset key is set to 0, doing nothing.. \n"
																exit 0
								fi
