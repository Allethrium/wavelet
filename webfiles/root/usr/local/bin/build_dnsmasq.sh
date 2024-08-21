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


# Finds and parses current server IP address, then injects it as a listen address in dnsmasq.conf for DNS name resolution.
IPVALUE=$(ip a | grep 192.168.1 | awk '/inet / {gsub(/\/.*/,"",$2); print $2}')
if [[ "${IPVALUE}" == "" ]] then
	# sleep for five seconds, then call yourself again
	echo -e "\nIP Address is null, sleeping and calling function again\n"
	sleep 5
	get_ipValue
else
	echo -e "\nIP Address is not null, testing for validity..\n"
	valid_ipv4() {
		local ip=$1 regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
		if [[ $ip =~ $regex ]]; then
			echo -e "\nIP Address is valid, continuing..\n"
			return 0
		else
			echo "\nIP Address is not valid, sleeping and calling function again\n"
			get_ipValue
		fi
	}
valid_ipv4 "${IPVALUE}"
fi

sed "s/listen-address=::1,127.0.0.1/listen-address=::1,127.0.0.1,${IPVALUE}/g" /etc/dnsmasq.conf
systemctl stop systemd-resolved.service
systemctl enable dnsmasq.service --now
# Can run SystemD-resolved with StubListener set appropriately.
systemctl enable systemd-resolved.service --now
systemctl restart dnsmasq.service

# 8/2023 - Might replace all of this with a full iDM running BIND, especially if we need WPA2/3-ENT