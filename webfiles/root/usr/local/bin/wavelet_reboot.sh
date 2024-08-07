#!/bin/bash
#
# This script resets the appropriate flag back to 0 and then reboots the system.
# Encoders and the entire System reset flag are a different deal
# Decoders don't set the system reboot flag at all, that waits until the Server reboots.
detect_self(){
systemctl --user daemon-reload
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*) 					echo -e "I am an Encoder \n"		;	event_encoder
	;;
	dec*)					echo -e "I am a Decoder \n"			;	event_decoder
	;;
	svr*)					echo -e "I am a Server \n"			;	event_server
	;;
	*) 						echo -e "This device is other \n"	;	event_other
	;;
	esac
}



#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
ETCDCTL_API=3

event_decoder(){
rebootflag=$(etcdctl --endpoints=192.168.1.32:2379 get /$(hostname)/DECODER_REBOOT --print-value-only)
if [[ "${rebootflag}" == 1 ]]; then
		echo -e "\nSystem Reboot flag reset to 0\n\n\n\n***SYSTEM IS GOING DOWN FOR REBOOT IMMEDIATELY***\n\n\n"
		# we wait 10 seconds so that the server has time to get out ahead and come back up before the decoders start doing anything.
		wait 10
		systemctl reboot -i
	else
		echo -e "\ninput_update key is set to 0, doing nothing.. \n"
		exit 0
	fi
}

event_encoder(){
etcdctl --endpoints=${ETCDENDPOINT} put "ENCODER_RESTART" -- "0"
echo -e "\nEncoder Reboot flag reset to 0\n\n\n\n***SYSTEM IS GOING DOWN FOR REBOOT IMMEDIATELY***\n\n\n"
# we wait 10 seconds so that the server has time to get out ahead and come back up before the decoders start doing anything.
wait 10
systemctl reboot -i
}

event_server(){
echo -e "\nSystem Reboot flag is set, waiting 5 Seconds for other machines to reboot or set appropriate flags..\n"
# Remember, the server houses the keypair store, so it must be available for the system to operate when everything has rebooted!
wait 5
etcdctl --endpoints=${ETCDENDPOINT} put "SYSTEM_RESTART" -- "0"
echo -e "\nSystem Reboot flag reset to 0\n\n\n\n***SYSTEM IS GOING DOWN FOR REBOOT IMMEDIATELY***\n\n\n"
systemctl reboot -i
}

event_other(){
etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/DECODER_RESTART" -- "0"
systemctl reboot -i
}

###
#
# Main 
#
###

detect_self
