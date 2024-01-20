#!/bin/bash
# Designed to be called by sway's build_ug.sh exec command.
# This spins up the server's control interface for any wifi client to access.  Files should already be prepopulated on EVERY device from Ignition.
# Need to amend this to generate or utilize proper certificates
# This uses a podman POD and therefore can't be ported to quadlets just yet..
# TODO - port to quadlets after 4.8 hits release and gets documentation 1/2024
ETCDENDPOINT=192.168.1.32:2379
KEYNAME=SERVER_HTTP-PHP_BOOTSTRAP_COMPLETED
KEYVALUE=1
USER=wavelet
SCRHOME="/var/home/wavelet"

# TLS certs would sure be nice..

set -x
exec >/home/wavelet/build_nginx_php.log 2>&1
cd ${SCRHOME}


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
chmod -R 0755 ${SCRHOME}/http-php

systemctl --user daemon-reload
systemctl --user enable pod-http-php.service --now
echo -e "Podman pod and containers, generated, service has been enabled in systemd, and will start on next reboot."
echo -e "The control service should be available via web browser on port 8180 I.E -\n http://svr.wavelet.local:8180 \n"
pwd
etcdctl --endpoints=${ETCDENDPOINT} put ${KEYNAME} -- ${KEYVALUE}
exit 0