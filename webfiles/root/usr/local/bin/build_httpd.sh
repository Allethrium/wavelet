#!/bin/bash
# Designed to be called by sway's build_ug.sh exec command.
# Need to amend this to generate or utilize proper certificates
ETCDENDPOINT=192.168.1.32:2379
KEYNAME=SERVER_HTTP_BOOTSTRAP_COMPLETED
KEYVALUE=1
USER=wavelet
SCRHOME=/home/wavelet

set -x
exec >/home/wavelet/build_httpd.log 2>&1

# Needs to be configured with proper TLS certs to be deployment ready.
echo -e "Generating Apache Podman container and systemd service file"
podman create --name httpd -p 8080:80 -v ${SCRHOME}/http/:/usr/local/apache2/htdocs:Z docker://docker.io/library/httpd
cd /home/wavelet/.config/systemd/user
podman generate systemd --restart-policy=always -t 5 --name httpd --files
cp container-httpd.service ${SCRHOME}/.config/systemd/user
chown wavelet:wavelet ${SCRHOME}/.config/systemd/user
systemctl --user enable container-httpd.service
echo -e "Apache Podman container generated, service has been enabled in systemd, and will start on next reboot."
etcdctl --endpoints=${ETCDENDPOINT} put ${KEYNAME} -- ${KEYVALUE}
pwd
exit 0

fail(){
	echo -e "A step in this script failed, please uncomment set -x and exec to debug."
	exit 1
}