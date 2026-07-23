#!/bin/bash

# This installation module sets up FreeRADIUS for better security w/ client systems
# to test:  podman run --name freeradius -d -v ./freeradius/:/etc/freeradius:z docker.io/freeradius/freeradius-server radiusd -Xx
# Server creates the server with new certificates
# Client generates a client certificate for a requestor during the etcd key provision process (when it is still on wired)
# Runs under wavelet-root exclusively

source "/etc/wavelet.conf"

build_containerfile(){
	# TODO - test on fedora:latest (44)
	# We limit to Fedora 42 as there is a bug with Freeradius and OpenSSL on the latest version 43.
	containerFile="/var/home/wavelet-root/config/Containerfile.radius"
	cat > "$containerFile" << EOF
FROM fedora:latest
RUN rm -rf /etc/yum.repos.d/fedora-cisco-openh264.repo && \
	dnf -y update && \
	dnf install -y radiusd && \
	dnf clean all
EOF
	# Building the radius container may not fail, it is a critical component.
	if ! podman build -t radiusd -f "$containerFile"; then
		podman build -t radiusd -f "$containerFile"
	fi
	podman push radiusd "$(hostname):5000/radiusd:latest"
}

configure_radius(){
	# Build RADIUS container
	# If LAN deployment, the container should already be available in the server's registry
	cd "/var/home/wavelet-root/config" || exit 1
	output="$(curl https://$SVR_HOSTNAME:5000/v2/_catalog)"
	if [[ "$output" == *"radiusd"* ]]; then
		echo "	Found expected container in registry catalog.."
	else
		echo "	Radius container not available on local registry, building container locally.."
		build_containerfile
	fi
	# TODO - we seem to have an error here - the skel config is no longer being correctly generated.
	echo "	Generating skel raddb configuration:"
	echo "	podman run -d -v /var/home/wavelet-root/config:/var/tmp:z $SVR_HOSTNAME/radiusd cp -R /etc/raddb/ /var/tmp"
	# Ensure ownerships are correct before proceeding
	sudo chown -R wavelet-root:wavelet-root "/var/home/wavelet-root"
	podman run --rm -v /var/home/wavelet-root/config:/var/tmp:z "$SVR_HOSTNAME/radiusd" sh -c 'cp -r /etc/raddb /var/tmp/'
	# Now that we have a full skeleton of RADIUS configuration files, we copy our templates in
	echo -e "\n\n	Copying RADIUS configuration files from git, as user: $(whoami)"
	sudo cp -R "/var/wavelet_root/home/wavelet-root/config/radius/" "/var/home/wavelet-root/config/"
	echo "	Copying custom files from /radius to /raddb config directory"
	rsync -a "/var/home/wavelet-root/config/radius/" "/var/home/wavelet-root/config/raddb/"
	# Modify the radiusd config to run as root, or there will be permissions issues when accessing config files and certificates.
	# Since we are running inside a rootless container, this is less problematic (but still bad practice..)
	if [[ ! -f "/var/home/wavelet-root/config/raddb/radiusd.conf" ]]; then
		echo "	ERROR:  radiusd.conf missing! cannot continue."
		exit 1
	else
		sed -i 's/user = radiusd/user = root/g' "/var/home/wavelet-root/config/raddb/radiusd.conf"
		sed -i 's/group = radiusd/group = root/g' "/var/home/wavelet-root/config/raddb/radiusd.conf"
		sed -i 's|cadir   = ${confdir}/certs|cadir   = /etc/ipa|g' "/var/home/wavelet-root/config/raddb/radiusd.conf"
	fi
	sudo chown -R wavelet-root:wavelet-root "/var/home/wavelet-root"
	# Enable radius-over-tls & config clients directives appropriately
	enable_radsec

	echo "	Generating RADIUS quadlet.."
	mkdir -p "/var/home/wavelet-root/.config/containers/systemd/"
	# Note the ExecStartPre directive, which checks for freeIPA's ACME service responder before starting.
	cat > "/var/home/wavelet-root/.config/containers/systemd/freeradius.container" <<-EOF
		[Unit]
		Description=FreeRADIUS Quadlet
		After=network.target freeipa.service

		[Container]
		ContainerName=freeradius
		Image=%H/radiusd
		Network=pasta
		PublishPort=192.168.1.32:1813:1813/udp
		PublishPort=192.168.1.32:1812:1812/udp
		PublishPort=192.168.1.32:2083:2083/tcp
		# RADIUS Config directory
		Volume=/var/home/wavelet-root/config/raddb/:/etc/raddb:z
		# CA
		Volume=/etc/ipa/ca.crt:/etc/ipa/ca.crt:ro
		Exec=radiusd -fxx -l stdout

		[Service]
		ExecStartPre=/bin/bash -c 'until curl -ksf https://192.168.1.227:8443/acme/ >/dev/null 2>&1; do sleep 3; done'
		Restart=always
		RestartSec=5

		[Install]
		# Start by default on boot
		WantedBy=multi-user.target default.target
	EOF
    # We must ensure the inner-tunnel link is removed, or RADIUS will refuse to start
    unlink "/var/home/wavelet-root/config/raddb/sites-enabled/inner-tunnel"
	systemctl --user daemon-reload
	systemctl --user start freeradius.service
}

