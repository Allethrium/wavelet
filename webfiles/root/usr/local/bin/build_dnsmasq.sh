# Designed to be called by svr ignition file
#USER=wavelet
#SCRHOME=/home/wavelet
#podman create --name dnsmasq -p 53:53 -v ${SCRHOME}/dnsmasq:/:Z -v /etc/dnsmasq.conf:/etc/dnsmasq.conf:Z -v ${SCRHOME}/tftp:/home/wavelet/tftp docker://docker.io/jpillora/dnsmasq
#podman generate systemd --restart-policy=always -t 1 --name dnsmasq --files
#cp container-dnsmasq.service ${SCRHOME}/.config/systemd/user
#chown wavelet:wavelet ${SCRHOME}/.config/systemd/user
#Turn Dnsstublistener off in /etc/systemd/resolved.conf to free up port 53
#chcon -t dnsmasq_etc_t dnsmasq.conf
sed -n 's/DNSStubListener=yes/DNSStubListener=no/p' /etc/systemd/resolved.conf
systemctl daemon-reload
# Set SElinux contexts - I don't know if these will be persistent across reboots, so TEST this.
chcon -R -t tftpdir_rw -t ppublic_content_t /var/lib/tftpboot
restorecon -Rv /var/tftp

# Overwrite DNSmasq unit file adding restart=on-fail
echo "[Unit]
Description=DNS caching server.
Before=nss-lookup.target
Wants=nss-lookup.target
After=network.target
; Use bind-dynamic or uncomment following to listen on non-local IP address
;After=network-online.target

[Service]
ExecStart=/usr/sbin/dnsmasq
Restart=on-failure
Type=forking
PIDFile=/run/dnsmasq.pid
ExecStartPost=-touch /var/dnsmasq_terminated.notice

[Install]
WantedBy=multi-user.target
" > /usr/lib/systemd/system/dnsmasq.service

# Download base images, maybe leave this to the client generation scripts as it's not really necessary during server spinup.
#podman run --security-opt label=disable --pull=always --rm -v .:/data -w /data quay.io/coreos/coreos-installer:release download -f iso
#coreos-installer download -s stable -p metal -C /var/tftpboot

#systemctl --user enable container-dnsmasq.service --now
systemctl stop systemd-resolved.service
systemctl enable dnsmasq.service --now
# Can run SystemD-resolved with StubListener set appropriately.
systemctl start systemd-resolved.service
systemctl restart dnsmasq.service

# 8/2023 - Might replace all of this with a full iDM running BIND, especially if we need WPA2-ENT