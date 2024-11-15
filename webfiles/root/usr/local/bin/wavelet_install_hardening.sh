#!/bin/bash
#	This module is concerned with implementing a freeIPA IdM along with RADIUS.
#	It will handle additional layers of network security and handle PKI and TLS certs for all of the appropriate web services
#	Web server configs will need to be modified, as will client spinup modules
#	This will take a lot of work and is adapted from several other online sources, then customized for Wavelet.

#	Called during wavelet_installer setup, therefore with root privilege.  Dumps files in /var/home/wavelet-root


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
	enc*)                   echo -e "I am an Encoder, this module is not applicable.\n" && exit 0
	;;
	dec*)                   echo -e "I am a Decoder, this module is not applicable." && exit 0
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
	domain=$(dnsdomainname)
	echo "${domain}" > /var/secrets/wavelet.domain
	echo "dc1.${domain}" > /var/secrets/wavelet.server
	ip=$(hostname -I | cut -d " " -f 1)
	# note - password must be at least 8 chars long and should be prepopulated via install_wavelet_server.sh
	administratorPassword=$(cat /var/secrets/ipaadmpw.secure)
	if [[ ${administratorPassword} == "DomainAdminPasswordGoesHere" ]]; then
		echo -e "\nThe domain administrator password doesn't appear to be set.  We will continue, but this password is effectively public knowledge..\n"
	fi
	directoryManagerPassword=$(cat /var/secrets/ipadmpw.secure)
	KRBDOMAIN=${domain^^}
	echo -e "Generated variables:\n Hostname:       ${hostname}\n   Domain: ${domain}\n     Kerberos Domain:        ${KRBDOMAIN}\n"
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
# Note we are remapping port 80 to port 8180 and port 443 to port 843 to free up the HTTP ports for nginx/wavelet UI!
	echo -e "
[Container]
Image=quay.io/freeipa/freeipa-server:almalinux-9
ContainerName=freeipa
PublishPort=8180:80
PublishPort=88:88
PublishPort=88:88/udp
PublishPort=123:123/udp
PublishPort=389:389
PublishPort=8443:443
PublishPort=464:464
PublishPort=464:464/udp
PublishPort=636:636
Volume=/var/freeipa-data:/data:Z
HostName=dc1.${domain}
AutoUpdate=registry
NoNewPrivileges=true

[Service]
Restart=always
RestartSec=5
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target" > /etc/containers/systemd/freeipa.container

	# Here, we CONFIGURE the freeIPA instance
	podman run -h "dc1.${domain}" --read-only \
		-v /var/freeipa-data:/data:Z \
		-e PASSWORD=${administratorPassword} \
		quay.io/freeipa/freeipa-server:almalinux-9 ipa-server-install -U -r ${KRBDOMAIN}

	# Maybe not needed given we just did this with the command above?
	# Set .env file for freeIPA configuration
	# curl this # Remote: https://raw.githubusercontent.com/freeipa/freeipa-container/master/init-data /var/freeipa-data
	echo -e "
# Remote: https://raw.githubusercontent.com/freeipa/freeipa-container/master/init-data
ipa-server-install
IPA_SERVER_IP=${ipAddress}
IPA_SERVER_HOSTNAME="dc1.${domain}"
IPA_SERVER_INSTALL_OPTS=--unattended \
--realm=${KRBDOMAIN} \
--ds-password=${directoryManagerPassword} \
--admin-password=${administratorPassword}" > /var/freeipa-data/.env.freeipa
	
	# Reload systemctl and start the container
	systemctl daemon-reload
	systemctl enable freeipa.service --now

	if systemctl is-active --quiet freeipa.service; then
		echo -e "FreeIPA configured and container is running!\n"
		echo -e "Performing initial host enrollment..\n"
		# We are doing the following;  creating an initial user who has domain join privileges
		# These credentials will be distributed during the initialization process on PXE boot and subsequently removed.
		podman exec freeipa "echo ${administratorPassword} | kinit admin"
		podman exec freeipa "ipa user-add domain_join --random --first=domain --last=join > data/output.txt"
		echo -e "$(cat /var/freeipa-data/output.txt | grep "Random password:" | cut -d ' ' -f 5)" > /var/secrets/domainEnrollment.password
		rm -rf /var/freeipa-data/output.txt
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
		password=$(cat /var/secrets/domainEnrollment.password)
		user="domain_join"
		waveletDomain=$(cat /var/secrets/wavelet.domain)
		waveletServer=$(cat /var/secrets/wavelet.server)
		rm -rf /var/secrets/domainEnrollment.password
		ipa-client-install --principal ${user} --password "${domainJoinPassword}" --domain ${waveletDomain} --server ${waveletServer} --unattended
		# In order to further configure services, we will need to reboot the server.
		touch /var/server.domain.enrollment.complete
		systemctl reboot
}

