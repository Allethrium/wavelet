#!/bin/bash
#	This module is concerned with implementing a freeIPA IdM and associated DHCP services



# Add our attempt at a password security solution here
source "/usr/local/bin/wavelet_secure_credentials.sh"
# Source our conf file
source "/etc/wavelet.conf"

# 	Wavelet's security model is simple;
#	*	Central FreeIPA IdM to handle machine accounts, service principals and certificates
#	*	WiFI is secured via RADIUS with EAP-TLS, requiring client certificate
#	*	Provisioning these is handled by wavelet-root, meaning the wavelet user cannot access the secrets
# * Etcd cluster access controlled by etcd roles (independent of domain)

detect_self(){
	echo -e "Hostname is $hostNameSys\n" >> "$logName"
	if [[ $hostNameSys != *"svr"* ]]; then
		echo "	ERR: This may only run on the server." >> "$logName"
		exit 1
	else
		event_server
	fi
}

event_server(){
	# This now runs all the time regardless of security layer flagging.
	echo -e "\n	The domain controller has not yet been configured, proceeding to spin up the container..\n" >> "$logName"
	configure_idm
	# We need to configure SELinux policy permanent -P to allow containers to read the cert bundle package
	setsebool -P container_read_certs 1
	if grep -q "^SERVER_DOMAIN_ENROLLMENT_COMPLETE=1" /etc/wavelet.conf; then
		echo "	Domain enrollment is complete, proceeding to configure certificates and service principals.." >> "$logName"
		sleep 1
		# Create a watcher service to keep certs up to date
		cat > "/etc/systemd/system/cert_publish.service" <<-EOF
			[Unit]
			Description=Certificate Inotify Filter
			After=network.target

			[Service]
			ExecStart=/usr/local/bin/certificate_filter.sh
			RestartSec=10s
			Type=simple
			StandardOutput=inherit
			StandardError=inherit

			[Install]
			WantedBy=default.target
		EOF
		mkdir -p "/var/home/wavelet-root/config/raddb/certs"
		chown wavelet-root "/var/home/wavelet-root/config/raddb/certs"
		systemctl daemon-reload && systemctl enable cert_publish.service --now
		# NTP Server
		configure_ntp
		# Ensure we have a valid kerberos ticket - note these are still files with root ownership 0600.
		administratorPassword="$(cat /var/secrets/ipaadmpw.secure)"
		kinit admin <<<"$administratorPassword"
		# We are going to generate all of our service certificates here
		configure_httpd_sp
		# Registry and etcd go first
		configure_registry_sp
		configure_etcd_certs
		# Now all our later services
		configure_radius_sp
		configure_enrollment
		# Finally we generate our 802.1x EAP-TLS profiles
		configure_freeipa_8021x
    	# Configure DHCP (ISC-Kea) with our earlier subnet declarations
    	configure_dhcp
    	ipa_dns_tsig
		# We must ensure the wavelet-root user has an autologin service, otherwise the container never starts.
		cat > "/etc/systemd/system/wavelet-root-autologin.service" <<-EOF
			[Unit]
			Description=Auto-login for wavelet-root
			After=network.target

			[Service]
			Type=oneshot
			ExecStart=/bin/bash -c 'loginctl enable-linger wavelet-root'
			RemainAfterExit=yes

			[Install]
			WantedBy=multi-user.target
		EOF
		if systemctl daemon-reload && configure_firewall && systemctl enable wavelet-root-autologin.service && systemctl restart etcd-quadlet.service registry.service; then
			echo -e "\n	Security infrastructure successfully configured!" >> "$logName"
			# We may want to now shred the administrator secret as it should no longer be necessary.
		else
			echo -e "	Failed to configure security infrastructure!" >> "$logName"
			exit 1
		fi
	else
		echo -e "	Domain controller is not responding to kerberos ticket requests!" >> "$logName"
		exit 1
	fi
}

reconfigure_dns(){
	# Modify system connection to utilize the DC going forwards
	# systemd-resolved is garbage, so we are resorting to resolv.conf
	rm -rf "/run/NetworkManager/system-connections/default_connection.nmconnection"
	systemctl disable systemd-resolved.service --now
	echo -e "[main]
dns=none" > "/etc/NetworkManager/conf.d/dns.conf"
	echo -e "$IPAServerHostIP dc1.$DOMAIN dc1" >> "/etc/hosts"
	echo -e "$IPAServerHostIP dc1.$DOMAIN dc1" > /var/home/wavelet/http/ignition/dc1_host_entry
	echo -e "DC1_IP=$IPAServerHostIP\nDC1_HOSTNAME=dc1.$DOMAIN" >> "/etc/wavelet.conf"
	chown wavelet:wavelet /var/home/wavelet/http/ignition/dc1_host_entry
	nmcli connection reload
	sleep 5
	# Our interface will have a new UUID, so we need to set that here
	ethernetInterfaceUUID="$(nmcli -t -f UUID,type con show --active | grep ethernet | cut -d: -f1)"
	nmcli con mod "$ethernetInterfaceUUID" ipv4.ignore-auto-dns yes ipv4.dns "$IPAServerHostIP"
	nmcli connection up "$ethernetInterfaceUUID"
	sleep 3
	systemctl restart NetworkManager
	sleep 3
	rm -rf "/etc/resolv.conf"
	# Note this is an append operation!
	cat >> "/etc/resolv.conf" <<-EOF
		nameserver $IPAServerHostIP
		nameserver $gateway
		nameserver 9.9.9.9
		search $DOMAIN
		options timeout:2 attempts:3
	EOF
	echo "  	DNS Reconfigured.." >> "$logName"
}

configure_dhcp(){
	# Configure ISC-Kea for DHCP with zone updates to freeIPA server
	# Utilizes vars calculated during server macvlan setup
  	file="/etc/kea/kea-dhcp-ddns.conf"
  	sed -i "s|wavelet.allethrium|$DOMAIN|g" "$file"
  	sed -i "s|dc1|${IPAServerHostIP}|g" "$file"
	file="/etc/kea/kea-dhcp4.conf"
	sed -i "s|eno1|${active_networkInterface}|g" "$file"
	sed -i "s|wavelet.allethrium|$DOMAIN|g" "$file"
	sed -i "s|192.168.1.0/24|${currentSubnet}|g" "$file"
	sed -i "s|192.168.1.32-192.168.1.32|$subnetDHCPRangeStart - $subnetDHCPRangeEnd|g" "$file"
	sed -i "s|192.168.1.1|${gateway}|g" "$file"
	sed -i "s|dc1|${IPAServerHostIP}|g" "$file"
	sed -i "s|pxeserver|$SVR_IP|g" "$file"
	generate_kea_quadlet
	generate_tftpd
	systemctl daemon-reload
	mkdir -p /var/log/kea
	chown -R kea:root /var/log/kea; chmod 0755 /var/log/kea
	systemctl start kea.service tftpd.service --now
}

