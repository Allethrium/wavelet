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
	mkdir -p /home/wavelet/.config/containers/systemd/
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
Restart=always
RestartSec=5

[Install]
# Start by default on boot
WantedBy=default.target" > /home/wavelet/.config/containers/systemd/httpd.container
	echo -e "\nApache Podman container generated, service has been enabled in systemd, starting service now..\n"
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "SERVER_HTTP_BOOTSTRAP_COMPLETED" "1"
	systemctl --user daemon-reload; systemctl --user start httpd.service
	# populate necessary files for decoder spinup
	cp /usr/local/bin/{UltraGrid.AppImage,wavelet_install_client.sh,decoderhostname.sh,connectwifi.sh,wavelet_installer_xf.sh} /var/home/wavelet/http/ignition/
	cp /var/home/wavelet/setup/wavelet-files.tar.xz /home/wavelet/http/ignition/
	cp /home/wavelet/.bashrc /home/wavelet/http/ignition/skel_bashrc.txt
	cp /home/wavelet/.bash_profile /home/wavelet/http/ignition/skel_profile.txt
	cp /usr/local/backgrounds/sway/wavelet_test.png /var/home/wavelet/http/ignition/
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
