#!/bin/bash
#	This module is concerned with implementing a freeIPA IdM along with RADIUS.
#	It will handle additional layers of network security and handle PKI and TLS certs for all of the appropriate web services
#	Web server configs will need to be modified, as will client spinup modules
#	This will take a lot of work and is adapted from several other online sources, then customized for Wavelet.


# 	Wavelet's security model is pretty simple;
#
#	*	Central FreeIPA IdM to handle machine accounts, service principals and certificates
#	*	RADIUS to provide an additional layer of network security given we are going over WiFi
#	*	Wifi Auth via EAP-TLS, requiring an already-enrolled certificate on the supplicant
#	*	administrative operations still protected with a sudo account
#	*	system should be properly segmented behind a proper security gateway allowing only control channels and/or http/https traffic for livestreaming
#


configure_idm(){
	# This will require a lot of trial and error to get it to spin up correctly.
	mkdir -p /var/home/wavelet/freeipa-data
	chown wavelet:wavelet /var/home/wavelet/freeipa-data
	echo -e "
[Container]
Image=quay.io/freeipa/freeipa-server:almalinux-9
ContainerName=freeipa
PublishPort=80:80
PublishPort=88:88
PublishPort=88:88/udp
PublishPort=123:123/udp
PublishPort=389:389
PublishPort=443:443
PublishPort=464:464
PublishPort=464:464/udp
PublishPort=636:636
EnvironmentFile=%h/.env.freeipa
Volume=freeipa-data:/data
AutoUpdate=registry
NoNewPrivileges=true

[Service]
Restart=always
RestartSec=5
TimeoutStartSec=300" > /home/users/wavelet/.config/systemd/users/freeipa.container
	echo -e "
# Remote: https://raw.githubusercontent.com/freeipa/freeipa-container/master/init-data
# ipa-server-install(1)

IPA_SERVER_IP=127.0.0.1
IPA_SERVER_HOSTNAME=svr.wavelet.local
IPA_SERVER_INSTALL_OPTS=--unattended --realm=WAVELET.LOCAL --ds-password=CHANGEME --admin-password=CHANGEME" > /var/home/wavelet/freeipa-data/.env.svr.wavelet.local
	systemctl --user daemon-reload
	systemctl --user enable freeipa.service --now
	if systemctl is-active --quiet freeipa.service; then
 		echo -e "FreeIPA configured!\n"
 	else
 		echo -e "FreeIPA provisioning failed!  Failing task..\n"
 		exit 0
 	fi
}

configure_freeradius(){
	# Pull RADIUS container as a quadlet, and utilize /etc/ confdir.  Conf files should be preconfigured from wavelet repo.
	git clone --depth=1 https://github.com/FreeRADIUS/freeradius-server/tree/v3.2.x/raddb
	cd radd
	# Note the service isn't enabled this time around.  It'll switch on next boot.
		echo -e "
[Container]
Image=freeradius/freeradius-server:latest
ContainerName=radius
PublishPort=1812-1813:1812-1813
PublishPort=1812-1813/udp:1812-1813/udp
Volume=/etc/raddb:/raddb
AutoUpdate=registry
NoNewPrivileges=true

[Service]
Restart=always
RestartSec=5
TimeoutStartSec=300" > /home/users/wavelet/.config/systemd/users/radius.container
	systemctl enable radius.service
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
	# Configure RADIUS service principal with some additional mods so it will auth utilizing the machine account using TTLS over EAP.
	# Uses wavelet user + pw over PAM rather than IPA/LDAP, since we aren't provisioning domain users here.

	#	check freeipa container has freeipa-server-trust-ad + ipa-adtrust-install
	#	ipa permission-add 'ipaNTHash service read' --attrs=ipaNTHash --type=user  --right=read
	#	ipa privilege-add 'Radius services' --desc='Privileges needed to allow radiusd servers to operate'
	#	ipa privilege-add-permission 'Radius services' --permissions='ipaNTHash service read' ?Don't need this, not doing user auth!
	#	ipa role-add 'Radius server' --desc="Radius server role"
	#	ipa role-add-privilege --privileges="Radius services" 'Radius server'
	ipa service-add "radius/`hostname`"
	ipa-getkeytab -p "radius/`hostname`" -s `hostname` -k /var/home/wavelet/radiusd.keytab
	kinit -t /var/home/wavelet/radiusd.keytab -k "radius/`hostname`"

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

	# Here we should do something to generate /etc/raddb from the container files

	# Get certificate for the IPA service principal.  This is all that's required, because radius should be configured to look here by default.
	ipa-getcert request -r -f /var/tmp/radius.pem -k /var/tmp/radius.key --principal=radius/`hostname`
	# Set SElinux contexts for these two files
	semanage fcontext -a -t cert_t --ftype -- "/etc/pki/tls/certs/radius.crt"
	semanage fcontext -a -t cert_t --ftype -- "/etc/pki/tls/certs/radius.key"
	restorecon -FvR /etc/pki/tls/certs/

	# Remove snake oil certs!
	rm -rf /etc/raddb/certs/*

	# OK.  Here is where we would work through the generated radius configuration files and appropriately customize them.
	# Process:
	#	Outer Tunnel request via EAP-TLS
	#	CA:	Domain CA
	#	Require client Certificate for identity, which is provisioned during client setup through IPA.
}

configure_client_hbac(){
	# If we need hbac/rbac stuff entered into freeIPA, we should accomplish that here
}

configure_additional_service(){
	# Intermediate CA from other upstream systems?
	# Any credentials-based services we might need logins for
	# Stuff I haven't yet though of here
}


####
#
# Main
#
####


exec >/home/wavelet/hardening.log 2>&1
systemctl enable --now certmonger
detect_self