generate_kea_quadlet(){
	# isc-kea expects writable dirs which rpm-ostree doesn't supply, so it must be containerized.
	# it should probably run rootful to retain access to certain system resources as necessary
	# Kea should be already built and pulled to the local registry regardless of deployment mode
	availableImages="$(podman images)"
	if [[ "$availableImages" != *"/isc-kea"* ]]; then
	  echo "    Image not available, building.."
    build_container "isc-kea" "/var/home/wavelet/containerfiles/Containerfile.isc-kea"
	fi
	# We need to make a kea user on the system to sync with the containerfile's UID
	useradd -u 964 kea -U
	# Generate quadlet
	echo "	Generating ISC-Kea Quadlet.."
	# Note, the podman quadlet generator complains about the WantedBy line even though it appears a valid config option.
	cat > /etc/containers/systemd/kea.container <<-EOF
		[Unit]
		Description=Kea DHCPv4 Server Quadlet
		Wants=network-online.target
		After=network-online.target
		After=time-sync.target

		[Container]
		ContainerName=kea
		Image=%H/isc-kea:latest
		AutoUpdate=local
		AddCapability=NET_RAW
		AddCapability=NET_BIND_SERVICE
		Network=host
		Volume=/etc/kea:/etc/kea:z
		Volume=/etc/ipa/ca.crt:/etc/ipa/ca.crt
		Volume=/var/log/kea:/var/log/kea:z
		Volume=/usr/local/bin/wavelet_network_sense.sh:/usr/share/kea/scripts/wavelet_network_sense.sh
		Volume=/var/lib/tftpboot:/var/lib/tftpboot:z
		Environment=KEA_PIDFILE_DIR=/var/run/kea
		Environment=KEA_LOCKFILE_DIR=/var/run/kea
		Environment=KEA_DHCP_DATA_DIR=/var/lib/kea
		Environment=KEA_LOG_FILE_DIR=/var/log/kea
		Environment=KEA_CONTROL_SOCKET_DIR=/run/kea
		Environment=ETCDHOSTNAME=%H

		[Service]
		Restart=always
		TimeoutStopSec=5

		[Install]
		WantedBy=multi-user.target
	EOF
}

generate_tftpd(){
	# ISC-Kea does not integrate a TFTP server so we must run our own now.
	availableImages="$(podman images)"
	if [[ "$availableImages" != *"/tftpd"* ]]; then
	  echo "    Image not available, building.."
    build_container "tftpd" "/var/home/wavelet/containerfiles/Containerfile.tftpd"
	fi
	mkdir -p "/var/log/tftp"
echo "[Unit]
Description=TFTP Server Quadlet
Wants=network-online.target
After=network-online.target

[Container]
ContainerName=tftpd
Image=%H/tftpd:latest
AutoUpdate=local
AddCapability=NET_RAW
AddCapability=NET_BIND_SERVICE
Network=host
Volume=/var/log/tftp:/log/:z
Volume=/var/lib/tftpboot:/data:z

[Service]
Restart=always

[Install]
WantedBy=multi-user.target" > "/etc/containers/systemd/tftpd.container"
}

nmcli_create_macvlan(){
	# ipvlan seemed more appropriate, but has networkmanager issues
	# we are going to leave this here encase there's a compelling reason to revisit
	podman network create -d macvlan -o parent=enp1s0f0np0 ipa_macvlan
	nmcli con add type macvlan dev "$active_networkInterface" mode bridge tap yes ifname ipa con-name ipa ip4 0.0.0.0/24
	nmcli con mod macvlan-ipa ipv6.method "disabled"
	nmcli con mod macvlan-ipa ipv4.method "disabled"
	nmcli con mod macvlan-ipa +ipv4.routes "$hostLinkIP/32"
	nmcli con up macvlan-ipa
}

iplink_create_ipvlan(){
	# Can't use nmcli - no ipvlan support until patch lands in fedora repo:
	# https://gitlab.freedesktop.org/NetworkManager/NetworkManager/-/commit/d238ff487b29a50ca346f906b2a158c692ff8864
	# We recreate this link on boot with a systemd unit.
	ip link add ipa_ipvlan_shim link "$active_networkInterface" type ipvlan mode l2
	ip addr add "$hostLinkIP"/32 dev ipa_ipvlan_shim
	ip link set ipa_ipvlan_shim up
	ip route add "$ipaSubnetArg" dev ipa_ipvlan_shim
	if ping -c 4 "$IPAServerHostIP"; then
		echo -e "	Container up and ping is successful, generating rootful unit for ip link shim on every reboot..\n" \
			>> "$logName"
		# Verify variables are set, exit if not
		if [[ -z "$active_networkInterface" || -z "$hostLinkIP" || -z "$ipaSubnetArg" ]]; then
			echo "		ERROR: Required network variables not set! Cannot create ipvlan." >> "$logName"
			return 1
		fi
		echo "		Generating ipvlan shim systemd unit.."
		cat > /usr/local/bin/ipa_link_up.sh <<-EOF
			#!/bin/bash
			ip link add ipa_ipvlan_shim link "${active_networkInterface}" type ipvlan mode l2
			ip addr add "${hostLinkIP}/32" dev ipa_ipvlan_shim
			ip link set ipa_ipvlan_shim up
			ip route add "${ipaSubnetArg}" dev ipa_ipvlan_shim
		EOF
		chmod +x /usr/local/bin/ipa_link_up.sh

		cat > /etc/systemd/system/wavelet_ipvlan_shim.service <<-EOF
			[Unit]
			Description=Run IP Routing to ipvlan container on boot
			After=network-online.target
			Wants=freeipa.service

			[Service]
			Type=oneshot
			ExecStart=/usr/bin/bash -c "/usr/local/bin/ipa_link_up.sh"

			[Install]
		WantedBy=multi-user.target
		EOF
		systemctl daemon-reload && systemctl enable wavelet_ipvlan_shim.service
	else
		echo "	Container is unpingable, there may be an error." >> "$logName"
		# Do remedial stuff here
	fi
}

