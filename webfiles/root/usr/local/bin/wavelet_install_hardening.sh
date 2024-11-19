#!/bin/bash
#	This module is concerned with implementing a freeIPA IdM along with RADIUS.
#	It will handle additional layers of network security and handle PKI and TLS certs for all of the appropriate web services
#	Web server configs will need to be modified, as will client spinup modules
#	This will take a lot of work and is adapted from several other online sources, then customized for Wavelet.

#	Called during wavelet_installer setup, therefore with root privilege.  Dumps files in /var/ and /home/


# 	Wavelet's security model is pretty simple;
#
#	*	Central FreeIPA IdM to handle machine accounts, service principals and certificates
#	*	RADIUS to provide an additional layer of network security given we are going over WiFi
#	*	Wifi Auth via EAP-TLS, requiring an already-enrolled certificate on the supplicant
#	*	administrative operations still protected with a sudo account
#	*	system should be properly segmented behind a proper security gateway allowing only control channels and/or http/https traffic for livestreaming
#

detect_self(){
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME\n"
	case $UG_HOSTNAME in
	enc*)                   echo -e "I am an Encoder, this module should not be applicable at this stage in configuration!\n" && exit 0
	;;
	dec*)                   echo -e "I am a Decoder, this should be handled in wavelet_install_client.sh!" ; exit 0
	;;
	svr*)                   echo -e "I am a Server. Proceeding..."	;	event_server
	;;
	*)                      echo -e "This device Hostname is not set approprately, exiting \n" && exit 0
	;;
	esac
}

event_server(){
	if [[ -f /var/server.domain.enrollment.complete ]]; then
		echo -e "Domain enrollment is complete, testing for domain connectivity.."
		if $(echo $(cat /var/secrets/ipaadmpw.secure) | kinit admin); then
			echo "IPA Server is responding to kinit requests.. continuing.."
			configure_freeradius
			configure_etcd_certs
			configure_httpd_sp
			configure_nginx_sp
			configure_registry_sp
			configure_radius_sp
			configure_additional_service
		else
			echo -e "Domain controller is not responding to kerberos ticket requests, something may have gone wrong with installation!\n"
			echo -e "Check /var/freeipa-data/var/log files for more information, but this is likely something for the developer to look into.\n"
			exit 1
		fi
	else
		echo -e "\nThe domain controller has not yet been configured, proceeding..\n"
		configure_idm
	fi
}

