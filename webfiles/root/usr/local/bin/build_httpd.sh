#!/bin/bash
# Designed to be called by sway's build_ug.sh exec command.
# Need to amend this to generate or utilize proper certificates
# Called from build_ug.sh when hostname is svr.wavelet.local
ETCDENDPOINT=192.168.1.32:2379
KEYNAME=SERVER_HTTP_BOOTSTRAP_COMPLETED
KEYVALUE=1
USER=wavelet
SCRHOME="/var/home/wavelet"

#set -x
exec >/home/wavelet/build_httpd.log 2>&1

echo -e "Generating Apache Podman container and systemd service file"
podman create --name httpd -p 8080:80 -v /home/wavelet/http:/usr/local/apache2/htdocs:Z docker://docker.io/library/httpd
cd /home/wavelet/.config/systemd/user
podman generate systemd --restart-policy=always -t 5 --name httpd --files
cp container-httpd.service ${SCRHOME}/.config/systemd/user
chown wavelet:wavelet ${SCRHOME}/.config/systemd/user
systemctl --user enable container-httpd.service
echo -e "\nApache Podman container generated, service has been enabled in systemd, and will start on next reboot.\n"
# Set ETCD key to true for this build step
etcdctl --endpoints=${ETCDENDPOINT} put ${KEYNAME} -- ${KEYVALUE}
# populate necessary files for decoder spinup
cp /usr/local/bin/UltraGrid.AppImage /home/wavelet/http/
cp /home/wavelet/wavelet-files.tar.xz /home/wavelet/http/ignition/
cp /usr/local/bin/wavelet_installer_xf.sh /home/wavelet/http/ignition/
cp /home/wavelet/.bashrc /home/wavelet/http/ignition/skel_bashrc.txt
cp /home/wavelet/.bash_profile /home/wavelet/http/ignition/skel_profile.txt
chown -R wavelet:wavelet /home/wavelet/http
chmod -x /home/wavelet/http
exit 0

fail(){
	echo -e "A step in this script failed, please uncomment set -x and exec to debug."
	exit 1
}
