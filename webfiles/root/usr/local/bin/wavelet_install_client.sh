#!/bin/bash
# This runs as a systemd unit on the SECOND boot on the Client devices ONLY
# It extracts the wavelet modules from the tarball to the appropriate places, and that's about it.

extract_base(){
	tar xf /home/wavelet/wavelet-files.tar.xz -C /home/wavelet --no-same-owner
	mv /home/wavelet/usrlocalbin.tar.xz /usr/local/bin/
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

####
#
# Main
#
####

exec >/home/wavelet/client_installer.log 2>&1
extract_base
extract_home
extract_usrlocalbin
sleep 2
systemctl reboot