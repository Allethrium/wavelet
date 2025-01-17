#!/bin/bash
# This runs as a systemd unit on the first boot on the Client devices ONLY.
# It is responsible for extracting the wavelet modules, 
# joining the domain (if security enabled) and provisioning services so that it can talk to etcd and the DC.

extract_base(){
	# Moves tar files to their target directories
	cd /var/home/wavelet/setup
	tar xf /home/wavelet/setup/wavelet-files.tar.xz -C /home/wavelet/setup --no-same-owner
	mv ./usrlocalbin.tar.xz /usr/local/bin/; mv ./etc.tar.xz /etc; mv ./wavelethome.tar.xz ../
}
extract_etc(){
	umask 022
	tar xf /etc/etc.tar.xz -C /etc --no-same-owner --no-same-permissions
	echo -e "System config files setup successfully..\n"
	rm -rf /etc/etc.tar.xz
}
extract_home(){
	tar xf /var/home/wavelet/wavelethome.tar.xz -C /var/home/wavelet
	echo -e "Wavelet homedir setup successfully..\n"
	rm -rf /var/home/wavelet/wavelethome.tar.xz
}
extract_usrlocalbin(){
	umask 022
	tar xf /usr/local/bin/usrlocalbin.tar.xz -C /usr/local/bin --no-same-owner
	chmod +x /usr/local/bin
	chmod -R 0755 /usr/local/bin/
	echo -e "Wavelet application modules setup successfully..\n"
	rm -rf /usr/local/bin/usrlocalbin.tar.xz
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
mkdir -p /var/home/wavelet/setup

# Run connectwifi
/usr/local/bin/connectwifi.sh

#set -x
exec > /var/home/wavelet/logs/client_installer.log 2>&1

# Fix AVAHI otherwise NDI won't function correctly, amongst other things;  https://www.linuxfromscratch.org/blfs/view/svn/basicnet/avahi.html
# Runs first because it doesn't matter what kind of server/client device, it'll need this.
groupadd -fg 84 avahi && useradd -c "Avahi Daemon Owner" -d /run/avahi-daemon -u 84 -g avahi -s /bin/false avahi
groupadd -fg 86 netdev
systemctl enable avai-daemon.service --now
extract_base
extract_home
extract_usrlocalbin
extract_etc
install_security_layer
chown -R wavelet:wavelet /var/home/wavelet
# Disable self so we don't run again on the next boot.
systemctl set-default graphical.target
touch /var/client_install.complete
# Generate sway service for allusers
echo "[Unit]
Description=sway - SirCmpwn's Wayland window manager
Documentation=man:sway(5)
BindsTo=default.target
Wants=default.target
After=default.target

[Install]
WantedBy=default.target

[Service]
Type=simple
EnvironmentFile=-%h/.config/sway/env
ExecStart=/usr/bin/sway
Restart=on-failure
RestartSec=1
TimeoutStopSec=10" > /etc/systemd/user/sway.service
systemctl --user -M wavelet@ daemon-reload
systemctl --user -M wavelet@ enable sway.service --now