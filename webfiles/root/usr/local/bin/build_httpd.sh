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

oldMethod(){
	# Podman generate systemd method
	echo -e "Generating Apache Podman container and systemd service file"
	podman create --name httpd -p 8080:80 -v /home/wavelet/http:/usr/local/apache2/htdocs:Z -v /home/wavelet/config/httpd.conf:/usr/local/apache2/conf/httpd.conf docker://docker.io/library/httpd
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
}

newMethod(){
	# Needs to be configured with proper TLS certs to be deployment ready.
	echo -e "Generating Apache Podman container and systemd service file"

	# Generate Quadlet - default is NOT secure and the config file would be overwritten by wavelet_install_hardening.sh
	# ref https://hub.docker.com/_/httpd
	echo -e "[Unit]
Description=HTTPD Quadlet
After=local-fs.target

[Container]
ContainerName=httpd
Image=docker://docker.io/library/httpd
PublishPort=8080:80
Volume=/home/wavelet/http:/usr/local/apache2/htdocs:Z
Volume=/home/wavelet/config/httpd.conf:/usr/local/apache2/conf/httpd.conf:Z
#cert
#key
Tmpfs=/run
Tmpfs=/tmp
Exec=httpd-foreground

[Service]
TimeOutStartSec=300
Restart=always
RestartSec=5

[Install]
# Start by default on boot
WantedBy=default.target" > /home/wavelet/.config/containers/systemd/httpd.container
	echo -e "\nApache Podman container generated, service has been enabled in systemd, and will start on next reboot.\n"
	etcdctl --endpoints=${ETCDENDPOINT} put ${KEYNAME} -- ${KEYVALUE}
	# populate necessary files for decoder spinup
	cp /usr/local/bin/UltraGrid.AppImage /home/wavelet/http/
	cp /home/wavelet/wavelet-files.tar.xz /home/wavelet/http/ignition/
	cp /usr/local/bin/wavelet_installer_xf.sh /home/wavelet/http/ignition/
	cp /home/wavelet/.bashrc /home/wavelet/http/ignition/skel_bashrc.txt
	cp /home/wavelet/.bash_profile /home/wavelet/http/ignition/skel_profile.txt
	chown -R wavelet:wavelet /home/wavelet/http
	chmod +x /home/wavelet/http
	exit 0
}

fail(){
	echo -e "A step in this script failed, please uncomment set -x and exec to debug."
	exit 1
}

#####
#
# Main
#
#####

if [[ -f /var/prod.security.enabled ]]; then
	echo -e "Security layer enabled, generating apache with TLS configuration.."
	newmethod
else
	echo -e "Security layer is not enabled, generating HTTPD without TLS.."
	oldMethod
fi