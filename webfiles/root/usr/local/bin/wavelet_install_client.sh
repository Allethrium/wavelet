#!/bin/bash
# This runs as a systemd unit on the first boot on the Client devices ONLY.
# It is responsible for:
#	Joining the domain
#	Provisioning services, so that it can talk to etcd and the DC.


check_resolved() {
    if systemctl is-active --quiet systemd-resolved; then
        return 0
    else
        return 1
    fi
}
reconfigure_dns(){
	# Modify system connection to utilize the DC going forwards
	# This is necessary so that IPA DNS discovery functions correctly
	systemctl disable systemd-resolved.service --now
	cat > "/etc/systemd/resolved.conf" <<-EOF
		[Resolve]
		DNS=$DC1_IP
		FallbackDNS=$gateway 9.9.9.9
		Domains=$DOMAIN
	EOF
	# Add our dc1 entry here - the entry is also populated into /etc/hosts below.
	systemctl enable systemd-resolved.service --now
	resolvectl dns "$active_networkInterface" "$DC1_IP"
	resolvectl domain "$active_networkInterface" "$DOMAIN"
	# TODO - not necessary
#	chmod +x "/etc/NetworkManager/dispatcher.d/20-ipa-dns-update"
	echo "  	DNS Reconfigured.."
}
join_domain(){
	local password="$1"
	echo "Attempting to join IPA Domain with host OTP.."
	# Install FreeIPA Client
	mkdir -p /var/lib/ipa-client/{pki,sysrestore,certmonger}
	mkdir -p "/var/lib/certmonger"
	# SELinux breaks certmonger, so we fix this here
	semanage fcontext -a -t certmonger_var_lib_t "/var/lib/certmonger(/.*)?"
	restorecon -Rv "/var/lib/certmonger"
	# The OTP can be used only once, then it becomes invalid
	ipa-client-install --password "$password" \
        --unattended \
        --enable-dns-updates \
        --ssh-trust-dns #\
        #--pkinit-identity=FILE:/etc/pki/tls/certs/provision.crt
        #--pkinit-anchor=FILE:/var/home/wavelet/root/config/ca.crt
}
request_otp(){
	# Request domain enrollment OTP from server
	local domainotprq; local output; local factor2
	enrollOTP=""
	ETCD_OTPFILE="$(mktemp)"
	TMPFILE="$(mktemp)"
	ETCDCTL_CACERT=""
	ETCDCTL_ENDPOINTS=""
	# Factor2 is independently generated on the server side as well from information about this host
	# The sha256sum has to match in order to be able to decrypt the OTP.
    current_second="$(date +%S)"
    current_minute="$(date +%M)"
    if [ "$current_minute" -eq 59 ] && [ "$current_second" -ge 30 ]; then
        sleep_seconds=$((60 - current_second))
        echo "Waiting $sleep_seconds seconds until next hour to avoid collision on encryption factor2."
        sleep "$sleep_seconds"
    fi
	factor2="$(echo -n "$myIPAddr","$(dnsdomainname)","${myMACAddr^^}","$(date +"%H")")"
	factor2="$(echo "$factor2" | sha256sum | tr -d ' -')"
	# Initiate domain enrollment request by accessing the etcd key with our preprovisioned enrollment pw.
	domainotprq="$(cat /var/root/secrets/enrollpw)"
	export ETCDCTL_CACERT="/var/home/wavelet/config/ca.crt"
	export ETCDCTL_ENDPOINTS="$ETCDENDPOINT"
	if [[ -z "$myIPAddr" ]]; then
		echo "	IP Address is empty, attempting to resolve.."
		myIPAddr="$(hostname -I | xargs)"
	fi
	# Start watch service writing JSON output to tmpfile for reliable parsing
	etcdctl --user="ENROLL:$domainotprq" \
	    watch "/ENROLL/REQUEST/$hostNameSys/OTP" -w json > "$TMPFILE" 2>&1 &
	WATCH_PID=$!
	echo " Waiting 2 seconds for watch registration..."
	sleep 2
	# Make request via another etcdctl call
	echo "	Writing request key at: /ENROLL/REQUEST/$hostNameSys"
	etcdctl --user "ENROLL:$domainotprq" \
		put "/ENROLL/REQUEST/$hostNameSys" -- "REQUEST;$myIPAddr" &
	timeout=300
	polling_threshold=101
	elapsed=0
	while (( elapsed < timeout )); do
		# Parse JSON watch output for put events - extract the value field reliably
		if [[ -s "$TMPFILE" ]]; then
			ETCD_WATCH_VALUE="$(grep -o '"action":"put"' "$TMPFILE" >/dev/null 2>&1 && \
			                    grep -o '"value":"[^"]*"' "$TMPFILE" | tail -1 | sed 's/"value":"//;s/"$//' || true)"
			if [[ -n "$ETCD_WATCH_VALUE" ]]; then
				echo "	Got OTP via watch: $ETCD_WATCH_VALUE"
				echo "$ETCD_WATCH_VALUE" > "$ETCD_OTPFILE"
				break
			fi
		fi
		# At 10 seconds, if watch hasn't fired, something has gone wrong, but attempt a direct read
		if (( elapsed >= polling_threshold )) && [[ ! -s "$ETCD_OTPFILE" ]]; then
			echo "	Watch silent for ${polling_threshold}s, attempting direct poll..."
			enrollOTP="$(etcdctl --user "ENROLL:$domainotprq" \
			    get "/ENROLL/REQUEST/$hostNameSys/OTP" --print-value-only 2>/dev/null)"
			if [[ -n "$enrollOTP" ]]; then
				echo "	Got OTP via direct poll at ${elapsed}s: $enrollOTP"
				echo "$enrollOTP" > "$ETCD_OTPFILE"
				break
			fi
		fi

		sleep .1
		(( elapsed += 1 ))
	done
	enrollOTP="$(<"$ETCD_OTPFILE")"
	kill "$WATCH_PID" 2>/dev/null
	rm -f "$TMPFILE"

	if [[ -z "$enrollOTP" ]]; then
		echo "	ERROR - OTP Null after ${timeout}s! Triggering recovery..."
		# Signal server to destroy and recreate the host account
		etcdctl --user "ENROLL:$domainotprq" \
		    put "/ENROLL/REQUEST/$hostNameSys/OTP_RECOVER" "$(hostname)" 2>/dev/null
		echo "	Recovery signal sent, waiting for re-enrollment..."
		# Retry the watch/poll cycle once more after recovery signal
		sleep 5
		enrollOTP="$(etcdctl --user "ENROLL:$domainotprq" \
		    get "/ENROLL/REQUEST/$hostNameSys/OTP" --print-value-only 2>/dev/null)"
		if [[ -n "$enrollOTP" ]]; then
			echo "	GOT OTP on retry after recovery signal: $enrollOTP"
			echo "$enrollOTP" > "$ETCD_OTPFILE"
			request_otp_phase2
		else
			echo "	FATAL: Recovery failed, no OTP received."
			exit 1
		fi
	else
		echo "	Response file written, proceeding.."
		request_otp_phase2
	fi
}
request_otp_phase2(){
	# Read the output
	local temp_base64; local decryptResult; local finalPassword
	temp_base64="$(mktemp)"
	output="$enrollOTP"
	if [[ -z "$output" ]]; then
		echo "		Return OTP null!  Attempting immediate re-read!"
		output="$(etcdctl --user "ENROLL:$domainotprq" \
        	get "/ENROLL/REQUEST/$hostNameSys/OTP" --print-value-only)"
    fi
	echo "$output" > "$temp_base64"
	temp_decrypted="$(mktemp)"
	temp_final="$(mktemp)"
	base64 -d "$temp_base64" > "$temp_decrypted"
	decryptResult="$(openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -pass pass:"$factor2" < "$temp_decrypted")"
	finalPassword="$(base64 -d <<< "$decryptResult")"
	if [[ "$decryptResult" == *"bad decrypt"* ]]; then
		echo "	Issue decrypting the domain join credential.	Attempting recovery.."
		output="$(etcdctl --user "ENROLL:$domainotprq" \
        	get "/ENROLL/REQUEST/$hostNameSys/OTP_RECOVER" --print-value-only)"
        if [[ -z "$output" ]]; then
        	echo "	Output recovery attempt failed.  There is an issue with the server preventing domain enrollment!"
        	exit 1
        fi
    fi
	rm "$temp_decrypted" "$temp_final" "$temp_base64"
	if join_domain "$finalPassword"; then
		echo "	Domain join completed successfully, proceeding with certificate requests"
		# Remove the enrollpw credential, because we don't need to ever enroll this host again.
		rm -rf "/etc/systemd/system/etcd_enroll_watcher.service"
		systemctl disable etcd_enroll_watcher.service --now && systemctl daemon-reload
		shred "/var/root/secrets/enrollpw" && rm -rf "/var/root/secrets/enrollpw"
		# Domain join completion is tracked by the presence of the file, but we don't need a state flag for this
		# as it's an intermediate step, not a final installation state
	else
		echo "	Domain join failed, cannot continue with certificate requests"
		exit 1
	fi
}
install_security_layer(){
	# Joins the device to the FreeIPA domain and requests an 802.1x certificate
	nmcli con mod "$(nmcli -g NAME con show | head -1)" ipv4.dns "$DC1_IP" ipv4.dns-search "$DOMAIN"
	# Import DC1 host entry to /etc/hosts
	cat "$DC1_IP $DC1_HOSTNAME" >> "/etc/hosts"
	# Check to see systemd-resolved is running
	echo "Configuring systemd-resolved..."
	reconfigure_dns
	# If DNS isn't working, we have bigger problems.
	request_otp
	# Now that IPA is up and running, we can run a getcert request and install our EAP-TLS certificate
	# Note that for this certificate profile:
	# IPA should NOT require any special permissions beyond being a domain member to acquire this cert.
	echo "	Requesting IPA EAP-TLS client certificate.."
	# Note we use a short hostname here
	clientHostName="$(hostname -s)"
	sudo ipa-getcert request \
		--id=802_1x \
		--profile=ca802_1xCert \
		--renew \
		--keyfile="/etc/pki/tls/private/eaptls-client-${clientHostName}.key" \
		--key-owner=root \
		--key-perms=600 \
		--certfile="/etc/pki/tls/certs/eaptls-client-${clientHostName}.crt" \
		--cert-owner=root \
		--cert-perms=644 \
		--wait \
		--wait-timeout=60 \
		--key-size=2048 \
		--after-command="setfacl -m u:wavelet:r /etc/pki/tls/certs/eaptls-client-${clientHostName}.crt && setfacl -m u:wavelet:r /etc/pki/tls/private/eaptls-client-${clientHostName}.key"
}
configure_firewall(){
    # Configures NFT for kernel-native filtering
    # Note this is the client/encoder. It can serve UltraGrid, RTSP, and NDI traffic,
    # but it does not host backend services (etcd, FreeIPA, RADSEC). Those are only on the main server.
    # Inbound traffic is allowed for discovery (mDNS/NDI), media serving (UltraGrid/RTSP/NDI),
    # and established/related connections for services the client initiates (DNS, FreeIPA, etcd, RADSEC).
    subNetCIDR="192.168.1.0/24"
    nft flush ruleset
    nft add table inet wavelet
    nft add chain inet wavelet input '{ type filter hook input priority 0; policy drop; }'
    nft add chain inet wavelet forward '{ type filter hook forward priority 0; policy drop; }'
    nft add chain inet wavelet output '{ type filter hook output priority 0; policy accept; }'
    # Allow loopback
    nft add rule inet wavelet input iif lo accept
    nft add rule inet wavelet input ct state established,related accept
    # Rate limiting to prevent brute-force on key client ports (SSH, Cockpit)
    nft add rule inet wavelet input tcp dport 22 limit rate 10/second accept
    nft add rule inet wavelet input tcp dport 9090 limit rate 10/second accept
    # Allow ICMP
    nft add rule inet wavelet input ip protocol icmp accept
    nft add rule inet wavelet input ip6 nexthdr icmpv6 accept
    # Avahi (mDNS/DNS-SD for NDI discovery) - Client needs to receive multicast/broadcast
    nft add rule inet wavelet input udp dport 5353 accept
    nft add rule inet wavelet input udp dport 5354 accept
    nft add rule inet wavelet input udp dport 5355 accept
    # UltraGrid streaming (serving/receiving as encoder)
    nft add rule inet wavelet input udp dport "{ 5004-5010, 3478-3480, 9800, 16384-16450, 30000-31000, 40000-40100 }" accept
    # RTSP (serving as encoder)
    nft add rule inet wavelet input tcp dport 554 accept
    # NDI media serving/reception (encoder as source or receiver/display)
    # NDI video streams (UDP)
    nft add rule inet wavelet input udp dport "{ 10000,10001 }" accept
    nft add rule inet wavelet input udp dport "{ 10000-10100 }" accept
    # NDI control (TCP)
    nft add rule inet wavelet input tcp dport "{ 33000-33004 }" accept
    # NDI VNC / remote control (TCP)
    nft add rule inet wavelet input tcp dport 5900 accept
    # Log drops for debugging
    nft add rule inet wavelet input log prefix "WAVELET-INPUT " level warn
    nft add rule inet wavelet input drop
}
generate_wavelet_userspace_services(){
  # Generates the wavelet_build.service, which launches upon UI restart
  file="/home/wavelet/.config/systemd/user/wavelet_build.service"
  echo -e "[Unit]
Description=Wavelet Initial Setup Service
After=network-online.target sway-session.target
Wants=network-online.target sway-session.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wavelet_build.sh

[Install]
WantedBy=sway-session.target" > "$file"
  chown wavelet:wavelet "$file"; chmod 0644 "$file"
}
optimize_latency(){
	local iface="$1"
	# This function attempts to perform some direct system optimizations
	# Based upon what we know about discovered hardware, CPU topology, etc.
	if [[ -n "$iface" ]]; then
		ethtool -K "$iface" gro off 2>/dev/null || echo "    (gro off not supported on $iface)"
		# also disable lro if present
		ethtool -K "$iface" lro off 2>/dev/null || true
	fi
	echo "	Getting CPU topology and attempting to isolate and reserve CPU cores for media encoding.."
	local numCPU; local isolated; local want; local reserved
	numCPU="$(nproc)"
	want=$(( numCPU - 2 ))          # leave 2 for systemd/kernel housekeeping
	if (( want < 2 )); then
		echo "	This device has too few CPU cores to safely perform isolation.  Skipping."
		want=0
	elif (( want > 8 )); then
		want=8                       # cap: encoders get diminishing returns past 8 threads
	fi
	want=$(( want & ~1 ))            # round down to an even number
	if (( want > 0 )); then
		isolated="$(seq -s ', ' $(( numCPU - want )) $(( numCPU - 1 )))"
		# ensure irqaffinity goes to the remainder (reserved) cores
		reserved="$(seq -s ', ' 0 $(( numCPU - want - 1 )))"
		rpm-ostree kargs --append="isolcpus=$isolated" \
			--append="nohz_full=$isolated" \
			--append="rcu_nocbd=$isolated" \
			--append="irqaffinity=$reserved" \
			2>/dev/null
		sed -i '/^ISOLATED_CPU=/d' "/etc/wavelet.conf"
		echo "ISOLATED_CPU=\"$isolated\"" >> "/etc/wavelet.conf"
		echo "	Isolated cores $isolated for media processing."
	fi
	# PAM fallback for login sessions (systemd user units use the drop-in above;
	# this covers any PAM-authenticated session path so the grants are consistent).
	mkdir -p "/etc/security/limits.d"
	cat > "/etc/security/limits.d/99-wavelet.conf" <<-EOF
		wavelet  -  rtprio    50
		wavelet  -  memlock   512M
	EOF
}


####
#
# Main
#
####


source "/etc/wavelet.conf"
ETCDENDPOINT="https://$SVR_HOSTNAME:2379"
# Same CA will be installed in /etc/ipa/ca.crt after domain enrollment
ETCDCTL_CACERT="/var/home/wavelet/config/ca.crt"
hostNameSys="$(hostname -f)"
active_networkInterface=""
if [[ -z "$active_networkInterface" ]]; then
	active_networkInterface="$(ip -4 route show default | awk '/default via/{print $5; exit}' 2>/dev/null)"
fi
if [[ -z "$active_networkInterface" ]] && command -v nmcli &> /dev/null; then
	# Try to find an Ethernet interface first
	active_networkInterface="$(nmcli -t -f DEVICE con show --active | grep -E '^(eth|enp)' | head -n 1)"
	# If no Ethernet found, fall back to the first active connection (Wi-Fi/Other)
	if [[ -z "$active_networkInterface" ]]; then
		active_networkInterface="$(nmcli -t -f DEVICE con show --active | head -n 1)"
	fi
fi
if [[ -z "$active_networkInterface" ]]; then
	active_networkInterface="$(ip -4 addr show scope global | awk '/inet /{split($NF,a,"@"); print a[1]; exit}' 2>/dev/null)"
	echo "Warning: Using last-resort interface detection: $active_networkInterface"
fi
if [[ -z "$active_networkInterface" || "$active_networkInterface" == "lo" ]]; then
	echo "ERROR: Could not detect a valid network interface. Aborting DNS reconfiguration."
	return 1
fi
gateway="$SVR_GW"
# IP and MAC Data for this host
myIPAddr="$(hostname -I | xargs)"
myMACAddr="$(nmcli -e no -g GENERAL.HWADDR dev show "$active_networkInterface")"

if [[ -z "$DC1_IP" ]]; then
	echo "	No domain controller IP address has been configured!"
	exit 1
fi

mkdir -p "/var/home/wavelet/logs"
mkdir -p "/var/home/wavelet/setup"

exec > "/var/home/wavelet/logs/install_client.log" 2>&1

# generate proper RC files for root/wavelet-root which gives us aliases and powerline
cd /root || return; rm .bashrc .bash_profile; cp /etc/skel/{.bashrc,.bash_profile} .
cd /var/home/wavelet-root || return; rm .bashrc .bash_profile; cp /etc/skel/{.bashrc,.bash_profile} .

# Fix AVAHI otherwise NDI won't function correctly, amongst other things
# https://www.linuxfromscratch.org/blfs/view/svn/basicnet/avahi.html
# Runs first because it doesn't matter what kind of server/client device, it'll need this.
cat > "/etc/dbus-1/system.d/org.freedesktop.avahi.conf" << EOF
<!DOCTYPE busconfig PUBLIC
		  "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
		  "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <!-- Only root or user avahi can own the Avahi service -->
  <policy user="avahi">
	<allow own="org.freedesktop.Avahi"/>
  </policy>
  <policy user="root">
	<allow own="org.freedesktop.Avahi"/>
  </policy>
  <!-- Allow anyone to invoke methods on Avahi server, except SetHostName -->
  <policy context="default">
	<allow send_destination="org.freedesktop.Avahi"/>
	<allow receive_sender="org.freedesktop.Avahi"/>
	<deny send_destination="org.freedesktop.Avahi"
		  send_interface="org.freedesktop.Avahi.Server" send_member="SetHostName"/>
  </policy>
  <!-- Allow everything, including access to SetHostName to users of the group "adm" -->
  <policy group="adm">
	<allow send_destination="org.freedesktop.Avahi"/>
	<allow receive_sender="org.freedesktop.Avahi"/>
  </policy>
  <policy user="root">
	<allow send_destination="org.freedesktop.Avahi"/>
	<allow receive_sender="org.freedesktop.Avahi"/>
  </policy>
</busconfig>
EOF
groupadd -fg 84 avahi && useradd -c "Avahi Daemon Owner" -d /run/avahi-daemon -u 84 -g avahi -s /bin/false avahi
groupadd -fg 86 netdev
mkdir -p "/var/lib/avahi/services"
systemctl enable avahi-daemon.service --now # May fail, but will correctly start next reboot
systemctl restart gssproxy.service

# Add haveged selinux policy
if [[ -f "/var/lib/wavelet/selinux/my-haveged.pp" ]]; then
    semodule -i "/var/lib/wavelet/selinux/my-haveged.pp"
fi
# Prevent NetworkManager from randomizing device MAC Addresses, which can interfere with WiFi EAP-TLS authentication
cat > "/etc/NetworkManager/conf.d/30-mac-randomization.conf" <<-EOF
	[device-mac-randomization]
	wifi.scan-rand-mac-address=no
	wifi.connect-rand-mac-address=no

	[connection]
	# Explicitly disable all MAC randomization for all connections
	# This ensures the real MAC is always used for RADIUS authentication
	wifi.mac-address-blacklist=

	[device]
	# Match all WiFi devices
	wifi.mac-address=
EOF

# Ensure other system services are active
systemctl enable certmonger.service

install_security_layer
configure_firewall

# Generate UltraGrid squashfs dir so we don't need to worry about FUSE for some uses (reflector/hd-rum-translator)
# This shaves about 500ms off cold start time.
mkdir -p "/usr/local/bin/ultragrid" && cd "/usr/local/bin/ultragrid"
/usr/local/bin/UltraGrid.AppImage --appimage-extract
echo "	Extracted AppImage contents available in /usr/local/bin/ultragrid/squashfs-root/ - to invoke call the AppRun binary."

# Disable self so we don't run again on the next boot.
systemctl set-default graphical.target
echo "CLIENT_INSTALL_COMPLETE=1" >> "/etc/wavelet.conf"
generate_wavelet_userspace_services
systemctl --user -M wavelet@ daemon-reload

# We need to copy the serverhostname and provision credentials to wavelet for ETCD provisioning
cp "/var/root/secrets/provisionpw" "/var/home/wavelet/config"
chown -R wavelet:wavelet "/var/home/wavelet"

# Generate our /var/lib and assign perms
mkdir -p /var/lib/wavelet; chown wavelet:wavelet "/var/lib/wavelet"

# Generate the persistent ramdisk
mkdir -p "/var/wavelet_ramfs"
cat > "/etc/systemd/system/var-wavelet_ramfs.mount" <<-EOF
	[Unit]
	Description=Wavelet user ramdisk (tmpfs) for UltraGrid binaries

	[Mount]
	What=tmpfs
	Where=/var/wavelet_ramfs
	Type=tmpfs
	RequiresMountsFor=/var/wavelet_ramfs
	# Mount options:
	#   size=1G     - cap at 1GiB (1073741824 bytes); tmpfs reports actual used
	#   mode=0755   - directory permissions after mount
	#   defaults    - standard mount options
	#   nosuid      - ignore setuid/setgid bits (security)
	#   nodev       - block creation of device files
	#   noatime     - avoid atime updates (reduces writes)
	Source=tmpfs
	Options=size=1G,nosuid,nodev,noatime,mode=0755

	[Install]
	WantedBy=multi-user.target
EOF
cat > "/etc/systemd/system/wavelet_copyfiles.service" <<-EOF
	[Unit]
	Description=Copies binaries from /usr/local/bin to ramdisk
	After=var-wavelet_ramfs.mount
	Wants=var-wavelet_ramfs.mount

	[Service]
	ExecStart=/usr/bin/bash -c 'cp -a /usr/local/bin/* /var/wavelet_ramfs/'

	[Install]
	WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now var-wavelet_ramfs.mount wavelet_copyfiles.service

optimize_latency "$active_networkInterface"
rpm-ostree initramfs --enable

# Run connectwifi to configure our 802.1x WiFi connectivity.. (will fail if no EAP-TLS certs from DC1!)
/usr/local/bin/connectwifi.sh
echo "	Client setup steps completed, moving to start user setup steps.."

# Ensure we disable this service so that it does not execute again on next reboot
systemctl disable wavelet_install_client.service
rm -rf /etc/systemd/system/wavelet_install_client.service
systemctl restart getty@tty1