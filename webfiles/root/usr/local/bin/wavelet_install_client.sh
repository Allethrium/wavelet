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

install_security_layer(){
	# This function checks for the presence of the security layer flag, and if it exists we run domain enrollment
	if [[ -f /var/prod.security.enabled ]]; then
		echo -e "Security layer is enabled.. enrolling to domain.\n\nThis will fail if a DC is not available on the wavelet network!\n"
		# This password should be prepopulated from the DC as part of the initial imaging process.
		# Umm.. how.  The Server would know a pxe installation request and may have a mac address and IP to play with from dnsmasq.. 
		# that's the only ID info we will get from that part...

		# Perhaps unattended might work this way..
		password=$(cat /var/secrets/domainEnrollment.password)
		user=$(cat /var/secrets/domainEnrollment.userAccount)
		# These files will be empty if security is not provisioned on the server.
		waveletDomain=$(cat /var/secrets/wavelet.domain)
		waveletServer=$(cat /var/secrets/wavelet.server)
		rm -rf /var/secrets/domainEnrollment.password
		rm -rf /var/secrets/domainEnrollment.userAccount
		ipa-client-install --principal "${user}" --password "${password}" --domain ${waveletDomain} --server ${waveletServer} --unattended

		# Reconfigure etcd to utilize certificates
		echo -e "Reconfiguring etcd client..\n"
		# Reconfigure WiFi to utilize EAP-TTLS
		echo -e "Reconfiguring WiFi supplicant..\n"
}




####
#
# Main
#
####




nmcli dev wifi rescan
sleep 5
exec >/home/wavelet/client_installer.log 2>&1
extract_base
extract_home
extract_usrlocalbin
sleep 2
install_security_layer
touch /var/client_install.complete
systemctl disable wavelet_install_client.service
connectwifi