#!/bin/bash
# This runs as a systemd unit on the SECOND boot on the Client devices ONLY
# It is responsible for extracting the wavelet modules, joining the domain (if security enabled) and provisioning services so that it can talk to etcd and the DC.

extract_base(){
	tar xf /home/wavelet/wavelet-files.tar.xz -C /home/wavelet --no-same-owner
	mv /home/wavelet/usrlocalbin.tar.xz /usr/local/bin/
}

extract_home(){
	tar xf /home/wavelet/wavelethome.tar.xz -C /home/wavelet
	chown -R wavelet:wavelet /home/wavelet
	chmod 0755 /home/wavelet/http
	#chmod -R 0755 /home/wavelet/http-php
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

		# WiFi configuration is handled via connectwifi module
	else
		echo -e "security layer is not enabled, not configuring"
	fi
}



####
#
# Main
#
####

mkdir -p /var/home/wavelet/logs

#set -x
exec > /var/home/wavelet/logs/client_installer.log 2>&1

# Fix AVAHI otherwise NDI won't function correctly, amongst other things;  https://www.linuxfromscratch.org/blfs/view/svn/basicnet/avahi.html
# Runs first because it doesn't matter what kind of server/client device, it'll need this.
groupadd -fg 84 avahi && useradd -c "Avahi Daemon Owner" -d /run/avahi-daemon -u 84 -g avahi -s /bin/false avahi
groupadd -fg 86 netdev
systemctl enable avai-daemon.service --now
nmcli dev wifi rescan
extract_base
extract_home
extract_usrlocalbin
install_security_layer
# Move the log file otherwise permissions is an issue and we don't get subsequent log
# Also reset permissions on wavelet home folder so that any other files generated whilst running under root are writable by the wavelet user
mv /var/home/wavelet/connectwifi.log /var/home/wavelet/logs/setup_old_connectwifi.log
chown -R wavelet:wavelet /var/home/wavelet
# Disable self so we don't run again on the next boot.
systemctl disable wavelet_install_client.service
touch /var/client_install.complete
echo -e "Starting decoder hostname randomizer, this is the final step in the second boot, and will reboot the client machine.."
systemctl start decoderhostname.service