configure_idm(){
	# Generate necessary data from the server's existing DNS configuration
	hostname=$(hostname)
	domain="$(dnsdomainname)"
	echo "${domain}" > /var/secrets/wavelet.domain
	echo "dc1.${domain}" > /var/secrets/wavelet.server
	ip=$(hostname -I | cut -d " " -f 1)
	directoryManagerPassword=$(cat /var/secrets/ipadmpw.secure)
	KRBDOMAIN=${domain^^}

	# note - password must be at least 8 chars long and should be prepopulated via install_wavelet_server.sh
	local administratorPassword=$(cat /var/secrets/ipaadmpw.secure)
	if [[ ${administratorPassword} == "DomainAdminPasswordGoesHere" ]]; then
		echo -e "\nThe domain administrator password doesn't appear to be set."
		echo -e "We will continue with a default password, but this default password is effectively public knowledge!\n"
	fi
	echo -e "Generated variables:\n Hostname:	${hostname}\n	Domain: ${domain}\n	Kerberos Domain:	${domain^^}\n"
	dcArray=()
	IFS="."
	echo -e "Reading array from ${hostname}\n"
	read -r -a dcArray <<< "${hostname}"
	echo -e "Array data:"
	for i in "${dcArray[@]}"; do
			printf "%s\t%s\n" "$i"
	done
	dn=${dcArray[0]} && echo -e "\nHost: ${dn}\n"
	tld=${dcArray[-1]} && echo -e "TLD is: .${tld}\n"
	ldap_dn="DN=${dn}"
	for ((i=1; i<${#dcArray[@]}; i++)); do
		ldap_dn="${ldap_dn},CN=${dcArray[i]}"
	done
	echo -e "LDAP DN Structure:\n${ldap_dn}\n"

	echo -e "Generating paths and quadlets..\n"
	mkdir -p /var/freeipa-data
	# This sets up the QUADLET to run freeipa, but it does not set the server itself up.
	# Port 953 needed for dynamic DNS updates
	echo -e "
[Container]
Image=quay.io/freeipa/freeipa-server:almalinux-9
ContainerName=freeipa
PublishPort=53:53
PublishPort=53:53/udp
PublishPort=80:80
PublishPort=88:88
PublishPort=88:88/udp
PublishPort=123:123/udp
PublishPort=389:389
PublishPort=443:443
PublishPort=464:464
PublishPort=464:464/udp
PublishPort=636:636
PublishPort=953:953
Volume=/var/freeipa-data:/data:z
HostName=dc1.${domain}
ReadOnly=true
AutoUpdate=registry
NoNewPrivileges=true

[Service]
Restart=always
RestartSec=5
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target" > /etc/containers/systemd/freeipa.container

	# First, we need to stop systemd-resolved, because it binds on port 53 and breaks the freeIPA container, despite configurations to not do so.  sigh.
	systemctl disable systemd-resolved --now
	systemctl disable dnsmasq.service --now
	# Switch dnsmasq DNS off and re-enable dnsmasq so that it now does NOT handle DNS at all.
	sed -i 's|#port=0|port=0|g' /etc/dnsmasq.conf
	systemctl enable dnsmasq.service --now
	# Here, we CONFIGURE the freeIPA instance
	podman run -h "dc1.${domain}" \
		--read-only \
		-v /var/freeipa-data:/data:Z \
		-e PASSWORD=${administratorPassword} \
		quay.io/freeipa/freeipa-server:almalinux-9 ipa-server-install -U --hostname=dc1.${domain} -r ${domain^^} \
		--ntp-pool=3.us.pool.ntp.org --setup-dns --no-hbac-allow --auto-forwarders --auto-reverse

	# Reload systemctl and start the container, we should now have a functional domain controller
	# Generate host record for dc1 in /etc/hosts, because until FreeIPA is up, we don't have any dns right now!
	echo -e "192.168.1.32 dc1.${domain} dc1" >> /etc/hosts
	systemctl daemon-reload
	systemctl start freeipa.service


	if systemctl is-active --quiet freeipa.service; then
		echo -e "FreeIPA configured and container is running!\n"
		echo -e "Enrolling server to freeIPA..\n"
		install_server_security_layer
	else
		echo -e "FreeIPA provisioning failed!  Failing task..\n"
		exit 0
	fi

	# Provision Dnsmasq DHCP server with a forward zone to FreeIPA
	sed -i "s|#IPA_ENTRY|server=/dc1.${domain}/${ip}|" /etc/dnsmasq.conf
	systemctl restart dnsmasq
}

install_server_security_layer(){
	user="domain_join"
	waveletDomain=$(dnsdomainname)
	waveletDCServer=dc1.$(dnsdomainname)
	waveletServer=$(hostname)
	directoryManagerPassword=$(cat /var/secrets/ipadmpw.secure)
	KRBDOMAIN=${domain^^}
	local administratorPassword=$(cat /var/secrets/ipaadmpw.secure)
	# The preferred mthod would be to run the ipa-client in a container, however there's no good (recent) documentation on this.
	# I opted to replace the nfs-utils-coreos package that was blocking freeipa-client installation so we are running this in the package overlay
	# Might break at some point..

	# We are doing the following;  creating an initial user who has domain join privileges
	# These credentials will be distributed during the initialization process on PXE boot and subsequently removed.
	ipa-client-install --unattended --principal=admin --password=${administratorPassword} --enable-dns-updates
		# These additional options might be needed but it would mean that DNS was broken on the system, we probably don't want them here.
		# --server ${waveletServer} --domain ${waveletDomain} --realm ${waveletDomain^^}
	echo ${administratorPassword} | kinit admin
	ipa user-add domain_join --random --first=domain --last=join > /var/secrets/domainEnrollment.password

	# Generate a tsig file for zone transfer from the DHCPD server to IPA's internal BIND.
	# or https://hub.docker.com/r/technitium/dns-server ? 
	# Ref https://www.freeipa.org/page/DHCP_Integration_Design
	#ddns-confgen -a hmac-sha512 \
	#-k ${waveletServer}. \
	#-s ${waveletDomain}. > /var/secrets/svr.tsig.key && \
	#echo $(cat /var/secrets/svr.tsig.key) >> /var/freeipa-data/etc/named.conf
	tsig-keygen -a hmac-sha512 svr.wavelet.local > /var/secrets/svr.tsig.key && echo $(cat /var/secrets/svr.tsig.key) >> /var/freeipa-data/etc/named.conf
	# Customize this for the domain in question
	ipa dnszone-mod ${waveletDomain}. --update-policy="grant ${waveletServer}. name ${waveletDomain}. ANY;"
	ipa dnszone-mod ${waveletDomain}. --dynamic-update=1
	# now DNS may be updated by executing nsupdate -k /var/secrets/svr.tsig.key from the dnsmasq script.
	touch /var/server.domain.enrollment.complete
	# Need this file in /var/tmp so dnsmasq knows to update BIND instead of itself!
	cp /var/tmp/prod.security.enabled /var/tmp
}

configure_freeradius(){
	# Pull RADIUS container as a quadlet, Conf files should probably be preconfigured from wavelet repo.
	# Note the service isn't enabled this time around.  It'll switch on next boot.
	mkdir -p /etc/raddb
	# This dockerfile is adapted from the freeradius official git, and contains an additional step
	# The step copies the config files onto the host.  We will then modify them.  
	# This takes a while, but I noted the FreeRADIUS conf files have an ID field and probably other data which we might want to preserve.
	podman build -t localhost/freeradius \
	-v=/etc/raddb/:/mount:z \
	-f /var/home/wavelet/containerfiles/Containerfile.freeradius-build
	# Now we pull an official freeRADIUS container from docker hub and push it to the local registry
	podman push docker.io/freeradius/freeradius-server 192.168.1.32:5000/freeradius --tls-verify=false
		echo -e "
[Container]
Image=${ip}:5000/freeradius
ContainerName=radius
PublishPort=1812-1813:1812-1813/tcp
PublishPort=1812-1813:1812-1813/udp
Volume=/etc/raddb:/etc/raddb
Volume=/etc/ipa:/etc/ipa
Volume=/etc/pki/tls/certs:/etc/pki/tls/certs
AutoUpdate=registry
NoNewPrivileges=true

[Service]
Restart=always
RestartSec=5
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target" > /etc/containers/systemd/radiusd.container
	systemctl daemon-reload	
}

configure_etcd_certs(){
	# Configure ETCD service principal within freeIPA and tell ETCD to monitor for the appropriate certificate
	ipa service-add etcd/`hostname`
	ipa service-add-host --hosts=dc1.$(dnsdomainname) etcd/`hostname`
	ipa-getcert request \
		-f /etc/pki/tls/certs/etcd.crt \
		-k /etc/pki/tls/private/etcd.key \
		-K etcd/svr.wavelet.local
	echo -e "TLS Certificate for Etcd generated.\n"
	echo -e "Reconfiguring Etcd to utilize certificate...\n"
	# sed the systemd file and add appropriate TLS settings here
	# we may need to generate a .pem base64 file from the crt files to utilize here.
	#	https://stackoverflow.com/questions/991758/how-to-get-pem-file-from-key-and-crt-files
	#	openssl x509 -inform DER -outform PEM -in server.crt -out server.crt.pem
	#	cat server.crt server.key > server.includesprivatekey.pem
	#
	#--client-cert-auth \
	#--trusted-ca-file /etc/ipa/ca/ipa.crt \
	#--cert-file /etc/pki/tls/certs/etcd.crt \
	#--key-file /etc/pki/tls/certs/etcd.key \
	#--peer-client-cert-auth \
	#--peer-trusted-ca-file /etc/ipa/ca/ipa.crt \
	#--peer-cert-file /etc/pki/tls/certs/etcd.crt \
	#--peer-key-file /etc/pki/tls/certs/etcd.key \
	#--auto-compaction-retention 1"
}

configure_httpd_sp(){
	# Configure Apache service principal
	# we might need to do something with cred files for the passwords etc. here, needs testing.
	ipa service-add http/`hostname`
	ipa service-add-host --hosts=dc1.$(dnsdomainname) http/`hostname`
	ipa-getcert request \
		-f /etc/pki/tls/certs/httpd.crt \
		-k /etc/pki/tls/private/httpd.key \
		-K http/`hostname`
	echo -e "TLS Certificate for web services generated.\n"
	echo -e "Reconfiguring httpd to utilize certificate...\n"
	# Configure Apache service principal within freeIPA and tell Apache to monitor for the appropriate certificate
	# Pull httpd.conf out of the container
	podman run --rm httpd:2.4 cat /usr/local/apache2/conf/httpd.conf > custom-httpd.conf
	# Put the secure conf file in place
		cp /var/home/wavelet/config/httpd.secure.conf  /var/home/wavelet/config/httpd.conf
	# Add httpd.conf volume to the httpd quadlet, this file will now be mounted from the host to the container directly.
	# Add the certificates to the httpd quadlet.  This will almost certainly require doing something nasty with SElinux..
	sed -i \
		-e 's|#cert|Volume=/etc/pki/tls/certs/httpd.crt:/usr/local/apache2/conf/httpd.crt:z' \
		-e 's|#key|Volume=/etc/pki/tls/certs/httpd.key:/usr/local/apache2/conf/httpd.key:z' \
		/var/home/wavelet/.config/systemd/users/httpd.container
	# And here's the something nasty.  I can't say I'm much of a fan of allowing container access to the private keys.  Is there a better way to do this?
	semanage fcontext -a -t cert_t --ftype -- "/etc/pki/tls/certs/httpd.crt"
	semanage fcontext -a -t cert_t --ftype -- "/etc/pki/tls/certs/httpd.key"
	restorecon -FvR /etc/pki/tls/certs/
}

configure_nginx_sp(){
	echo -e "Re-utilizing the httpd certificate for Nginx services...\n"
	# Reconfigure the nginx quadlet to look for the httpd certificates
		sed -i \
		-e 's|listen   80; #TLS|""' \
		-e 's|#TLS|""' \
		/var/home/wavelet/http-php/nginx/nginx.conf
}

configure_registry_sp(){
	echo -e "Re-utilizing the httpd certificate for Registry services...\n"
	# Reconfigure the registry systemd unit to look for the httpd certificates
}

configure_radius_sp(){
	#	Configure FreeRADIUS in /etc/raddb along with a domain service principal with some additional mods.
	#	It will auth utilizing the machine account using EAP-TTLS.

	ipa service-add radius/`hostname`
	ipa service-add-host --hosts=dc1.$(dnsdomainname) radius/`hostname`
	ipa-getcert request \
		-f /etc/pki/tls/certs/radius.crt \
		-k /etc/pki/tls/private/radius.key \
		-K radius/`hostname`

	# Set SElinux contexts for these two files
	semanage fcontext -a -t cert_t --ftype "/etc/pki/tls/certs/radius.crt"
	semanage fcontext -a -t cert_t --ftype "/etc/pki/tls/certs/radius.key"
	restorecon -FvR /etc/pki/tls/certs/

	# Might need this for EAP-TTLS
	# Generate the outer tunnel openSSL certificate CA
	#sed -i 's|input_password|${outerCAInputPassword}|g' /etc/raddb/certs/ca.cnf
	#sed -i 's|output_password|${outerCAOutputPassword}|g' /etc/raddb/certs/ca.cnf
	#sed -i 's|[certificate_authority]|${outerCACertificateAuthoritySection}|g' /etc/raddb/certs/ca.cnf
	#make ca.pem
	# Same for server
	#sed -i 's|input_password|${outerCAInputPassword}|g' /etc/raddb/certs/server.cnf
	#sed -i 's|output_password|${outerCAOutputPassword}|g' /etc/raddb/certs/server.cnf
	#sed -i 's|[certificate_authority]|${outerCACertificateAuthoritySection}|g' /etc/raddb/certs/server.cnf
	#make server
	# Finally for Clien*T* - the outer tunnel will use the client certificate as a PSK
	#sed -i 's|input_password|${outerCAInputPassword}|g' /etc/raddb/certs/client.cnf
	#sed -i 's|output_password|${outerCAOutputPassword}|g' /etc/raddb/certs/client.cnf
	#sed -i 's|[certificate_authority]|${outerCACertificateAuthoritySection}|g' /etc/raddb/certs/client.cnf
	#make client

	# OK.  Here is where we would work through the generated radius configuration files and appropriately customize them.
	# Process:
	#	Outer Tunnel request with pre-made certificates above stored in /etc/raddb/certs
	#	Inner Tunnel request with domain certificates:
	#		CA:	Domain CA
	#		Client Cert:  Radius opens LDAP connection, reads machine certificate for the supplicant hostname and accepts/rejects

	echo -e "
# Wavelet NAS
client AP_$(dnsdomainname) {
	ipaddr							=	${AccessPointIPAddress}
	proto							=	*
	secret							=	${AccessPointSecret}
	require_message_authenticator 	=	no
	nas_type						=	other" >> /etc/raddb/clients.conf


	# We will need the following files configured appropriately for the wavelet installation:
	#	Suggest creating appropriate template files and embedding with Ignition, then utilizing stream editor to populate
	#	/etc/raddb/mods-enabled/eap
	#	/etc/raddb/mods-enabled/inner-eap	
	#	/etc/raddb/mods-enabled/ldap
	#	/etc/raddb/mods-enabled/krb5 ?
	#	/etc/raddb/mods-enabled/realm ?
	#	/etc/raddb/mods-enabled/utf8 ?

	#	/etc/raddb/sites-enabled/default
	#	/etc/raddb/sites-enabled/inner_tunnel
	#	/etc/raddb/sites-enabled/check-eap-tls
	
	#	/etc/raddb/clients.conf
	#	/etc/raddb/panic.gdb
	#	/etc/raddb/huntgroups
	#	/etc/raddb/hints
	#	/etc/raddb/dictionary
	#	/etc/raddb/radiusd.conf

	#	This would generate wavelet's dummy or outer-tunnel certificates for initial connection
	#	/etc/raddb/certs/inner_server.cnf
	#	/etc/raddb/certs/Makefile
	#	/etc/raddb/certs/passwords.mk
}

configure_client_hbac(){
	# If we need hbac/rbac stuff entered into freeIPA, we should accomplish that here
}

configure_additional_service(){
	# Intermediate CA from other upstream systems?
	# Any credentials-based services we might need logins for
	# Stuff I haven't yet though of here

	# rkhunter propupd set for system files and configure a daily cron job for scanning and upstream notification
	echo -e "
#!/bin/sh
   (
    #/usr/local/bin/rkhunter --versioncheck
    #/usr/local/bin/rkhunter --update
    /usr/local/bin/rkhunter --cronjob --report-warnings-only
   ) #| /bin/mail -s 'rkhunter Daily Run (PutYourServerNameHere)' your@email.com" > /etc/cron.daily/rkhunter.sh
	rkhunter --update
	rkhunter --propupd

	# Freshclam and ClamAV scans on off hours?
}


####
#
# Main
#
####


exec >/home/wavelet/hardening.log 2>&1
#	Certmonger is in the container though?
#systemctl enable --now certmonger
detect_self