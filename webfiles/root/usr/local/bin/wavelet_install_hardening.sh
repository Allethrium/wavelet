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
			echo "This is likely going to be a complex issue that is not easily resolvable."
			echo -e "Check /var/freeipa-data/var/log files for more information, but this is likely something for the developer to look into.\n"
			exit 1
		fi
	else
		echo -e "\nThe domain controller has not yet been configured, proceeding to spin up the container..\n"
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
	local directoryManagerPassword=$(cat /var/secrets/ipadmpw.secure)
	KRBDOMAIN=${domain^^}
	gateway=$(read _ _ gateway _ < <(ip route list match 0/0); echo "$gateway")
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

	# This block should generate an intelligent subnet for the freeipa container based off the server's current values

	# Pull config data that should have been prepopulated with install_wavelet_server.sh during initial configuration
	# Compare against current network environment
	# Look for authoritative DHCP/DNS servers

	# Calculate subnets (we need only four addresses, really)
	# Probably not the most elegant approach :|
	# What we're doing is finding the current subnet, 
	# subtracting four addresses and effectively putting the wavelet domain subnet at the end of the current subnet range.
	currentIPCIDR=$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | head -n 1)
	childSubnetCIDR="/28"
	childSubnetCIDRHosts="14"
	currentSubnet=$(ipcalc ${currentIPCIDR} | sed -n '2p')
	childSubnetMaxAddr=$(ipcalc ${currentIPCIDR} --maxaddr)
	childSubnetClean=$(echo ${childSubnetMaxAddr##*=})
	childSubnetNetworkAddr=$(echo ${childSubnetClean%.*}.)
	childSubnetLastOctet=$(echo ${childSubnetClean##*.})
	# We don't want to eat the existing subnet's broadcast address..
	childSubnetRangeStart=$(( ${childSubnetLastOctet} - $(( 14 * 2 )) ))
	IPAServerHostIP=$(( ${childSubnetRangeStart} + 1 )) ; IPAServerHostIP="${childSubnetNetworkAddr}${IPAServerHostIP}"
	hostLinkIP=$(( ${childSubnetRangeStart} + 2 )) ; hostLinkIP="${childSubnetNetworkAddr}${hostLinkIP}"
	echo -e "\n\nGenerated subnet is:\n$(ipcalc "${childSubnetNetworkAddr}${childSubnetRangeStart}${childSubnetCIDR}")"
	ipaSubnetArg=$(ipcalc "${childSubnetNetworkAddr}${childSubnetRangeStart}${childSubnetCIDR}" | sed -n 2p | awk '{ print $2 }')
	echo -e "\nIPA Server will be granted IP Address:\n${IPAServerHostIP}"
	echo -e "\nAn additional IP link will be generated with the arguments:\nip link add ipa_ipvlan_shim link ${active_networkInterface} type ipvlan mode l2\nip addr add ${hostLinkIP} dev ipa_ipvlan_shim\nip link set ipa_ipvlan_shim up\nip route add ${childSubnetNetworkAddr}${childSubnetRangeStart} dev ipa_ipvlan_shim"


	# TODO
	# if configured_subnets match discovered subnets; then
	#		echo -e "Configured subnet matches host subnet, proceeding"
	# else
	# 	echo -e "Wavelet's subnet configuration has changed.\nIf you want to install this system on a pre-existing network or drastically alter the underlying network configuration, it is highly recommended to reprovision the system from the beginning!\n"
	#	  exit 1
	# fi

	# TODO 
	# IPv6? @_@  To be honest getting a real handle on that would likely invalidate all of the above work.


	echo -e "Generating paths and quadlets..\n"
	mkdir -p /var/freeipa-data
	# This sets up the QUADLET to run freeipa, but it does not set the server itself up.
	# Port 953 needed for dynamic DNS updates
	#	Run iplink_up.sh to activate the generated shim to that we can talk to the container from the server.
	echo -e "[Container]
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
HostName=dc1.ipa.$(dnsdomainname)
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
ExecStartPost=-/usr/bin/bash -c "/usr/local/bin/iplink_up.sh"

[Install]
WantedBy=multi-user.target" > /etc/containers/systemd/freeipa.container

	# Here, we CONFIGURE the freeIPA instance
	# Note that no forwarders are configured.  We can add one later if we need that functionality but for now this is an isolated DNS zone.
	# We will force populate appropriate zones later on in setup after the svr.wavelet client is configured.
	# There is a ridiculously long delay after installation whilst it does a bunch of DNS nonsense...

	# we are going to do horrible things with dns.
	# Quick explanation;
	# We want the freeIPA internal DNS server (BIND) to handle dns resolution for the wavelet domain
	# There is one caveat - the entire security layer will need to be re-installed if at some point the domain name changes to a valid TLD
	# So we need to engineer a switch here, or provide a module to deprovision the security layer gracefully if we want to eventually hook the system in to a larger network with authoritative DNS.
	# --allow-zone-overlap is enabled so we can play nice with the existing dnsmasq DNS server
	# First we create a new ipvlan podman network so we can get another IP address.
	active_networkInterface=$(ip route get 8.8.8.8 | sed -nr 's/.*dev ([^\ ]+).*/\1/p')

	# These commands perform the following (evil) tasks:
	#		Creates a podman network in the same subnet as the physical network
	#		generates a "shim" ipvlan device and assigns an IP address to it
	#		force-adds a route to that the container and the host can now communicate
	#		Without this the controller wouldn't be able to function without moving the entirety into a container itself
	#		We might want to actually do this with macvlan after all.  
	podman network create -d ipvlan --subnet ${currentIPCIDR} --gateway ${gateway} --ip-range ${ipaSubnetArg} ipa_ipvlan -o parent=${active_networkInterface}

	iplink_create_ipvlan(){
		# Can't use nmcli - no ipvlan support until patch lands in fedora repo: 
		# https://gitlab.freedesktop.org/NetworkManager/NetworkManager/-/commit/d238ff487b29a50ca346f906b2a158c692ff8864
		# So problem.. on reboot, the link doesn't work and therefore the server is unpingable.  We would have to perform this every reboot..
		ip link add ipa_ipvlan_shim link ${active_networkInterface} type ipvlan mode l2
		ip addr add ${hostLinkIP}/32 dev ipa_ipvlan_shim 
		ip link set ipa_ipvlan_shim up
		ip route add ${ipaSubnetArg} dev ipa_ipvlan_shim
		if ping dc1; then
			echo -e "Container up and ping is successful, generating rootful service to create ip link shim on every reboot..\n"
			echo "ip link add ipa_ipvlan_shim link ${active_networkInterface} type ipvlan mode l2
ip addr add ${hostLinkIP}/32 dev ipa_ipvlan_shim 
ip link set ipa_ipvlan_shim up
ip route add ${ipaSubnetArg} dev ipa_ipvlan_shim" > /usr/local/bin/iplink_up.sh; chmod +x /usr/local/bin/iplink_up.sh
			echo "[Unit]
Description=Run IP Routing to ipvlan container on boot
After=network-online.target
Wants=freeipa.service
[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c "/usr/local/bin/iplink_up.sh"
[Install]
WantedBy=multi-user.target" > /etc/systemd/system/wavelet_ipvlan_shim.service
			systemctl daemon-reload
			systemctl enable wavelet_ipvlan_shim.service
		else
			echo -e "Container is unpingable, there may be an error."
			# Do remedial stuff here
		fi
	}

	nmcli_create_macvlan(){
		podman network create -d macvlan -o parent=enp1s0f0np0 ipa_macvlan
		# Doesn't seem to work
		nmcli con add type macvlan dev ${active_networkInterface} mode bridge tap yes ifname ipa con-name ipa ip4 0.0.0.0/24
		nmcli con mod macvlan-ipa ipv6.method "disabled"
		nmcli con mod macvlan-ipa ipv4.method "disabled"
		nmcli con mod macvlan-ipa	+ipv4.routes "${hostLinkIP}/32"
		nmcli con up macvlan-ipa
	}
 

	# Quick container command to test this, just try to ping the svr.wavelet.local host:
	# podman run -it --network=ipa_ipvlan alpine:latest /bin/sh
	# If ping successful (and vice versa) the IPA container should now have no problem communicating with host.

	echo -e "${IPAServerHostIP}	dc1.ipa.${domain} dc1" >> /etc/hosts

	# Generate host record for dc1 in /etc/hosts, because until FreeIPA is up, we don't have any dns right now!
	echo -e "192.168.1.32 dc1.${domain} dc1" >> /etc/hosts

	# Even though the files in /etc/systemd/resolved.conf.d SHOULD override systemd's behavior... it ignores them.
	# We do this to stop systemd-resolved binding on port 53, which will prevent freeipa.service from coming up.
	systemctl disable dnsmasq.service --now
	# Switch dnsmasq DNS off and re-enable dnsmasq so that it now does NOT handle DNS at all.  May not be needed with allow-zone-overlap on IPA.
	sed -i 's|#port=0|port=0|g' /etc/dnsmasq.conf
	# systemctl enable dnsmasq.service --now
	systemctl daemon-reload

	# We might want to run this in a subshell because it doesn't seem to terminate after completion.
	podman pull quay.io/freeipa/freeipa-server:almalinux-9
	podman run -h "dc1.ipa.${domain}" \
		--name freeipa_dc1_install \
		--read-only \
		--ip=${IPAServerHostIP} \
		--network=ipa_ipvlan \
		--dns=127.0.0.1 \
		-h=dc1.ipa.${domain} \
		-v /var/freeipa-data:/data:Z \
		-e PASSWORD=${administratorPassword} \
		quay.io/freeipa/freeipa-server:almalinux-9 ipa-server-install -U --domain=ipa.${domain} -r IPA.${domain^^} \
		--ntp-pool=3.us.pool.ntp.org --setup-dns --no-hbac-allow --auto-forwarder --allow-zone-overlap --auto-reverse --setup-adtrust &

		# We don't need port arguments now that the container has its own IP address via ipvlan, right?
 		# -p 53:53/udp -p 53:53 -p 389:389 -p 636:636 -p 88:88/udp -p 464:464/udp -p 464:464 -p 123:123/udp
 	# It takes approximately five minutes to spin up the container
 	sleep 300
	echo -e "
acl "wavelet_network" {
  127.0.0.1;
  192.168.1.0/24;
};" >> /var/freeipa-data/etc/named/ipa-ext.conf
	echo -e "
allow-recursion { wavelet_network; };" >> /var/freeipa-data/etc/named/ipa-options-ext.conf
	systemctl start freeipa.service

	# Here we will need to reconfigure systemd-resolved or it will break the container and prevent freeIPA from resolving hostnames because port53.
	echo -e "
[Resolve]
DNSStubListener=no" > /etc/systemd/resolved.conf
	systemctl restart systemd-resolved.service
	# Generate an appropriate file for systemd-resolved to try to ignore and make a dog's dinner of (I hate that thing)
	echo -e "
[Main]
dns=default

[global-dns]
searches=ipa.${domain}

[global-dns-domain-*]
servers=${IPAServerHostIP}" > /etc/NetworkManager/conf.d/123-ipa.conf
	echo -e "DNS=${IPAServerHostIP}, ${gateway}
Domains=~. {searchdomains}" > /etc/systemd/resolved.conf.d/dns_servers.conf
	systemctl daemon-reload
	systemctl restart systemd-resolved.service --now
	resolvectl dns ${active_networkInterface} ${IPAServerHostIP}
	resolvectl domain ${active_networkInterface} ipa.${domain}


	if systemctl is-active --quiet freeipa.service; then
		echo -e "FreeIPA configured and container is running!\n"
		echo -e "Enrolling server to freeIPA..\n"
		install_server_security_layer
	else
		echo -e "FreeIPA provisioning failed!  Failing task..\n"
		exit 0
	fi
	systemctl restart dnsmasq
}

install_server_security_layer(){
	user="domain_join"
	waveletDomain=ipa.$(dnsdomainname)
	waveletDCServer=dc1.ipa.$(dnsdomainname)
	waveletServer=$(hostname)
	directoryManagerPassword=$(cat /var/secrets/ipadmpw.secure)
	KRBDOMAIN=${waveletDomain^^}
	local administratorPassword=$(cat /var/secrets/ipaadmpw.secure)

	# The preferred method would be to run the ipa-client in a container, however there's no good (recent) documentation on this.
	# I opted to replace the nfs-utils-coreos package that was blocking freeipa-client installation so we are running this in the package overlay
	# Package does not seem to create directories, so we do it manually
	mkdir -p /var/lib/ipa-client/{pki,sysrestore,certmonger}
	# Run in a subshell or it gets a little stuck..
	# We define the server's IP address here during install, or we waste a lot of time with DNS queries
	ipa-client-install --unattended --principal=admin --ip-address=$(hostname -I | cut -d " " -f 1) --password=${administratorPassword} --enable-dns-updates --ssh-trust-dns --server=${waveletDCServer} --domain=${waveletDomain} &
	# These additional options might be needed but it would mean that DNS was broken on the system, we probably don't want them here.
	# --server ${waveletServer} --domain ${waveletDomain} --realm ${waveletDomain^^}
	# We are doing the following;  creating an initial user who has domain join privileges
	# These credentials will be distributed during the initialization process on PXE boot and subsequently removed.
	echo ${administratorPassword} | kinit admin


	ipa user-add domain_join --random --first=domain --last=join > /var/secrets/domainEnrollment.password

	# Generate a tsig file for zone transfer from the dnsmasq/DHCPD server to IPA's internal BIND.
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
	ipa service-add-host --hosts=dc1.ipa.$(dnsdomainname) etcd/`hostname`
	# Configure the system certificate store for the ETCD service principal
	ipa-getcert request \
		-f /etc/pki/tls/certs/etcd.crt \
		-k /etc/pki/tls/private/etcd.key \
		-K etcd/svr.wavelet.local \
		-D wavelet.local
	echo -e "TLS Certificate for Etcd generated.\n"

	#	We now need to generate some certificates which the wavelet user should be able to access in order to use etcdctl
	# OR DO WE?
	# Ref; https://frasertweedale.github.io/blog-redhat/posts/2015-08-06-freeipa-custom-certprofile.html
	# Do we need to mess with profiles to get this working?
	ipa group-add etcd_users;	ipa caacl-add etcd_users_acl;	ipa caacl-add-user etcd_users_acl --group etcd_users
	ipa group-add-member etcd_users --user wavelet_domain

	# Generate a user certificate locally, and request it to be signed via the FreeIPA CA
	# This example would require a wavelet_domain FreeIPA user
	echo "[ req ]
prompt = no
encrypt_key = no

distinguished_name = dn
req_extensions = exts

[ dn ]
commonName = "wavelet_domain"

[ exts ]
subjectAltName=email:wavelet_domain@$(dnsdomainname)" > /var/home/wavelet/config/wavelet_openssl.config
	# Generate user key and request the certificate
	openssl genrsa -out key.pem 2048
	ipa cert-request wavelet_domain.req --principal wavelet_domain #--profile-id smime

	echo -e "Reconfiguring Etcd to utilize certificate...\n"
	# Client devices should be requesting an etcd service certificate on their end, for that specific host once they are properly provisioned
	# The client AND server cert is required to communicate with the etcd cluster, this prevents unauthorized clients from accessing etcd.
	# Note that the PHP modules will now also need to provide a valid client certificate to successfully deal with etcd
	# This might be a good time to roll them all up into a single file with a single curl function that operates appropriately.
	
	# Configure etcd root user, we will sync this with IPA because.. why not?
	ipa user-add etcd_root --random --first=etcd --last=rootUser > /var/secrets/etcdRoot.password
	local etcdRootPW=$(cat /var/secrets/etcdRoot.password); echo "${etcdRootPW}" | etcdctl user add root

	# Define roles
	# First role is for the server, which should be able to do everything
	role="server"
	etcdctl role add "${role}"
	etcdctl role grant-permission "${role}" readwrite --prefix ""

	# Add the user which will be allowed to access etcd from the server localhost via the webUI
	ipa user-add etcd_webui --random --first=etcd --last=webui > /var/secrets/etcdwebui.password
	local etcdWebUIPW=$(cat /var/secrets/etcdwebui.password); echo "${etcdWebUIPW}" | etcdctl user add etcd_webui
	role="etcd_webui"
	etcdctl role add "${role}"
	# We wish to grant the WebUI only permissions to readwrite keys which it ought to be interacting with.  You'll need to walk through this.
	# This is also why we've put everything webUI related under /interface/ or similar prefixes..
	etcdctl role grant-permission "${role}" readwrite --prefix ""

	# We may wish to add a different etcd client user for each client which joins
	# This will enable us to restrict clients from interfering with any keys other than their own.
	# This would be done on the client spinup and.. probably leave a mess when clients leave the network and need to be cleaned up on the regular?
	# Let us test with the server and go from there..
	local userName="etcd_host_$(hostname)"
	ipa user-add ${userName} --random --first=etcd --last=webui > /var/secrets/etcd_host_$(hostname).password
	local etcdHostPW=$(cat /var/secrets/${userName}); echo "${etcdHostPW}" | etcdctl user add ${userName}
	etcdctl user grant-role "${userName}" "server"
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
		# To Pull httpd.conf out of the container
		# podman run --rm httpd:2.4 cat /usr/local/apache2/conf/httpd.conf > custom-httpd.conf
	# Put the secure conf file in place
	cp /var/home/wavelet/config/httpd.secure.conf  /var/home/wavelet/config/httpd.conf
	# Add the certificate files to the quadlet (note right now this is a container, more work needed to move it to quadlet, so path will change etc.)
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
	# Copy new nginx configuration file configured for TLS certs
	cp /var/home/wavelet/config/nginx.conf.secure /var/home/wavelet/http-php/nginx/nginx.conf
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
	# Stuff I haven't yet thought of here

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
  sudo systemctl --now enable clamav-freshclam.service clamd@scan.service
  sudo semanage boolean -m -1 antivirus_can_scan_system

	# Freshclam and ClamAV scans on off hours?
}


####
#
# Main
#
####


hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
exec >/var/home/wavelet/logs/hardening.log 2>&1
detect_self