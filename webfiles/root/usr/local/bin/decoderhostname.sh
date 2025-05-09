#!/bin/bash
# sets a unique (FOR THIS LAN - *NOT* A UUID!) four-char alphanumeric for the hostname

detect_self(){
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	decX.wavelet.local)		echo -e "I am a Decoder, and my hostname needs to be randomized. \n" && event_decoder
	;;
	*) 						echo -e "This device Hostname is not set appropriately, exiting \n" && exit 0
	;;
	esac
}

event_decoder(){
	echo "Setting decoder hostname as well as 'Pretty' label to the same value."
	echo "The Pretty label will be utilized on the webUI and may change."
	echo "The stable hostname is for domain enrollment, and should remain stable after initial configuration."
	newhostname=$(head -c 4 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')
	hostnamectl hostname dec$newhostname.wavelet.local
	hostnamectl --pretty hostname dec$newhostname.wavelet.local
	# remember to reset permissions or we get root logfiles
	chown wavelet:wavelet -R /var/home/wavelet
	echo "All set, rebooting decoder.."
	# Final step in the FIRST boot.
	touch /var/firstboot.complete.target
	sleep 1
	systemctl reboot
}

#set -x
exec >/var/home/wavelet/logs/decoderhostname.log 2>&1
detect_self