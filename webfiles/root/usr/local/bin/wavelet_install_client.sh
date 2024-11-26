#!/bin/bash
# This runs as a systemd unit on the SECOND boot on the Client devices ONLY
# It is responsible for extracting the wavelet modules, joining the domain and provisioning services so that it can talk to etcd and the DC.

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
		password=$(cat /var/secrets/domainEnrollment.password)
		user=$(cat /var/secrets/domainEnrollment.userAccount)
		# These files will be empty if security is not provisioned on the server, they will be populated during PXE boot ignition from the server.
		rm -rf /var/secrets/domainEnrollment.password
		rm -rf /var/secrets/domainEnrollment.userAccount
		# Install FreeIPA Client
		ipa-client-install --principal "${user}" --password "${password}" --unattended # --request-cert seems broken?
		
		# These might not be necessary.
		#ipa service-add etcd-client/$(hostname) && ipa service-add-host --hosts=dc1.$(dnsdomainname) etcd-client/`hostname`
		hostname=$(hostname)
		ipa-getcert request \
		-f /var/home/wavelet/pki/tls/certs/etcd-client.crt \
		-k /var/home/wavelet/pki/tls/private/etcd-client.key \
		-K etcd-client/${hostname}@${hostname^^} \
		-D $(dnsdomainname)


		#ipa service-add radius-client/$(hostname) && ipa service-add-host --hosts=dc1.$(dnsdomainname) radius-client/`hostname`
		#ipa-getcert request \
		#-f /etc/pki/tls/certs/radius-client.crt \
		#-k /etc/pki/tls/private/radius-client.key \
		#-K radius-client/$(hostname) \
		#-D $(dnsdomainname)
		
		# Reconfigure etcd to utilize certificates
		# As long as the machine is enrolled correctly into the etcd and wifi groups on the server, it should be able to authenticate
		# We are going to do this with the machine host certificate
		echo -e "Reconfiguring etcd client..\n"
		# Here

		# Reconfigure WiFi to utilize EAP-TTLS
		echo -e "Reconfiguring WiFi supplicant..\n"

		nmcli con mod ${wifiConnection} \
		802-11-wireless.ssid 'My Wifi' \
		802-11-wireless-security.key-mgmt wpa-eap \
		802-1x.eap tls \
		802-1x.identity identity@example.com \
		802-1x.ca-cert /etc/ipa/ca.crt \
		802-1x.client-cert /etc/nssdb/ \
		802-1x.private-key /etc/nssdb/ \
}



####
#
# Main
#
####


# Fix AVAHI otherwise NDI won't function correctly, amongst other things;  https://www.linuxfromscratch.org/blfs/view/svn/basicnet/avahi.html
# Runs first because it doesn't matter what kind of server/client device, it'll need this.
groupadd -fg 84 avahi && useradd -c "Avahi Daemon Owner" -d /run/avahi-daemon -u 84 -g avahi -s /bin/false avahi
groupadd -fg 86 netdev

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