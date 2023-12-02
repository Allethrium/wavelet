#!/bin/bash
# Designed to be called by sway's build_ug.sh exec command.
# This spins up the server's control interface for any wifi client to access.
# Need to amend this to generate or utilize proper certificates
ETCDENDPOINT=192.168.1.32:2379
KEYNAME=SERVER_HTTP-PHP_BOOTSTRAP_COMPLETED
KEYVALUE=1
USER=wavelet
SCRHOME=/home/wavelet

# TLS certs would sure be nice..

set -x
exec >/home/wavelet/build_nginx_php.log 2>&1
USER=wavelet
SCRHOME=/home/wavelet
podman pod create --infra=true --name http-php --publish 8180:80 -v ${SCRHOME}/http-php/html:/var/www/html:Z -v ${SCRHOME}/http-php/nginx:/etc/nginx/conf.d/:Z -v ${SCRHOME}/http-php/html:/var/www/html:Z
echo -e "Generating nginx simple configuration, and systemd service files.."
# Can't echo because it loses critical charactesr in the conf file.
# should be done in ignition now.
# wget -P /home/wavelet/http-php/nginx/ https://www.andymelville.net/wavelet/nginx.conf
podman create --name nginx --pod http-php docker://docker.io/library/nginx:alpine
podman create --name php-fpm --pod http-php docker://docker.io/library/php:fpm

echo -e "Generating nginx/PHP pod systemd service file.. \n"

podman generate systemd --restart-policy=always -t 5 --name http-php --files
mv container-nginx.service ${SCRHOME}/.config/systemd/user
mv container-php-fpm.service ${SCRHOME}/.config/systemd/user
mv pod-http-php.service ${SCRHOME}/.config/systemd/user

chown wavelet:wavelet ${SCRHOME}/.config/systemd/user

cd /home/wavelet
rm -rf http-php
tar -xvf http-php.tar.xz

systemctl --user daemon-reload
systemctl --user enable pod-http-php.service --now
echo -e "Podmans container generated, service has been enabled in systemd, and will start on next reboot."
echo -e "The control service should be available via web browser on port 8180 I.E -\n http://svr.wavelet.local:8180 \n"
pwd
etcdctl --endpoints=${ETCDENDPOINT} put ${KEYNAME} -- ${KEYVALUE}
