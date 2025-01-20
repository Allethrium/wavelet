#!/bin/bash
# Designed to be called by sway's build_ug.sh exec command.
# Need to amend this to generate or utilize proper certificates
# Called from build_ug.sh when hostname is svr.wavelet.local
USER=wavelet
SCRHOME="/var/home/wavelet"

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
Volume=/home/wavelet/http:/usr/local/apache2/htdocs:z
Volume=/home/wavelet/config/httpd.conf:/usr/local/apache2/conf/httpd.conf:z
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
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "SERVER_HTTP_BOOTSTRAP_COMPLETED" "1"
	# populate necessary files for decoder spinup
	cp /usr/local/bin/UltraGrid.AppImage /home/wavelet/http/
	cp /home/wavelet/setup/wavelet-files.tar.xz /home/wavelet/http/ignition/
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

#set -x
exec >/var/home/wavelet/logs/build_httpd.log 2>&1

newMethod
