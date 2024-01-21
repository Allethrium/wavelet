#!/bin/bash
# Sets up a FreeIPA server in a container, calling all passwords from a preset file in /var/lib/ipa-data/
# Necessary if we want to implement RADIUS/WPA2-ENT or have useful certificate tracking
ETCDENDPOINT=192.168.1.32:2379
KEYNAME=SERVER_IDM_BOOTSTRAP_COMPLETED
KEYVALUE=1
USER=wavelet
SCRHOME=/home/wavelet

git clone https://github.com/freeipa/freeipa-container.git
cd freeipa-container
podman build -f Dockerfile.fedora-39 -t freeipa-server .

# Allow systemd in containers
setsebool -P container_manage_cgroup 1

# Create FreeIPA data dir
mkdir -P /var/lib/ipa-data
mkdir -P /etc/containers/systemd
# Generate Quadlet
echo -e "[Unit]
Description=The sleep container
After=local-fs.target

[Container]
ContainerName=freeipa-server-container
Image=localhost/freeipa-server:latest
HostName=ipa.wavelet.local
PublishPort=53:53/udp
PublishPort=53:53
PublishPort=88:88/udp
PublishPort=389:389/tcp
PublishPort=123:123/udp
PublishPort=464:464/udp
PublishPort=636:636/tcp
PublishPort=88:88/tcp
PublishPort=464:464/tcp
Volume=/var/lib/ipa-data:/data:Z
Volume=/sys/fs/cgroup:/sys/fs/cgroup:ro
Tmpfs=/run
Tmpfs=/tmp
Environment=IPA_SERVER_IP=192.168.1.32
Environment=realm=WAVELET.LOCAL
Environment=admin-password=WaveletPasswordAdm1313
Environment=no-ntp
Environment=setup-dns
Environment=forwarder=192.168.1.1
Environment=forwarder=9.9.9.9
Environment=p=password1234
Environment=ip-address=192.168.1.32

[Install]
# Start by default on boot
WantedBy=multi-user.target default.target
" > /etc/containers/systemd/freeipa.container

# Disable dnsmasq, as with FreeIPA we will be using integrated BIND for DNS.
systemctl disable dnsmasq --now

# Initialize the podman container
echo -e "\nFreeIPA Podman container generated, service has been enabled in systemd, and will start on next reboot.\n"
systemctl daemon-reload
systemctl enable freeipa.container --now
etcdctl --endpoints=${ETCDENDPOINT} put ${KEYNAME} -- ${KEYVALUE}

exit 0

fail(){
	echo -e "A step in this script failed, please uncomment set -x and exec to debug."
	exit 1
}