configure_idm(){
	# Generate necessary data from the server's existing DNS configuration
	local administratorPassword; local ipaHostName
	gateway=$(read _ _ gateway _ < <(ip route list match 0/0); echo "$gateway")
	# Discover ethernet interface data
	active_networkInterface=$(ip route get 8.8.8.8 | sed -nr 's/.*dev ([^\ ]+).*/\1/p')
	ethernetInterfaceUUID="$(nmcli -t -f UUID,type con show --active | grep ethernet | cut -d: -f1)"
	# note - password must be at least 8 chars long and should be prepopulated via install_wavelet_server.sh
	administratorPassword="$(cat /var/secrets/ipaadmpw.secure)"
	if [[ "${administratorPassword}" == "DomainAdminPasswordGoesHere" ]]; then
		echo "The domain administrator password doesn't appear to be set." >> "$logName"
		echo "We will continue with a default password, but this default password is effectively public knowledge!" >> "$logName"
	fi
	# Check for DM password
	if [[ -z "$directoryManagerPassword" ]]; then
		echo "The domain Directory Manager password doesn't appear to be set" >> "$logName"
		cat "/var/secrets/ipaadmpw.secure" > "/var/secrets/ipadmpw.secure"
		local directoryManagerPassword="$administratorPassword"
	fi
	echo -e "Generated variables:\n	Hostname: ${hostNameSys}\n	Domain: $DOMAIN\n	Kerberos Domain: ${DOMAIN^^}\n" \
	  >> "$logName"
	dcArray=()
	IFS="."
	read -r -a dcArray <<< "${hostNameSys}"
	dn=${dcArray[0]} && echo -e "\nHost: ${dn}"
	tld=${dcArray[-1]} && echo -e "TLD is: .${tld}"
	ldap_dn="DN=${dn}"
	for ((i=1; i<${#dcArray[@]}; i++)); do
		ldap_dn="${ldap_dn},CN=${dcArray[i]}"
	done
	echo -e "LDAP DN Structure:\n${ldap_dn}\n" >> "$logName"

	# This block should generate an intelligent subnet for the freeipa container based off the server's current values
	# Put the wavelet domain controller subnet at the end of the current subnet range.
	currentIPCIDR="$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | head -n 1)"
	childSubnetCIDR="/28"
	# childSubnetCIDRHosts="14"
	currentSubnet=$(ip route | grep "$active_networkInterface" | grep src | awk '{print $1}')
	network=$(ipcalc "$currentIPCIDR" | sed -n '/^Network:/p' | awk '{print $2}')
	childSubnetMaxAddr=$(ipcalc "$network" --maxaddr)
	childSubnetClean=${childSubnetMaxAddr##*=}
	childSubnetNetworkAddr="${childSubnetClean%.*}."
	childSubnetLastOctet=${childSubnetClean##*.}
	# We don't want to eat the existing subnet's broadcast address..
	childSubnetRangeStart=$(( childSubnetLastOctet - $(( 14 * 2 )) ))
	# Set our target IP addresses (static) for our containers
	IPAServerHostIP=$(( childSubnetRangeStart + 1 )); IPAServerHostIP="${childSubnetNetworkAddr}${IPAServerHostIP}"
	# May not use macvlan for this but let's calculate one anyway..
	DHCPServerHostIP=$(( childSubnetRangeStart)); DHCPServerHostIP="${childSubnetNetworkAddr}${DHCPServerHostIP}"
	hostLinkIP=$(( childSubnetRangeStart + 2 )) ; hostLinkIP="${childSubnetNetworkAddr}${hostLinkIP}"
	ipaSubnetArg=$(ipcalc "${childSubnetNetworkAddr}${childSubnetRangeStart}${childSubnetCIDR}" | sed -n 2p | \
    	awk '{ print $2 }')
	# Generate a valid DHCP pool range for ISC-Kea
	subnetRangeStart=$(ipcalc "$network" --minaddr)
	subnetDHCPRangeStart="$childSubnetNetworkAddr$(("${subnetRangeStart##*.}" + 63))"
	subnetDHCPRangeEnd="$childSubnetNetworkAddr$(("${subnetRangeStart##*.}" + 127))"
	echo -e "\nGenerated subnet data:\n$(ipcalc "${childSubnetNetworkAddr}${childSubnetRangeStart}${childSubnetCIDR}")" \
	  >> /"$logName"
	echo -e "\nIPA Server will be granted IP Address:\n ${IPAServerHostIP}" \
		>> "$logName"
	#echo -e "\nDHCP ISC-Kea Server will be granted IP Address:\n ${DHCPServerHostIP}" \
	#	>> "$logName"
	# These commands perform the following (evil) tasks:
	#		Creates a podman network in the same subnet as the physical network
	#		generates a "shim" ipvlan device and assigns an IP address to it
	#		force-adds a route to that the container and the host can now communicate
	podman network create -d ipvlan \
	  --subnet "${currentIPCIDR}" \
	  --gateway "${gateway}" \
	  --ip-range "${ipaSubnetArg}" \
	  ipa_ipvlan \
	  -o parent="${active_networkInterface}"

	# Quick container command to test this, just try to ping the svr.wavelet.allethrium host:
	# podman run -it --network=ipa_ipvlan alpine:latest /bin/sh
	# If ping successful (and vice versa) the IPA container should now have no problem communicating with host.

	# Reconfigure DNS to use our FreeIPA server
	reconfigure_dns

	# Sanitize target directories and old containers
	rm -rf "/var/freeipa-data"
	podman rm freeipa_dc1_install
	mkdir -p "/var/freeipa-data/"
	echo "	Generating IPA server install options file.." >> "$logName"
	echo "-U
--domain=$DOMAIN
-r ${DOMAIN^^}
--ip-address=${IPAServerHostIP}
--ds-password=${administratorPassword}
--admin-password=${administratorPassword}
--ntp-pool=3.us.pool.ntp.org 
--setup-dns 
--auto-forwarder
--auto-reverse
--allow-zone-overlap
--no-hbac-allow 
--setup-adtrust" > /var/freeipa-data/ipa-server-install-options
	# Set secure permissions on the options file (0600) so only root can read it
	# Note: The podman container will access this via the :Z volume mount which handles SELinux context
	chmod 0600 /var/freeipa-data/ipa-server-install-options
	echo -e "\n	Attempting setup of FreeIPA server instance.." >> "$logName"
	echo -e "\n Details in journalctl or /var/freeipa-data/var/logs" >> "$logName"
	ipaHostName="dc1.$DOMAIN"
	# Turn off logging for this part, ipa has a quiet option for this purpose
	mkdir -p /root/logs
	podman run -d \
		--name freeipa_dc1_install \
		--read-only \
		--dns=127.0.0.1 \
		-h="$ipaHostName" \
		--ip="$IPAServerHostIP" \
		--network=ipa_ipvlan \
		-v /var/freeipa-data:/data:Z \
		"$hostNameSys/freeipa-server:latest" ipa-server-install -q -U < "/var/freeipa-data/ipa-server-install-options"
	# Wait for server install to complete
	file="/var/freeipa-data/var/log/ipaserver-install.log" >> "$logName"
	while [[ ! -f "$file" ]]; do
		sleep 1
	done
	echo "	Waiting for server installation to complete.." >> "$logName"
	wait_for_line "INFO The ipa-server-install command was successful"
	# Make sure the INSTALL container has been stopped and destroyed!
	podman rm freeipa_dc1_install -f
	# Securely shred the FreeIPA install options file that contains plaintext passwords
	if [[ -f "/var/freeipa-data/ipa-server-install-options" ]]; then
		shred -u -v -n 3 "/var/freeipa-data/ipa-server-install-options"
	fi
	# Generate named ACL
	echo -e "acl \"wavelet_network\" {\n127.0.0.1;\n$currentSubnet;\n};" >> "/var/freeipa-data/etc/named/ipa-ext.conf"
	echo -e "allow-recursion { wavelet_network; };\nallow-query-cache { wavelet_network; };" >> "/var/freeipa-data/etc/named/ipa-options-ext.conf"
	echo "	Generating paths and quadlets.." >> "$logName"
	mkdir -p "/var/freeipa-data"
	# This sets up the QUADLET to run freeipa, but it does not set the server itself up.
	# Port 953 needed for dynamic DNS updates
	# Run iplink_up.sh to activate the generated shim to that we can talk to the container from the server
	# Note we are using the tagged local image, because we don't have certificates yet we can't use the registry.
	podman pull "$hostNameSys/freeipa-server"
	cat > "/etc/containers/systemd/freeipa.container" <<-EOF
		[Container]
		Image=%H/freeipa-server:latest
		ContainerName=freeipa_server
		Volume=/var/freeipa-data:/data:z
		HostName=dc1.$DOMAIN
		IP=${IPAServerHostIP}
		Network=ipa_ipvlan
		ReadOnly=true
		DNS=127.0.0.1
		AutoUpdate=registry
		NoNewPrivileges=true

		[Service]
		Restart=always
		RestartSec=5
		TimeoutStartSec=600
		ExecStartPost=-/usr/bin/bash -c "/usr/local/bin/ipa_link_up.sh"

		[Install]
		WantedBy=multi-user.target
	EOF
	podman rm freeipa_dc1_install -f
	systemctl daemon-reload && systemctl start freeipa.service
	if systemctl is-active --quiet freeipa.service; then
		echo "	FreeIPA configured and container is running!" >> "$logName"
		echo "	Enrolling server to freeIPA.." >> "$logName"
		iplink_create_ipvlan
		install_server_security_layer
	else
		echo "	FreeIPA provisioning failed!  Failing task." >> "$logName"
		exit 1
	fi
}

install_server_security_layer(){
  # Configures the wavelet server with Freeipa-client
  local directoryManagerPassword; local administratorPassword
	directoryManagerPassword="$(cat /var/secrets/ipaadmpw.secure)"
	# Directory manager and Admin credential are the same.  We probably want to alter this.
	cat /var/secrets/ipaadmpw.secure > /var/secrets/ipadmpw.secure
	administratorPassword="$(cat /var/secrets/ipaadmpw.secure)"
	# The preferred method would be to run the ipa-client in a container
	# I found the documentation on this to leave something to be desired.
	# We run bare metal on the overlay after solving an nfs-utils issue and manually generating some directories.
	mkdir -p /var/lib/ipa-client/{pki,sysrestore,certmonger}
	mkdir -p /var/lib/certmonger
	# Note & at the end to run in a subshell or installation hangs at installation success for a LONG time.
	# We define the server's IP address here during install, or we waste a lot of time with DNS queries
	active_networkInterface=$(ip route get 8.8.8.8 | sed -nr 's/.*dev ([^\ ]+).*/\1/p')
	ethernetInterfaceUUID="$(nmcli -t -f UUID,type con show --active | grep ethernet | cut -d: -f1)"
	clientIpAddress="$(nmcli -t -f ipv4.addresses con show "$ethernetInterfaceUUID" | cut -d: -f2)"
	# SELinux breaks certmonger, so we fix this here
	semanage fcontext -a -t certmonger_var_lib_t "/var/lib/certmonger(/.*)?"
	restorecon -Rv "/var/lib/certmonger"
	# Install the freeIPA client on the server bare metal
	echo "	Ensuring DNS resolution functions.."
#	output="$(dig @dc1 _ldap._tcp.wavelet.allethrium)"
#	output="$(dig _ldap._tcp.wavelet.allethrium)"
	echo "	Attempting IPA Client installation.."
	# We must NOT use --enable-dns-updates here, as the ipa-client seems to prefer the ipvlan shim to the real NIC
	# Run ipa-client-install and capture output to a file we can monitor
	ipa-client-install --unattended --principal=admin --password="${administratorPassword}" \
	--ssh-trust-dns --ip-address="${clientIpAddress%/*}" > "/var/log/ipaclient-install.log" 2>&1 &
	# Use inotify to wait for the file to exist instead of busy waiting
	file="/var/log/ipaclient-install.log"
	# Ensure the log file exists
	touch "$file"
	inotifywait -q -e modify "$file" --timeout 300 > /dev/null || true
	echo -e "\n\n	IPA client installation log being processed, continuing.." >> "$logName"
	# Now tail the file until we find success pattern
	wait_for_line "Client configuration complete."
	#podman exec freeipa_server ldapmodify -x -D "cn=admin" -W  -f pwmod.ldif
	# Ideally here, we could use REST calls w/ Unleashed to add our new CA to the AP
	echo "SERVER_DOMAIN_ENROLLMENT_COMPLETE=1" >> "/etc/wavelet.conf"
}

ipa_dns_tsig(){
	# Generate a tsig file for zone transfer from the DHCP server to IPA's internal BIND.
	# Ref https://www.freeipa.org/page/DHCP_Integration_Design
	echo "	Generating DNS TSIG key and modifying DNS zones for transfer updates" >> "$logName"
	echo "	This is necessary for DHCP to be able to update IPA's DNS records." >> "$logName"
	mkdir -p "/etc/kea/tsig-keys"
	local secret;
	secret=$(tsig-keygen -a hmac-sha512 KEA-DHCP | awk '/secret/{gsub(/"/,"",$2); sub(/;$/,"",$2); print $2}')
	cat > "/etc/kea/tsig-keys/KEA-DHCP.json" <<EOF
"tsig-keys": [
	{
		"name": "KEA-DHCP",
		"algorithm": "hmac-sha512",
		"secret": "$secret"
	}
],
EOF
	chmod 0755 /etc/kea; chown -R kea:root /etc/kea; chmod -R 0640 /etc/kea/*
	chmod 0755 /etc/kea/tsig-keys; chmod 0640 /etc/kea/tsig-keys/KEA-DHCP.json
	# Allow DDNS updates from Kea to FreeIPA via dnzone policy
	# Note this goes into the container /var/freeipa-data/etc folder!
	echo "/* Wavelet ISC-Kea DHCP TSIG KEY */
key \"KEA-DHCP\" {
	algorithm hmac-sha512;
	secret \"$secret\";
};" >> /var/freeipa-data/etc/named/ipa-ext.conf
	ipa dnszone-mod "${DOMAIN^^}." \
	  --update-policy="grant ${DOMAIN^^} krb5-self * A; grant ${DOMAIN^^} krb5-self * AAAA; grant ${DOMAIN^^} krb5-self * SSHFP; grant KEA-DHCP wildcard * ANY;"
	ipa dnszone-mod "${DOMAIN^^}." --dynamic-update=1
	ipa dnszone-mod "${DOMAIN^^}." --allow-sync-ptr=TRUE
	# Because of our very weird virtual/host setup, we need to manually add the server DNS record and reverse;
	ipa dnsrecord-add "$DOMAIN." "$(hostname -s)" --a-rec "$SVR_IP"
	# Note: Reverse DNS zone for the IPA server subnet is already created by --auto-reverse during IPA server installation
	# Restart ipa service so that the modified ipa-ext.conf is loaded for named
	systemctl restart freeipa.service
	sleep 8
}

wait_for_line(){
	# Loops until pattern appears in log
	echo -e "		Input file: $file" >> "$logName"
	echo -e "			Waiting for match: $1" >> "$logName"
	inactivity_seconds=5
	while true; do
		if inotifywait -q -e modify "$file" --timeout "$inactivity_seconds" > /dev/null; then
			last_mod_time="$(date -r "$file" +%s)"
		else
			current_time="$(date +%s)"
			inactivity_time="$((current_time - last_mod_time))"
			if [[ "$inactivity_time" -ge "$inactivity_seconds" ]]; then
				if grep -q "$1" "$file"; then
					echo "			Pattern matched!" >> "$logName"
					break
				else
					:
				fi
			fi
		fi
	done
}

configure_etcd_certs(){
	# Configure ETCD service principal within freeIPA
	ipa service-add "etcd/$hostNameSys"
	ipa service-add-host --hosts="$hostNameSys" "etcd/$hostNameSys"
	# Configure the system certificate store for the ETCD service principal
	# This requires am X509 SAN extension to support the IP address of the etcd cluster.
	ipa-getcert request \
		-f "/etc/pki/tls/certs/etcd.crt" \
		-k "/etc/pki/tls/private/etcd.key" \
		-K "etcd/$SVR_HOSTNAME" \
		-N "$SVR_HOSTNAME"
	echo -e "		TLS Certificate for Etcd generated.\n"
	# We generate the quadlet here so it is ready to go.
	# Add FREEIPA ACME service check, etcd will not start until IPA CA is available.
	cat > /etc/containers/systemd/etcd-quadlet.container <<-EOF
		[Unit]
		Description=etcd quadlet
		Documentation=https://github.com/etcd-io/etcd
		Documentation=man:etcd
		After=network.target

		[Container]
		Environment=ETCD_DATA_DIR=/etcd-data
		Environment=ETCD_CONFIG_FILE=/etc/etcd/etcd.conf
		Image=%H/etcd:latest
		ContainerName=etcd-quadlet
		Network=host
		Volume=/etc/etcd/:/etc/etcd/:Z
		Volume=/var/lib/etcd-data:/etcd-data:Z
		Volume=/etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem/
		Volume=/etc/pki/tls/certs/etcd.crt:/etc/pki/tls/certs/etcd.crt
		Volume=/etc/pki/tls/private/etcd.key:/etc/pki/tls/private/etcd.key
		AutoUpdate=registry
		NoNewPrivileges=true

		[Service]
		Environment=ETCD_CONFIG_FILE=/etc/etcd/etcd.conf
		ExecStartPre=-mkdir -p /var/lib/etcd-data
		ExecStartPre=-/bin/podman kill etcd
		ExecStartPre=-/bin/podman rm etcd
		ExecStartPre=/bin/bash -c 'until curl -ksf https://$IPAServerHostIP:8443/acme/ >/dev/null 2>&1; do sleep 3; done'
		Restart=always

		[Install]
		WantedBy=graphical.target
	EOF
}

configure_enrollment(){
	chown -R wavelet-root:wavelet-root /var/home/wavelet-root
	# These are called seldom, so we do not worry about their presence on ramfs
	generate_secure_systemd_service \
		user="wavelet-root" \
		serviceName="wavelet_provision" \
		key="/PROV/REQUEST" \
		modulePath="/usr/local/bin/wavelet_provision.sh" \
		additionalArg="PROV"
	generate_secure_systemd_service \
		user="wavelet-root" \
		serviceName="wavelet_enrollment_watcher" \
		key="/ENROLL/REQUEST/" \
		modulePath="/usr/local/bin/wavelet_client_domain_enroll.sh" \
		additionalArg="ENROLL"
	generate_secure_systemd_service \
		user="wavelet-root" \
		serviceName="wavelet_deprovision_watcher" \
		key="/HOSTS/" \
		modulePath="/usr/local/bin/wavelet_force_deprovision.sh" \
		additionalArg="root"
	# Add IPA Certmap rule for host cert pkinit (encase we want to use certificates instead of OTP)
	# Kinit as admin again, because we would be kinit as domain join from the process above
	kinit admin <"/var/secrets/ipaadmpw.secure"
	ipa certmaprule-add pkinit-host \
		--matchrule "<ISSUER>CN=Certificate Authority,O=${DOMAIN^^}" \
		--maprule='(fqdn={subject_dns_name})'
  # Process:
	# Client writes hostname into /ENROLL/REQUEST/$hostname -- val (REQUEST;machine-id)
	# Server Pulls hostname + gets MAC Address from host via arp -a
	# Server Process generates a host principal and issues an OTP via FreeIPA
	# Server uploads OTP to ETCD /ENROLL/$hostname/OTP -- val $otp
	# Watcher on the client machine grabs OTP
	# Server deletes OTP+REQUEST keys after 2 seconds - *blink!* (still crappy security)
	# Client immediately uses OTP to enroll in domain
	# This is insecure, but the following must be true for this to work:
	# The client must have the PROV account credential (or a new one)
	# The client must have the CA to talk to the etcd cluster
	# The client must successfully use its own data to generate the decrypt key for the OTP pass
	# Communication with the etcd cluster is secured via TLS
	# The client is limited to writing to this single key
	echo "		Provision Infrastructure for clients generated." >> "$logName"
}

configure_httpd_sp(){
	# Configure Apache service principal
	ipa service-add "http/$hostNameSys"
	ipa service-add-host --hosts="$hostNameSys" "http/$hostNameSys"
	ipa-getcert request \
		-f "/etc/pki/tls/certs/httpd.crt" \
		-k "/etc/pki/tls/private/httpd.key" \
		-K "http/$hostNameSys"
	# Generate a certmonger hook to update the cert filter on certificate renewal for our user-facing services.
	echo -e "		TLS Certificate for web services generated.\n" >> "$logName"
	while [[ ! -f "/etc/pki/tls/certs/httpd.crt" ]]; do
		sleep .5
	done
	# We need to manually copy these certs initially, as the service is not yet running
	mkdir -p "/var/home/wavelet/config/certs"
	cp "/etc/pki/tls/certs/httpd.crt" "/var/home/wavelet/config/certs"
	cp "/etc/pki/tls/private/httpd.key" "/var/home/wavelet/config/certs"
	chown -R wavelet:wavelet "/var/home/wavelet/config/certs"
	# To Pull httpd.conf out of the container:
	# podman run --rm httpd:2.4 cat /usr/local/apache2/conf/httpd.conf > custom-httpd.conf
	# We set global sebool for container cert access and mount the files directly as container volumes now.
	# semanage fcontext -a -t cert_t --ftype -- "/etc/pki/tls/certs/httpd.crt"
	# semanage fcontext -a -t cert_t --ftype -- "/etc/pki/tls/certs/httpd.key"
	# restorecon -FvR /etc/pki/tls/certs/
}

configure_registry_sp(){
	echo "		Re-utilizing the httpd certificate for Registry services.." >> "$logName"
	# Reconfigure the registry systemd unit to look for the httpd certificates
	# This amounts to mounting the pki volumes in the systemd unit and adding REGISTRY_HTTP_TLS_CERTIFICATE
	# along with REGISTRY_HTTP_TLS_KEY environment args to the quadlet.
	cat > "/etc/containers/systemd/registry.container" <<-EOF
		[Unit]
		Description=Wavelet container registry
		After=network-online.target
		Wants=network-online.target

		[Container]
		ContainerName=registry
		Image=registry
		AutoUpdate=local
		Network=host
		Volume=/var/containers/registry:/var/lib/registry/:z
		Volume=/etc/pki/tls/certs/httpd.crt:/certs/httpd.crt
		Volume=/etc/pki/tls/private/httpd.key:/certs/httpd.key
		Environment=REGISTRY_LOG_LEVEL=info
		Environment=OTEL_TRACES_EXPORTER=none
		Environment=REGISTRY_HTTP_TLS_CERTIFICATE=/certs/httpd.crt
		Environment=REGISTRY_HTTP_TLS_KEY=/certs/httpd.key

		[Service]
		Restart=always

		[Install]
		WantedBy=multi-user.target
	EOF
	# TODO - ensure the cert makes it into the correct docker dir
	# Ensure we modify the registry definition to secure after are done, or calls to it will fail.
	cat > "/etc/containers/registries.conf.d/10-wavelet.conf" <<-EOF
		[[registry]]
		prefix = "svr.$DOMAIN"
		location = "$(hostname):5000"
		insecure = false
	EOF
}

configure_radius_sp(){
	# Configures the RADIUS service principal and then calls the module to configure the RADIUS quadlet
	ipa service-add "radius/$hostNameSys"
	ipa service-add-host --hosts="dc1.$DOMAIN" "radius/$hostNameSys"
	ipa-getcert request \
		-f "/etc/pki/tls/certs/radius.pem" \
		-k "/etc/pki/tls/private/radius.key" \
		-K "radius/$hostNameSys"
	# Configure Radius-over-TLS to secure AP->RADIUS traffic
	ipa service-add "radsec/$hostNameSys"
	ipa service-add-host --hosts="$hostNameSys" "radsec/$hostNameSys"
	ipa-getcert request \
		-f "/etc/pki/tls/certs/radsec.crt" \
		-k "/etc/pki/tls/private/radsec.key" \
		-K "radsec/$hostNameSys"
	echo -e "		TLS Certificates for RADIUS services generated\n" >> "$logName"
}

configure_freeipa_8021x(){
 	# Configures FreeIPA with an appropriate certificate profile
 	# Based off this guide: https://wiki.fil.guru/a/a1cff461-5579-4cfd-9c41-d60911bae228
  	# Changes - the certificates last 10 years, and they are stored in FreeIPA
 	# This means the revocation mechanism will work for our purposes (I.E wavelet deprovision)
 	# 10yr certificate lifetime means that the system WILL stop working after that deployment window!
 	echo "		Generating certificate profile for EAP-TLS clients.." >> "$logName"
 	ipa certprofile-show caIPAserviceCert --out caIPAserviceCert.txt
 	cp caIPAserviceCert.txt ca802_1xCert.txt
 	sed -i 's/.serverCertSet./.set1./g' ca802_1xCert.txt
 	sed -i 's/policyset.list=serverCertSet/policyset.list=set1/g' ca802_1xCert.txt
 	sed -i 's/caIPAserviceCert/ca802_1xCert/g' ca802_1xCert.txt
 	sed -i 's/server certificates/802.1x certificates/g' ca802_1xCert.txt
 	sed -i 's/Server Certificate Enrollment/802.1x Certificate Enrollment/g' ca802_1xCert.txt
 	# Note - tutorial/blog shows 1.2 and IPA generates .2 - check if this is important
 	# Delete policyset.set.2 and append to replace it with
 	sed -i '/policyset\.serverCertSet\.2/,+2d' ca802_1xCert.txt
 	cat >> "ca802_1xCert.txt" <<-EOF
		policyset.set.2.constraint.class_id=validityConstraintImpl
		policyset.set.2.constraint.name=Validity Constraint
		policyset.set.2.constraint.params.rangeUnit=day
		policyset.set.2.constraint.params.range=3650
		policyset.set.2.constraint.params.notBeforeGracePeriod=3650
		policyset.set.2.constraint.params.notBeforeCheck=true
		policyset.set.2.constraint.params.notAfterCheck=true
		policyset.set.2.default.class_id=validityDefaultImpl
		policyset.set.2.default.name=Validity Default
		policyset.set.2.default.params.range=3650
		policyset.set.2.default.params.startTime=0"
	EOF
	# Remove 1024 bit keys from the keyParameters list
	sed -i 's/policyset.set1.3.constraint.params.keyParameters=1024,2048,3072,4096,8192/policyset.set1.3.constraint.params.keyParameters=2048,3072,4096,8192/g' ca802_1xCert.txt
	# Set certificate key usage OID's to clientAuth,Eap-Over-LAN
	sed -i 's/policyset.set1.7.default.params.exKeyUsageOIDs=1.3.6.1.5.5.7.3.1,1.3.6.1.5.5.7.3.2/policyset.set1.7.default.params.exKeyUsageOIDs=1.3.6.1.5.5.7.3.2,1.3.6.1.5.5.7.3.14/g' ca802_1xCert.txt
	# Modify certificate signing algorythms to keep them compatible with EAP-TLS
	sed -i 's/policyset.set1.8.constraint.params.signingAlgsAllowed=SHA1withRSA,SHA256withRSA,SHA384withRSA,SHA512withRSA,MD5withRSA,MD2withRSA,SHA1withDSA,SHA1withEC,SHA256withEC,SHA384withEC,SHA512withEC/policyset.set1.8.constraint.params.signingAlgsAllowed=SHA256withRSA,SHA384withRSA,SHA512withRSA/g' ca802_1xCert.txt
	# We may want to retain revocation checks for our purposes!
	# Delete policyset 1.5 from the list to disable OSCP revocation checks
	# sed -i 's/policyset.set1.list=1,2,3,4,5,6,7,8,9,10,11,12/policyset.set1.list=1,2,3,4,6,7,8,9,10,11,12/g' ca802_1xCert.txt
	# Import the new certificate profile, add ACL host profile and bind it to hosts
	# Since we have limited clients, we don't mind storing the certificates and can therefore use IPA for CRL
	ipa certprofile-import ca802_1xCert \
		--file=ca802_1xCert.txt \
		--store=true \
		--desc="This certificate profile is for enrolling 802.1x certificates with IPA-RA agent authentication." >> "$logName"
	# We are going to use IPA's groups feature to handle this
	ipa hostgroup-add decoders --desc="All wavelet decoder devices"
	ipa automember-add --type=hostgroup decoders
	ipa automember-add-condition --type=hostgroup decoders \
    --key=fqdn --inclusive-regex='^(dec)[0-9]+'
    # IPA only accepts hostcat=all as arg, see: https://www.freeipa.org/page/V4/Certificate_Profiles
  	ipa caacl-add hosts__ca802_1xCert --desc="CA ACL for wavelet decoders" --hostcat=all
	# ipa caacl-add-host hosts__ca802_1xCert --hostgroups=decoders
	# The CA must be added to the ACL as well.
	ipa caacl-add-ca hosts__ca802_1xCert --cas=ipa
	# Then we must add the ACL to the profile we just generated
	ipa caacl-add-profile hosts__ca802_1xCert --certprofiles=ca802_1xCert
	# The client will request WiFi certs once enrolled in the IPA Domain
	echo "	IPA CA Updated to support machine 802.1x certificates!" >> "$logName"
}

#configure_additional_service(){
#	# Intermediate CA from other upstream systems?
#	# Any credentials-based services we might need logins for
#	# Stuff I haven't yet thought of here
#	# rkhunter propupd set for system files and configure a daily cron job for scanning and upstream notification
#	mkdir -p "/var/log/rkhunter/"; mkdir -p "/var/lib/rkhunter/db"
#	cat > "/etc/cron.daily/rkhunter.sh" <<EOF
##!/bin/sh
#(
#	#/usr/local/bin/rkhunter --versioncheck
#	#/usr/local/bin/rkhunter --update
#	/usr/local/bin/rkhunter --cronjob --report-warnings-only
#)
##| /bin/mail -s 'rkhunter Daily Run (PutYourServerNameHere)' your@email.com"
#EOF
#	rkhunter --update
#	rkhunter --propupd
#	clamconf -g "freshclam.conf" > "freshclam.conf"
#    clamconf -g "clamd.conf" > "clamd.conf"
#    clamconf -g "clamav-milter.conf" > "clamav-milter.conf"
#    setsebool -P antivirus_can_scan_system 1
#	systemctl --now enable clamav-freshclam.service clamd@scan.service
#}

configure_wavelet_ap(){
	# TODO - This is broken
	# Ruckus don't provide a public API for Unleashed so this is a lot of poking and guessing.
	# Configures the Access Point defined in the installer
	echo "		Configuring WiFi Access point certificates.."
	local wifi_ap_block; local wifi_ap_ip; local wifi_ap_mac; local wifi_adminUser; local wifi_adminPass
	local cookie_file; local supportedVendorMAC; local macPrefixListFile
	local wifi_config_dir="/var/home/wavelet-root/config"
	# Check if WiFi config directory and required files exist
	if [[ ! -d "$wifi_config_dir" ]]; then
		echo "		WiFi configuration directory $wifi_config_dir does not exist. Skipping AP configuration." >> "$logName"
		return 0
	fi
	wifi_ap_ip="$(cat "${wifi_config_dir}/wifi_ipaddr" 2>/dev/null)"
	if [[ -z "$wifi_ap_ip" ]]; then
		echo "		WiFi AP IP address not specified in ${wifi_config_dir}/wifi_ipaddr. Skipping AP configuration." >> "$logName"
		return 0
	fi
	wifi_ap_mac="$(arp "$wifi_ap_ip" 2>/dev/null | tail -n 1 | awk '{print $3}')"
	if [[ -z "$wifi_ap_mac" || "$wifi_ap_mac" == "Incomplete" ]]; then
		echo "		Could not resolve MAC address for WiFi AP IP $wifi_ap_ip. Skipping AP configuration." >> "$logName"
		return 0
	fi
	wifi_ap_block="$(echo "$wifi_ap_mac" | tr '-' ':' | cut -d ":" -f1-3)"
	wifi_adminUser="$(cat "${wifi_config_dir}/wifi_adminuser" 2>/dev/null)"
	wifi_adminPass="$(cat "${wifi_config_dir}/wifi_adminpw" 2>/dev/null)"
	if [[ -z "$wifi_adminUser" || -z "$wifi_adminPass" ]]; then
		echo "		WiFi AP admin credentials not fully specified in ${wifi_config_dir}/. Skipping AP configuration." >> "$logName"
		return 0
	fi
	# Right now, there's no purpose in this file as we only support Ruckus Unleashed.
	macPrefixListFile="${wifi_config_dir}/supportedVendorMAC"
	cookie_file="$(mktemp)"
	supportedVendorMAC=false
	# Check if macPrefixListFile exists and has content
	if [[ -f "$macPrefixListFile" && -s "$macPrefixListFile" ]]; then
		while IFS= read -r prefix; do
	    	# Skip empty lines
	    	if [[ -z "$prefix" ]]; then
		        continue
		    fi
		    # Check if the wifi_ap_mac starts with the current prefix
		    if [[ "$wifi_ap_block" == "$prefix"* ]]; then
		        supportedVendorMAC=true
		        break
		    fi
		done < "$macPrefixListFile"
	else
		# If no macPrefixListFile, assume supported (Ruckus Unleashed is the only supported vendor)
		supportedVendorMAC=true
	fi
	if [[ ! "$supportedVendorMAC" ]]; then
	    echo "		The provided Wireless Access Point MAC address does not match Wavelet's supported vendor list." \
	        >> "$logName"
	    echo "		Wavelet will be unable to automatically generate and sign the device certificate, so this must be done manually!" \
	        >> "$logName"
	    return 0
	fi
	# This code was copied and (slightly) adapted from:
	# https://github.com/acmesh-official/acme.sh/blob/master/deploy/ruckus.sh
	echo "		Discovering the login URL"
	login_url="$(curl https://"$wifi_ap_ip" -k -s -L -o /dev/null -w '%{url_effective}')"
	if [ -n "$login_url" ]; then
		login_path=$(echo "$login_url" | sed 's|https\?://[^/]\+||')
		if [ -z "$login_path" ]; then
			echo "		Connection failed: redirected to a different host."
			return 1
		fi
	fi
	if [ -z "$login_url" ]; then
		echo "		Connection failed: couldn't find login page."
		return 1
	fi
	base_url=$(dirname "$login_url")
	login_page=$(basename "$login_url")
	if [ "$login_page" = "index.html" ]; then
		echo "		Connection temporarily unavailable: Unleashed Rebuilding."
		return 1
	fi
	if [ "$login_page" = "wizard.jsp" ]; then
		echo "		Connection failed: Setup Wizard not complete."
		return 1
	fi
	# Get CSRF token and establish session
	loginResponse="$(curl -k -c "$cookie_file" "$login_url" -d username="$wifi_adminUser" -d password="$wifi_adminPass" -d ok=Log\ In -i | awk '/^HTTP_X_CSRF_TOKEN:/ { print $2 }' | tr -d '\040\011\012\015')"
	# Get AP system information
	xmlString="<ajax-request action='getstat' comp='system'><identity/><sysinfo/></ajax-request>"
	apName="$(curl -k -b "$cookie_file" "$base_url/_cmdstat.jsp" -H "X-CSRF-Token: $loginResponse" --data-raw "$xmlString" | xmllint --xpath 'string(//identity/@name)' -)"
	apFQDN="$apName.$DOMAIN"
	if [[ -z "$apName" ]]; then
		echo "		Access point hostname is not populated!  Cannot continue."
		return 1
	fi
	# Set up FreeIPA entries
	# These would be needed for a CSR, so we leave them in.
	kinit admin < "/var/secrets/ipaadmpw.secure"
	ipa host-add "$apFQDN" --force
	ipa service-add "WiFi-AP/$apFQDN" --force
	# The CA is all that's required for the AP to be able to open a TLS connection w/ RADIUS
	addCaSuccess="$(curl -k -b "$cookie_file" "$base_url/_upload.jsp?request_type=xhr" \
      -H "X-CSRF-Token: $loginResponse" \
      -F "u=@/etc/ipa/ca.crt" \
      -F "action=uploadCA" \
      -F "callback=uploader_uploadCA" \
      -F "ImportCaMethod=cover" \
      2>/dev/null \
      | grep "CF_CADoneDesc")"
    if [[ -z "$addCaSuccess" ]]; then
		echo "		Failed to upload CA certificate!"
		rm -f "$cookie_file"
		return 1
	else
		xmlString="<ajax-request action='docmd' comp='system' updater='rid.0.5' xcmd='delete-file' timeout='-1'><xcmd cmd='delete-file' type='uploaded' filename='uploadCA'/></ajax-request>"
		curl -k -b "$cookie_file" "$base_url/_cmdstat.jsp" -H "X-CSRF-Token: $loginResponse" --data-raw "$xmlString" >/dev/null 2>&1
	fi
	rm -f "$cookie_file"
	# Configure AP for low-latency video and multicast optimization
	# echo "		Configuring AP for low-latency video transmission..."
	# configure_ap_video_optimization "$cookie_file" "$base_url" "$loginResponse"
	# Reboot AP to fully activate new certificate
	#xmlString='<ajax-request action="docmd" comp="worker" updater="rid.0.5" xcmd="cert-reboot" checkAbility="6"><xcmd cmd="cert-reboot" action="undefined"/></ajax-request>'
	#curl -k -b "$cookie_file" \
	#	-X POST "$base_url/_cmdstat.jsp" \
	#	-H "X-CSRF-Token: $loginResponse" \
	#	--data-raw "$xmlString"
	echo "		AP configuration completed successfully!"
}

configure_ap_video_optimization(){
	# TODO - not used as the API is not published.
	local cookie_file; local base_url; local csrf_token; local xmlString
	cookie_file="$1"
	base_url="$2"
	csrf_token="$3"
#	curlOpts="-k -b $cookie_file"
	echo "		Configuring AP for defensive 5GHz-only operation in hostile RF environment..."
	# DISABLE 2.4GHz radio completely
	xmlString='<ajax-request action="setstat" comp="radio-2g">
		<radio enabled="false"/>
	</ajax-request>'
	curl -k -b "$cookie_file" "$base_url/_cmdstat.jsp" -H "X-CSRF-Token: $csrf_token" --data-raw "$xmlString"
	echo "		2.4GHz radio disabled"
	# Configure 5GHz for interference avoidance and adaptive behavior
	xmlString='<ajax-request action="setstat" comp="radio-5g">
		<radio enabled="true" channel="auto" channelwidth="80" txpower="auto">
			<advanced>
				<beacon_interval>100</beacon_interval>
				<dtim_period>1</dtim_period>
				<rts_threshold="1500"/>
				<fragmentation_threshold="1500"/>
				<short_gi>true</short_gi>
				<aggregation enabled="true" ampdu_max_length="65535"/>
				<amsdu enabled="true" amsdu_max_length="7935"/>
				<ldpc enabled="true"/>
				<stbc enabled="true"/>
				<beamforming enabled="true"/>
				<dynamic_channel_assignment enabled="true"/>
				<interference_mitigation enabled="true"/>
			</advanced>
		</radio>
	</ajax-request>'
	curl -k -b "$cookie_file" "$base_url/_cmdstat.jsp" -H "X-CSRF-Token: $csrf_token" --data-raw "$xmlString"
	# Enable aggressive interference avoidance
	xmlString='<ajax-request action="setstat" comp="wlan-advanced">
		<bandsteering enabled="false"/>
		<interference_detection enabled="true" threshold="-70"/>
		<channel_scan_interval>300</channel_scan_interval>
		<neighbor_ap_detection enabled="true"/>
		<radar_detection enabled="true"/>
		<channel_utilization_monitoring enabled="true"/>
	</ajax-request>'
	curl -k -b "$cookie_file" "$base_url/_cmdstat.jsp" -H "X-CSRF-Token: $csrf_token" --data-raw "$xmlString"
	# Conservative multicast and client management
	xmlString='<ajax-request action="setstat" comp="wlan-advanced">
		<multicast_enhancement enabled="true" rate="36000"/>
		<proxy_arp enabled="true"/>
		<airtime_fairness enabled="true"/>
		<client_balancing enabled="true" max_clients="16"/>
		<admission_control enabled="true"/>
	</ajax-request>'
	curl -k -b "$cookie_file" "$base_url/_cmdstat.jsp" -H "X-CSRF-Token: $csrf_token" --data-raw "$xmlString"
	# Defensive QoS - prioritize our traffic but don't be greedy
	xmlString='<ajax-request action="setstat" comp="qos">
		<wmm enabled="true"/>
		<diffserv enabled="true"/>
		<video_priority>5</video_priority>
		<voice_priority>6</voice_priority>
		<rate_limiting enabled="true" per_client_limit="180000"/>
		<burst_control enabled="true"/>
		<traffic_shaping enabled="true"/>
	</ajax-request>'
	curl -k -b "$cookie_file" "$base_url/_cmdstat.jsp" -H "X-CSRF-Token: $csrf_token" --data-raw "$xmlString"
	# Enable coexistence features for dense environments
	xmlString='<ajax-request action="setstat" comp="wlan-advanced">
		<bss_coloring enabled="true"/>
		<spatial_reuse enabled="true" sensitivity_threshold="-72"/>
		<overlapping_bss_protection enabled="true"/>
		<cts_protection enabled="true"/>
		<load_balancing enabled="true" rssi_threshold="-65"/>
	</ajax-request>'
	curl -k -b "$cookie_file" "$base_url/_cmdstat.jsp" -H "X-CSRF-Token: $csrf_token" --data-raw "$xmlString"
	# Conservative power and channel management
	xmlString='<ajax-request action="setstat" comp="wlan-advanced">
		<max_clients_per_radio="16"/>
		<client_isolation enabled="false"/>
		<pmf enabled="true"/>
		<mesh_networking enabled="false"/>
		<background_scanning enabled="true" scan_interval="600"/>
		<channel_utilization_threshold="75"/>
		<power_adjustment enabled="true"/>
	</ajax-request>'
	curl -k -b "$cookie_file" "$base_url/_cmdstat.jsp" -H "X-CSRF-Token: $csrf_token" --data-raw "$xmlString"
	# Block problematic legacy clients but not too aggressively
	xmlString='<ajax-request action="setstat" comp="wlan-advanced">
		<minimum_data_rate>12000</minimum_data_rate>
		<minimum_mgmt_rate>12000</minimum_mgmt_rate>
		<legacy_client_support enabled="true"/>
		<weak_signal_threshold>"-75"/>
	</ajax-request>'
	curl -k -b "$cookie_file" "$base_url/_cmdstat.jsp" -H "X-CSRF-Token: $csrf_token" --data-raw "$xmlString"
	# Enable smart retry and error recovery
	xmlString='<ajax-request action="setstat" comp="radio-5g">
		<radio>
			<advanced>
				<retry_limit>7</retry_limit>
				<short_retry_limit>3</short_retry_limit>
				<frame_aggregation_timeout>250</frame_aggregation_timeout>
				<channel_bonding adaptive="true"/>
				<noise_floor_monitoring enabled="true"/>
			</advanced>
		</radio>
	</ajax-request>'
	curl -k -b "$cookie_file" "$base_url/_cmdstat.jsp" -H "X-CSRF-Token: $csrf_token" --data-raw "$xmlString"
	# Set conservative SSID broadcast settings
	xmlString='<ajax-request action="setstat" comp="wlan-security">
		<ssid_broadcast enabled="true"/>
		<beacon_suppression enabled="false"/>
		<probe_response_optimization enabled="true"/>
		<management_frame_protection enabled="true"/>
	</ajax-request>'
	curl -k -b "$cookie_file" "$base_url/_cmdstat.jsp" -H "X-CSRF-Token: $csrf_token" --data-raw "$xmlString"
}

export_container(){
	# Exports container image to the Wavelet registry
	imageTarget="$1"
	if podman tag "$imageTarget" "${hostNameSys}/$imageTarget:latest"; then
		fail=0
		echo -e "Pushing container $imageTarget to registry..${NC}"
		podman push --format oci "${hostNameSys}/$imageTarget:latest" "$hostNameSys:5000/$imageTarget:latest" \
			>> "./build_registry.log"
	else
		fail=1
		echo -e "${RED}Unable to tag or push container image, possible package issue inside the container."
		(( count++ ))
		echo -e "Retrying as long as it takes (Retry attempts: $count)${NC}"
	fi
}

build_container(){
	# This function builds the container image
	# Needs imageTarget and containerFile as args
	imageTarget="$1"
	containerFile="$2"
	buildOptions="$3"
	echo "Attempting container build: $imageTarget"
	podman build "$buildOptions" -t "$imageTarget" \
    	-v="/var/home/wavelet/containerfiles:/mount:z" \
    	-f "/var/home/wavelet/containerfiles/$containerFile"
	local fail
	export_container "$imageTarget"
	if [[ "${fail}" == "1" ]]; then
		(( attempt++ ))
		if (( attempt < 2 )); then
			opt="--no-cache"
		fi
		echo "Build and export operation failed, repeating indefinitely.."
		build_container "$1" "$2" "$opt"
	fi
}

configure_ntp(){
	local config; local ntpServerHostIP
	echo "		Configuring NTP server services.." >> "$logName"
   	config="/etc/chrony.conf"
	# Ensure the chrony user exists (CoreOS 44+ requirement)
	if ! id -u chrony &>/dev/null; then
		useradd -r -g chrony -s /sbin/nologin -d /nonexistent chrony 2>/dev/null || true
    fi
   	ntpServerHostIP="$SVR_IP"
   	# Configure upstream NTP pools for this server
   	cat > "$config" <<-EOF
		# Wavelet NTP server configuration
		# Upstream time sources
		server 3.us.pool.ntp.org iburst
		server time.nist.gov iburst

		# Allow local subnet to query this server as NTP source
		allow 192.168.1.0/24
		local stratum 3
		driftfile /var/lib/chrony/drift
		rtcsync

		# Log
		log tracking measurements statistics
		logdir /var/log/chrony

		# Record the step of the clock every 10 samples
		#makestep 1.0 3

		# NTP servers to sync to
		bindcmdaddress $ntpServerHostIP
		bindaddress $ntpServerHostIP
		bindaddress 127.0.0.1
	EOF
    	echo -e "		NTP server configuration written to $config" >> "$logName"
    	systemctl enable chronyd.service --now
    	echo -e "		Chronyd NTP server is running on $ntpServerHostIP\n" >> "$logName"
}


configure_firewall(){
    # Configures NFT for kernel-native filtering
    subNetCIDR="$currentSubnet"
    nft flush ruleset
    nft add table inet wavelet
    nft add chain inet wavelet input '{ type filter hook input priority 0; policy drop; }'
    nft add chain inet wavelet forward '{ type filter hook forward priority 0; policy drop; }'
    nft add chain inet wavelet output '{ type filter hook output priority 0; policy accept; }'
    # Allow loopback
    nft add rule inet wavelet input iif lo accept
    nft add rule inet wavelet input ct state established,related accept
    # Rate limiting to prevent brute-force on SSH
    nft add rule inet wavelet input tcp dport 22 limit rate 10/second accept
    # Allow ICMP
    nft add rule inet wavelet input ip protocol icmp accept
    nft add rule inet wavelet input ip6 nexthdr icmpv6 accept
    # Allow DNS
    nft add rule inet wavelet input udp dport 53 accept
    nft add rule inet wavelet input tcp dport 53 accept
    # DHCP and PXE
    nft add rule inet wavelet input udp dport "{ 67,68 }" accept
    # NTP
    nft add rule inet wavelet input udp dport 123 accept
    # etcd (clients)
    nft add rule inet wavelet input ip saddr "$subNetCIDR" tcp dport "{ 2379,2380 }" accept
    # Registry
    nft add rule inet wavelet input ip saddr "$subNetCIDR" tcp dport 5000 accept
    # FreeIPA
    nft add rule inet wavelet input ip saddr "$subNetCIDR" udp dport "{ 88, 389, 636, 8822, 8823, 464 }" accept
    nft add rule inet wavelet input ip saddr "$subNetCIDR" tcp dport "{ 88, 389, 636, 8822, 8823, 464 }" accept
    # Nginx, Apache
    nft add rule inet wavelet input tcp dport "{ 80, 443, 8080, 8443 }" accept
    # UltraGrid streaming
    nft add rule inet wavelet input udp dport "{ 5004-5010, 3478-3480, 9800, 16384-16450, 30000-31000, 40000-40100 }" accept
    # RADSEC (RADIUS over TLS)
    nft add rule inet wavelet input tcp dport 2083 accept
    # Avahi (mDNS/DNS-SD for NDI discovery)
    nft add rule inet wavelet input udp dport 5353 accept
    nft add rule inet wavelet input udp dport 5354 accept
    nft add rule inet wavelet input udp dport 5355 accept
    # TFTP
    nft add rule inet wavelet input udp dport 69 accept
    # RTSP
    nft add rule inet wavelet input tcp dport 554 accept
    # NDI usage ports
    nft add rule inet wavelet input udp dport "{ 5960-6000 }" accept
    nft add rule inet wavelet input tcp dport "{ 5960-6000 }" accept
    # Log drops for debugging
    nft add rule inet wavelet input log prefix "WAVELET-INPUT: " level warn
    nft add rule inet wavelet input drop
}


####
#
# Main
#
####


# Note we have two logs, as sensitive secrets are handled in this script.
logName="/var/roothome/logs/hardening.log"
#debugLogName="/var/roothome/logs/hardening_debug.log"

exec > "$logName" 2>&1
hostNameSys="$SVR_HOSTNAME"
detect_self