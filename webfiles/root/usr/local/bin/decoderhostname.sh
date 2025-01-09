#!/bin/bash
# sets a unique (FOR THIS LAN - *NOT* A UUID!) four-char alphanumeric for the hostname

detect_self(){
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	decX.wavelet.local)		echo -e "I am a Decoder, and my hostname needs to be randomized. \n" && event_decoder
	;;
	dec*)					echo -e "I am a Decoder, but my hostname is already randomized and set \n"; exit 0
	;;
	svr*)					echo -e "I am a Server."  && echo -e "I don't need hostname randomization, ending process.. "; exit 0
	;;
	*) 						echo -e "This device Hostname is not set appropriately, exiting \n" && exit 0
	;;
	esac
}

event_decoder(){
	echo "Setting decoder hostname as well as 'Pretty' label"
	newhostname=$(LC_ALL=C tr -dc A-Z-0-9 </dev/urandom | head -c 4)
	hostnamectl hostname dec$newhostname.wavelet.local
	hostnamectl --pretty hostname dec$newhostname.wavelet.local
	# remember to reset permissions or we get root logfiles
	chown wavelet:wavelet -R /var/home/wavelet
	echo "All set, rebooting decoder.."
	systemctl reboot
}

#set -x
exec >/home/wavelet/decoderhostname.log 2>&1
detect_self