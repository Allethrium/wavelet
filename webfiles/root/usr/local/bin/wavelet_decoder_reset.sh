#!/bin/bash
#
# This script resets the appropriate flag back to 0 and then resets the AppImage service.
# Should fix some errors and cheaper than a reboot.
detect_self(){
systemctl --user daemon-reload
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*) 					echo -e "I am an Encoder \n"		;	exit 0
	;;
	dec*)					echo -e "I am a Decoder \n"			;	event_decoder
	;;
	svr*)					echo -e "I am a Server \n"			;	exit 0
	;;
	*) 						echo -e "This device is other \n"	;	event_decoder
	;;
	esac
}



#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
ETCDCTL_API=3

event_decoder(){
# Kill the systemd task for a few moments
systemctl --user stop wavelet-decoder-restart.service
echo -e "\nDecoder Reset flag change detected, resetting flag and restarting the UltraGrid service..\n\n\n"
# we wait 15 seconds so that the server has time to get out ahead and come back up before the decoders start doing anything.
etcdctl --endpoints=${ETCDENDPOINT} put "decoderip/$(hostname)/DECODER_RESET" -- "0"
systemctl --user enable wavelet-decoder-restart.service --now
systemctl --user restart UltraGrid.AppImage.service
echo -e "\nTask Complete.\n"
exit 0
}

###
#
# Main 
#
###
#
detect_self