configure_freeradius(){
	# Pull RADIUS container as a quadlet, Conf files should probably be preconfigured from wavelet repo.
	# Note the service isn't enabled this time around.  It'll switch on next boot.
		echo -e "
[Container]
Image=docker.io/freeradius/freeradius-server:latest
ContainerName=radius
PublishPort=1812-1813:1812-1813/tcp
PublishPort=1812-1813:1812-1813/udp
Volume=/etc/raddb:/raddb
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
	ipa-getcert request \
		-f /etc/pki/tls/certs/etcd.crt \
		-k /etc/pki/tls/private/etcd.key \
		-K ETCD/svr.wavelet.local
		-D svr.wavelet.local
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
	ipa-getcert request \
		-f /etc/pki/tls/certs/httpd.crt \
		-k /etc/pki/tls/private/httpd.key \
		-K HTTP/`hostname`
		-D `hostname`
	echo -e "TLS Certificate for web services generated.\n"
	echo -e "Reconfiguring httpd to utilize certificate...\n"
	# Configure Apache service principal within freeIPA and tell Apache to monitor for the appropriate certificate
	# Pull httpd.conf out of the container
	podman run --rm httpd:2.4 cat /usr/local/apache2/conf/httpd.conf > custom-httpd.conf
	# modify the conf file to enable SSL/TLS
	sed -i \
		-e 's/^#\(Include .*httpd-ssl.conf\)/\1/' \
		-e 's/^#\(LoadModule .*mod_ssl.so\)/\1/' \
		-e 's/^#\(LoadModule .*mod_socache_shmcb.so\)/\1/' \
		/var/home/wavelet/custom-httpd.conf
	# Add httpd.conf volume to the httpd quadlet, this file will now be mounted from the host to the container directly.
	# Add the certificates to the httpd quadlet.  This will almost certainly require doing something nasty with SElinux..
	sed -i \
		-e 's|#conf|Volume=/home/wavelet/custom-httpd.conf:/usr/local/apache2/conf/httpd.conf:z' \
		-e 's|#cert|Volume=/etc/pki/tls/certs/httpd.crt:/usr/local/apache2/conf/httpd.crt:z' \
		-e 's|#key|Volume=/etc/pki/tls/certs/httpd.key:/usr/local/apache2/conf/httpd.key:z' \
		/var/home/wavelet/.config/systemd/users/httpd.container
	# And here's the something nasty.  I can't say I'm much of a fan of allowing access to the private keys.  Is there a better way to do this?
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


	# NOT NEEDED	ipa permission-add 'ipaNTHash service read' --attrs=ipaNTHash --type=user  --right=read
	#	ipa privilege-add 'Radius services' --desc='Privileges needed to allow radiusd servers to operate'
	# NOT NEEDED	ipa privilege-add-permission 'Radius services' --permissions='ipaNTHash service read'
	#	ipa role-add 'Radius server' --desc="Radius server role"
	#	ipa role-add-privilege --privileges="Radius services" 'Radius server'
	ipa service-add "radius/`hostname`"
	# PROBABLY NOT NEEDED ipa-getkeytab -p "radius/`hostname`" -s `hostname` -k /var/home/wavelet/radiusd.keytab
	# PROBABLT NOT NEEDED kinit -t /var/home/wavelet/radiusd.keytab -k "radius/`hostname`"

	# Here we need some logic to generate a valid radius password, get the hostname
	# we need to generate an all uppercase domain from the hostname
	# we need to generate foreach DC= entries appropriately for the DN.. probably a while read . delimited foreach thing?

	echo -e "
# LDIF example from https://firstyear.id.au/blog/html/2015/07/06/FreeIPA:_Giving_permissions_to_service_accounts..html

dn: krbprincipalname=radius/`hostname`@${KRBDOMAIN},cn=services,cn=accounts,dc=${dc1},dc=${dc2},dc=${dc3}
changetype: modify
add: objectClass
objectClass: simpleSecurityObject
-
add: userPassword
userPassword: ${radiusPassword}
" > radius.ldif
	# probably need to page in DM password here?
	ldapmodify -f radius.ldif -D 'cn=Directory Manager' -W -H ldap://`hostname` -Z
	echo -e "
dn: cn=adtrust agents,cn=sysaccounts,cn=etc,dc=${dc1},dc=${dc2},dc=${dc3}
changetype: modify
add: memberUid
memberUid: krbprincipalname=radius/`hostname`@${KRBDOMAIN},cn=services,cn=accounts,dc=${dc1},dc=${dc2},dc=${dc3}
" > adtrust.ldif
	ldapmodify -f adtrust.ldif -D 'cn=Directory Manager' -W -H ldap://`hostname` -Z

	# Get certificate for the IPA service principal.  This is all that's required, because radius should be configured to look here by default.
	ipa-getcert request -r -f /var/tmp/radius.pem -k /var/tmp/radius.key --principal=radius/`hostname`
	# Set SElinux contexts for these two files
	semanage fcontext -a -t cert_t --ftype -- "/etc/pki/tls/certs/radius.crt"
	semanage fcontext -a -t cert_t --ftype -- "/etc/pki/tls/certs/radius.key"
	restorecon -FvR /etc/pki/tls/certs/

	# Generate the outer tunnel openSSL certificate CA
	sed -i 's|input_password|${outerCAInputPassword}|g' /etc/raddb/certs/ca.cnf
	sed -i 's|output_password|${outerCAOutputPassword}|g' /etc/raddb/certs/ca.cnf
	sed -i 's|[certificate_authority]|${outerCACertificateAuthoritySection}|g' /etc/raddb/certs/ca.cnf
	make ca.pem
	# Same for server
	sed -i 's|input_password|${outerCAInputPassword}|g' /etc/raddb/certs/server.cnf
	sed -i 's|output_password|${outerCAOutputPassword}|g' /etc/raddb/certs/server.cnf
	sed -i 's|[certificate_authority]|${outerCACertificateAuthoritySection}|g' /etc/raddb/certs/server.cnf
	make server
	# Finally for Clien*T* - the outer tunnel will use the client certificate as a PSK
	sed -i 's|input_password|${outerCAInputPassword}|g' /etc/raddb/certs/client.cnf
	sed -i 's|output_password|${outerCAOutputPassword}|g' /etc/raddb/certs/client.cnf
	sed -i 's|[certificate_authority]|${outerCACertificateAuthoritySection}|g' /etc/raddb/certs/client.cnf
	make client

	# OK.  Here is where we would work through the generated radius configuration files and appropriately customize them.
	# Process:
	#	Outer Tunnel request with pre-made certificates above stored in /etc/raddb/certs
	#	Inner Tunnel request with domain certificates:
	#		CA:	Domain CA
	#		Client Cert:  Radius opens LDAP connection, reads machine certificate for the supplicant hostname and accepts/rejects

	mkdir -p /etc/raddb/sites-enabled
	mkdir -p /etc/raddb/mods-enabled

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