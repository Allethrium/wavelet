#!/bin/bash
# Designed to be called by sway's build_ug.sh exec command.
# This spins up the server's control interface for any wifi client to access.  
# Files should already be prepopulated on EVERY device from Ignition.

ETCDENDPOINT=192.168.1.32:2379
KEYNAME=SERVER_HTTP-PHP_BOOTSTRAP_COMPLETED
KEYVALUE=1
USER=wavelet
SCRHOME="/var/home/wavelet"

detect_self(){
	systemctl --user daemon-reload
	echo -e "Hostname is ${hostNameSys} \n"
	case ${hostNameSys} in
	svr*)					echo -e "I am a Server. Proceeding..."															;	podman_quadlet
	;;
	*) 						echo -e "This device Hostname is not set appropriately, exiting\n"								;	exit 0
	;;
	esac
}

podman_quadlet(){
	# New Method - quadlets
	# We also now know we don't have any other services running on port 80 so we can put nginx on standard HTTP(S) ports.
	# The .kube file at the end basically allows us to link these two services into a podman pod.   
	# The install wantedBy= section is how we do systemctl enable --now, basically.
	mkdir -p /var/home/wavelet/.config/containers/systemd/
	echo -e "
[Unit]
Description=PHP + FPM
[Container]
Image=docker.io/library/php:fpm
AutoUpdate=registry
Pod=http-php.pod" > /var/home/wavelet/.config/containers/systemd/php-fpm.container
# For Nginx, ports are mapped to 9080 and 9443 respectively..
	echo -e "
[Unit]
Description=NGINX
[Container]
Image=docker.io/library/nginx:alpine
AutoUpdate=registry
Pod=http-php.pod" > /var/home/wavelet/.config/containers/systemd/nginx.container
	if [[ -f /var/prod.security.enabled ]]; then
	echo -e "Security layer enabled, adding mounts for certificates..\n"
		# Check for prod certs
		if [[ ! -f /etc/pki/tls/certs/http.crt ]]; then
			# we generate a crappy certificate so things work, at the very least..
			echo -e "Certificate has not been generated on server, generating a snake oil certificate for testing..\n"
			openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/pki/tls/certs/httpd.key -out /etc/pki/tls/certs/httpd.crt -subj "/C=US/ST=NewYork/L=NewYork/O=ALLETHRIUM/OU=DevOps/CN=WaveletInterface"
			openssl dhparam -out /etc/pki/certs/dhparam.pem 4096
		fi
		# Cert directory mounted regardless, the conf file will determine if we bother looking for them.
		cp /var/home/wavelet/config/nginx.secure.conf /var/home/wavelet/http-php/nginx/nginx.conf
	fi
	mkdir -p /var/home/wavelet/http-php/log
	echo -e "
[Pod]
PublishPort=9080:80
PublishPort=9443:443
Volume=/etc/pki/tls/certs/:/etc/pki/tls/certs/
Volume=/var/home/wavelet/http-php/log:/var/log/nginx:Z
Volume=/var/home/wavelet/http-php/html:/var/www/html:Z
Volume=/var/home/wavelet/http-php/nginx:/etc/nginx/conf.d/:z
[Install]
WantedBy=multi-user.target" > /var/home/wavelet/.config/containers/systemd/http-php.pod
	echo -e "Podman pod and containers, generated, service has been enabled in systemd, and will start on next reboot."
	echo -e "The control service should be available via web browser I.E \nhttp://svr.wavelet.local\n"
	systemctl --user daemon-reload
	systemctl --user start http-php-pod.service
	exit 0
}

#####
#
# Main
#
#####

#set -x
hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
exec > /var/home/wavelet/logs/build_nginx_php.log 2>&1
cd ${SCRHOME}
detect_self