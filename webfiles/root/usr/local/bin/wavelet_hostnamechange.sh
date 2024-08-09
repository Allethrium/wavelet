#!/bin/bash
# Called by a watcher service which will pull the new device label as set from the web interface and change this device hostname accordingly.

detect_self(){
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*) 					echo -e "I am an Encoder \n" 											;	devType="enc"	;	getNewHostname ${devType}
	;;
	decX.wavelet.local)		echo -e "I am a Decoder, and my hostname needs to be randomized. \n" 	;	exit 0
	;;
	dec*)					echo -e "I am a Decoder\n"												;	devType="dec"	;	getNewHostname ${devType}
	;;
	livestream*)			echo -e "I am a Livestreamer \n"										;	devType="lvstr"	;	getNewHostname ${devType}
	;;
	gateway*)				echo -e "I am a Gateway\n"												;	devType="gtwy"	;	getNewHostname ${devType}
	;;
	svr*)					echo -e "I am a Server.\n"												;	echo -e "The server hostname should not be modified.\nExiting process.\n"	;	exit 0
	;;
	*) 						echo -e "This device Hostname is not set appropriately.\n"				;	exit 0
	;;
	esac
}

getNewHostName(){
	# create an oldhostname file for next reboot
	echo -e $(hostname) > /home/wavelet/oldhostname.txt
	# etcdctl get the hash of the device from the watcher
	HOW?
	#etcdctl get the NEW label of the device
	etcdctl --endpoints=192.168.1.32:2379 get hostHash/label -- printvalue only
	# parse the label and make sure we have a valid one and can generate a proper fqdn from it
		# validation stuff here
	# 
	hostnamectl hostname ${1}${printvalue}.wavelet.local
	# reboot system, build_ug/run_ug will pick everything up from here.
	systemctl reboot
}


###
#
# Main
#
###

echo -e "Called with arguments:\n${1}\n${2}\n${3}\n"
detect_self