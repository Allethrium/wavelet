#!/bin/bash
# Designed to be called by sway's build_ug.sh exec command.
# This spins up the server's control interface for any wifi client to access.  
# Files should already be prepopulated on EVERY device from Ignition.

ETCDENDPOINT=192.168.1.32:2379
KEYNAME=SERVER_HTTP-PHP_BOOTSTRAP_COMPLETED
KEYVALUE=1
USER=wavelet
SCRHOME="/var/home/wavelet"

set -x
exec >/var/home/wavelet/build_nginx_php.log 2>&1
cd ${SCRHOME}
detect_self(){
	systemctl --user daemon-reload
	UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	svr*)					echo -e "I am a Server. Proceeding..."															;	event_server
	;;
	*) 						echo -e "This device Hostname is not set appropriately, exiting \n"								;	exit 0
	;;
	esac
}

podman_systemd_generate(){
	# Old method
	podman pod create --infra=true --name http-php --publish 8180:80 \
		-v ${SCRHOME}/http-php/html:/var/www/html:Z \
		-v ${SCRHOME}/http-php/nginx:/etc/nginx/conf.d/:Z \
		-v ${SCRHOME}/http-php/html:/var/www/html:Z
	echo -e "Generating nginx simple configuration, and systemd service files.."
	podman create --name nginx --pod http-php docker://docker.io/library/nginx:alpine
	podman create --name php-fpm --pod http-php docker://docker.io/library/php:fpm
	echo -e "Generating nginx/PHP pod systemd service file.. \n"
	podman generate systemd --restart-policy=always -t 5 --name http-php --files
	mv container-nginx.service ${SCRHOME}/.config/systemd/user
	mv container-php-fpm.service ${SCRHOME}/.config/systemd/user
	mv pod-http-php.service ${SCRHOME}/.config/systemd/user
	chown -R wavelet:wavelet ${SCRHOME}/.config/systemd/user
	chown -R wavelet:wavelet ${SCRHOME}/http-php
	# Does nginx need +X on these files? (yes, it does)
	chmod -R 0755 ${SCRHOME}/http-php
	systemctl --user daemon-reload
	systemctl --user enable pod-http-php.service --now
}

podman_quadlet(){
	# New Method - quadlets
	# We also now know we don't have any other services running on port 80 so we can put nginx on standard HTTP(S) ports.
	# The .kube file at the end basically allows us to link these two services into a podman pod.   
	# The install wantedBy= section is how we do systemctl enable --now, basically.
	echo -e "\
[Unit]
Description=PHP + FPM
[Container]
Image=docker.io/library/php:fpm
ContainerName=container-php-fpm
AutoUpdate=registry
Notify=true
Pod=http-php
[Service]
Restart=always
TimeoutStartSec=30
[Install]
WantedBy=multi-user.target default.target" > /var/home/wavelet/.config/containers/systemd/container.php-fpm
# For Nginx, we moved the port mapping to standard ports, so that we will no longer need to include additional steps or documentation at the user end.
	echo -e "\
[Unit]
Description=NGINX
[Container]
Image=docker.io/library/nginx:alpine
ContainerName=container-nginx
AutoUpdate=registry
Notify=true
Pod=http-php
Volume=/etc/pki/tls/certs/httpd.cert:z
Volume=/etc/pki/tls/certs/httpd.key:z
[Service]
Restart=always
TimeoutStartSec=30
[Install]
WantedBy=multi-user.target default.target" > /var/home/wavelet/.config/containers/systemd/nginx.container
	echo -e "\
[Install]
WantedBy=default.target
[Unit]
Requires=nginx.service
After=php-fpm.service
[Kube]
# Publish the envoy proxy data port
PublishPort=80:80
PublishPort=443:443" > /var/home/wavelet/.config/containers/systemd/http-php.kube
	echo -e "Podman pod and containers, generated, service has been enabled in systemd, and will start on next reboot."
	echo -e "The control service should be available via web browser I.E \nhttp://svr.wavelet.local:8180\n"
	etcdctl --endpoints=${ETCDENDPOINT} put ${KEYNAME} -- ${KEYVALUE}
	systemctl --user daemon-reload
	systemctl --user enable http-php.service
	exit 0
}

event_server(){
	if [[ -f /var/developerMode.enabled ]]; then
		echo -e "\n\n***WARNING***\n\nDeveloper Mode is ON\n\nAttempting to spin up services using quadlets..\n"
		podman_quadlet
	else
		echo -e "\nDeveloper mode off.\n"
		podman_systemd_generate
	fi
}