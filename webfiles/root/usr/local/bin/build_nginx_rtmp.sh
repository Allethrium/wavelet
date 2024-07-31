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
exec >/home/wavelet/build_nginx_rtmp.log 2>&1
cd ${SCRHOME}


podman pod create --infra=true --name nginx-rtmp --publish 8554 \
-v ${SCRHOME}/http-rtmp/nginx:/etc/nginx/conf.d/:Z \
echo -e "Generating nginx RTMP Server simple configuration, and systemd service files.."
podman create --name nginx --pod nginx-rtmp docker://docker.io/library/nginx:alpine

echo -e "Generating nginx/PHP pod systemd service file.. \n"

podman generate systemd --restart-policy=always -t 5 --name http-rtmp --files
mv container-nginx.service ${SCRHOME}/.config/systemd/user

chown -R wavelet:wavelet ${SCRHOME}/.config/systemd/user
chown -R wavelet:wavelet ${SCRHOME}/nginx-rtmp
chmod -R 0755 ${SCRHOME}/nginx-rtmp

systemctl --user daemon-reload
systemctl --user enable pod-http-rtmp.service --now
echo -e "Podman pod and containers, generated, service has been enabled in systemd, and will start on next reboot."
echo -e "The control service should be available via web browser on port 8180 I.E -\n http://svr.wavelet.local:8180 \n"
pwd
etcdctl --endpoints=${ETCDENDPOINT} put ${KEYNAME} -- ${KEYVALUE}
exit 0