enable_radsec(){
	cd "/var/home/wavelet-root/config/radius" || exit 1
	# Append correct client entry to tls module
	# This is required or RADIUS will not respond to the WiFi AP!
	# If we wind up supporting systems running multiple AP, this will need attention.
	# find #_APPEND_HERE and add
	if [[ -z "$WIFI_IPADDR" ]]; then
		echo "	ERROR:  Wifi IP address isn't populated, attempting to resource file.."
		source "/etc/wavelet.conf"
		if [[ -z "$WIFI_IPADDR" ]]; then
			echo "	Attempting to resolve WiFi AP IP address via MAC ($WIFI_BSSID)..."
			resolvedIP=""
			while read -r entry; do
				ip_addr=$(echo "$entry" | awk '{print $1}')
				mac_addr=$(echo "$entry" | awk '{print $5}')
				if [[ "$mac_addr" == *"$WIFI_BSSID"* ]]; then
					resolvedIP="$ip_addr"
					break
				fi
			done < <(ip -4 neigh show 2>/dev/null)
			if [[ -z "$resolvedIP" ]]; then
				while read -r line; do
					if [[ "$line" == *"$WIFI_BSSID"* ]]; then
						# Extract IP from arp -a output: ? (192.168.1.1) at 00:11:22:33:44:55
						resolvedIP=$(echo "$line" | grep -oE '\([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\)' | tr -d '()')
						if [[ -n "$resolvedIP" ]]; then
							break
						fi
					fi
				done < <(arp -a -n 2>/dev/null)
			fi
			if [[ -z "$resolvedIP" ]]; then
				echo "	ERROR:  Could not resolve WiFi AP IP address from MAC $WIFI_BSSID"
			else
				echo "	Resolved IP: $resolvedIP"
				echo "	Verifying resolved IP via avahi/reverse lookup and reachability..."
				verify_ip=false
				# Check via avahi-resolve-address if available
				if command -v avahi-resolve-address &> /dev/null; then
					avahi_result="$(avahi-resolve-address -4 "$resolvedIP" 2>/dev/null)"
					avahi_host=$(echo "$avahi_result" | awk '{print $2}')
					if [[ -n "$avahi_host" && "$avahi_host" != "-" && "$avahi_host" != "." ]]; then
						echo "	Avahi resolved hostname: $avahi_host"
						verify_ip=true
					fi
				fi
				if [[ "$verify_ip" != true ]]; then
					if timeout 3 bash -c "echo >/dev/tcp/$resolvedIP/443" 2>/dev/null; then
						echo "	Port 443 on $resolvedIP is open, verification passed."
						verify_ip=true
					elif ping -c 1 -W 2 "$resolvedIP" > /dev/null 2>&1; then
						echo "	Ping to $resolvedIP succeeded, verification passed."
						verify_ip=true
					elif command -v nmap &> /dev/null && nmap -p 443 --open -n "$resolvedIP" > /dev/null 2>&1; then
						echo "	nmap verified port 443 open on $resolvedIP, verification passed."
						verify_ip=true
					fi
				fi
				if [[ "$verify_ip" != true ]]; then
					echo "	WARNING:  Could not verify $resolvedIP via avahi or reachability checks."
				fi
				echo "	Performing curl to verify manufacturer on: https://$resolvedIP/admin/login.jsp"
				# Use -k to allow self-signed certs, -s for silent, -m 5 for 5 sec timeout
				result="$(curl -ks -m 5 "https://$resolvedIP/admin/login.jsp" 2>/dev/null)"
				# This is the common login redirect for Unleashed.
				if [[ "$result" != *"Ruckus"* ]]; then
					echo "	ERROR:  resolve IP does not appear to be a Ruckus Access point"
					echo "	Continuing so that RADIUS accepts this NAS, but CA injection likely won't work"
					echo "	This will break RADSEC and cause TLS error log spam from the RADIUS container."
				else
					echo "	Verified: $resolvedIP appears to be a Ruckus Access point."
				fi
				echo "WIFI_IPADDR=$resolvedIP" >> "/var/home/wavelet-root/wifi_ipaddr.txt"
			fi
		fi
		# Re-source wavelet.conf with the populated IP address
		WIFI_IPADDR="$(</var/home/wavelet-root/wifi_ipaddr.txt)"
		WIFI_IPADDR="${WIFI_IPADDR##*=}"
	fi
	echo "	Appending TLS NAS client to /sites-enabled/tls, required for secured communication between AP and RADIUS."
	# once we have consumed the AP IP Address in the conf file, we can remove that line from the file.
	rm -rf "/var/home/wavelet-root/wifi_ipaddr.txt"
	cat > "tls_client_block" <<EOF
		client waveletAP {
			ipaddr = ${WIFI_IPADDR}
			proto = tls
			secret = radsec
		}
EOF
	sed -i "/#_APPEND_RADSEC_CLIENT_HERE/r tls_client_block" sites-enabled/tls
	cp -f "sites-enabled/tls" "/var/home/wavelet-root/config/raddb/sites-enabled"
	# May not be needed - would make replacing the AP a real pain in the event of hw failure
	# generate_client_certificate "wavelet_ap";
	# This approach at the simplest should be adding our generated IPA CA to the CA store on the Access Point.
	currentIPCIDR="$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | head -n 1)"
	currentSubnet="$(ipcalc "$currentIPCIDR" | sed -n '2p')"
	# We could try to scan the subnet for a valid AP now, or just allow NAS requests from the entire subnet.  Leave permissive for now.
	# Require client cert means the AP must have a signed certificate from the CA we generated above.  This will be complex to manage, and require a full PKI.
	cat > "/var/home/wavelet-root/config/raddb/clients.conf" <<EOF
# Defines a RADIUS client.
# Only one AP client for this system, simplified config.  127.0.0.1 disabled as testing unnecessary.
client waveletAP {
	ipaddr = ${currentSubnet#*:} # accept NAS client calls from this subnet
	proto = *
	secret = radsec
	require_message_authenticator = true
	#require_client_certificate = yes
	ca_file = /etc/ipa/ca.crt
	nas_type = other
	limit {
		max_connections = 8
		lifetime = 0
		idle_timeout = 30
	}
}
EOF
}

# Remove inner tunnel, it is not needed for EAP-TLS
rm -rf "/var/home/wavelet-root/config/raddb/sites-enabled/inner-tunnel"


#####
#
# Main
#
#####


logName="$HOME/logs/radius_conf.log"
if [[ -e "$logName" || -L "$logName" ]] ; then
	i=0
	while [[ -e "$logName-$i" || -L "$logName-$i" ]] ; do
		(( i++ ))
	done
	logName="$logName-$i"
fi

exec > "$logName" 2>&1

echo "	Called with ${*}"
case "$@" in
	*server*)	echo "	Configuring RADIUS server!"; configure_radius
	;;
	*)			echo "	Called with invalid option!"; exit 0
esac