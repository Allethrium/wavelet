#!/bin/bash
# Updates wavelet modules automatically from central source

detect_self(){
systemctl --user daemon-reload
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*) 					echo -e "I am an Encoder \n" && echo -e "Provisioning systemD units as an encoder.."			;	event_encoder
	;;
	decX.wavelet.local)		echo -e "I am a Decoder, but my hostname is generic.  Randomizing my hostname, and rebooting"	;	event_decoder 
	;;
	dec*)					echo -e "I am a Decoder \n" && echo -e "Provisioning systemD units as a decoder.."				;	event_decoder
	;;
	svr*)					echo -e "I am a Server. Proceeding..."  														;	event_server
	;;
	*) 						echo -e "This device Hostname is not set approprately, exiting \n" && exit 0
	;;
	esac
}

event_encoder(){
	extract_base
	extract_home && extract_usrlocalbin
	exit 0
}

event_decoder(){
	extract_base
	extract_home && extract_usrlocalbin
	exit 0
}

event_server(){
	mkdir -p /home/wavelet/.config/containers/systemd/
	chown -R wavelet:wavelet /home/wavelet
	extract_base
	extract_home && extract_usrlocalbin
}

extract_base(){
	tar xf /home/wavelet/wavelet-files.tar.xz -C /home/wavelet --no-same-owner
	cd /home/wavelet
	mv ./usrlocalbin.tar.xz /usr/local/bin/
}

extract_etc(){
	umask 022
	tar xf /etc/etc.tar.xz -C /etc --no-same-owner --no-same-permissions
	echo -e "System config files setup successfully..\n"
}

extract_home(){
	tar xf /home/wavelet/wavelethome.tar.xz -C /home/wavelet
	chown -R wavelet:wavelet /home/wavelet
	chmod 0755 /home/wavelet/http
	chmod -R 0755 /home/wavelet/http-php
	echo -e "Wavelet homedir setup successfully..\n"
}

extract_usrlocalbin(){
	umask 022
	tar xf /usr/local/bin/usrlocalbin.tar.xz -C /usr/local/bin --no-same-owner
	chmod +x /usr/local/bin
	chmod 0755 /usr/local/bin/*
	echo -e "Wavelet application modules setup successfully..\n"
}


# Perhaps add a checksum to make sure nothing's been tampered with here..
wget https://192.168.1.32:8080/ignition/wavelet-files.tar.xz
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
systemctl disable zincati.service --now
set -x
exec >/home/wavelet/wavelet_installer.log 2>&1
detect_self