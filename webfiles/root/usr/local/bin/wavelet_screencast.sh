#!/bin/bash
# Screencast (Miracast / WFD) lifecycle helper.
# Invoked by wavelet_client_controller.sh's toggle_screencast / authorize_screencast.
#
# Sub-commands:
#   up   <iface>    bring up P2P GO + sinkctl, arm WPS-PBC
#   auth <iface>    release the M7 gate so RTP starts flowing
#   down <iface>    tear everything down, return iface to NM
#   status <iface>  echo "up"/"down"
#	capable			checks for capability on this system (extra devs)
#   -dev=$DEVICE	configures the device name for P2P Wi-Di

set -euo pipefail

ETCDINTERACTIONHOOKS=""
if [[ -f /var/wavelet_ramfs/etcd_interaction_hooks.sh ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source /usr/local/bin/etcd_interaction_hooks.sh
	ETCDINTERACTIONMOD="/usr/local/bin/etcd_interaction_hooks.sh"
fi

CMD="${1:?usage: wavelet_screencast.sh up|auth|down|status <iface>}"
IFACE="${2:?iface required}"
SOCKDIR="/run/wavelet_wpa"
FLAGDIR="/var/home/wavelet/config/screencast"
WPA_CONF="/etc/wavelet/wpa_p2p_${IFACE}.conf"

wpacli() { wpa_cli -p "$SOCKDIR" -i "$IFACE" "$@"; }

cmd_up() {
	mkdir -p "$FLAGDIR" "$SOCKDIR" /etc/wavelet
	# 1. Detach the iface from NM.
	configure_wifi_device "$IFACE"
	# 2. Render config (idempotent).
	if [[ ! -f "$WPA_CONF" ]]; then
		sudo tee "$WPA_CONF" >/dev/null <<-EOF
			ctrl_interface=${SOCKDIR}
			ctrl_interface_group=wavelet
			update_config=1
			device_name=Wavelet-$(hostname -s)
			device_type=7-0050F204-1
			p2p_go_intent=15
			p2p_go_ht40=1
			country=US
		EOF
	fi
	# 3. Start templated supplicant unit.
	systemctl start "wavelet-wpa@${IFACE}.service"
	# 4. Wait for ctrl socket.
	local tries=0
	until [[ -S "${SOCKDIR}/${IFACE}" ]] || (( tries > 50 )); do
		sleep 0.1; ((tries++))
	done
	[[ -S "${SOCKDIR}/${IFACE}" ]] || { echo "ctrl socket never appeared"; return 1; }
	# 5. Form group + arm WPS.
	wpacli p2p_group_add persistent >/dev/null
	wpacli wps_pbc >/dev/null
	local goIface
	goIface=$(wpacli interfaces | awk '/^p2p-/{print; exit}')
	echo "$goIface" > "$FLAGDIR/go.iface"
	# 6. Start sinkctl. It'll wait for a peer, then block on M7 until /flags/authorized exists.
	#    Output is RTP/MP2T to loopback 5004; UltraGrid picks it up after auth.
	systemctl start "wavelet-sinkctl@${goIface}.service"
}

cmd_auth() {
	# The sinkctl wrapper polls for this file before completing the WFD trigger.
	: > "$FLAGDIR/authorized"
}

cmd_down() {
	local goIface; goIface="$(cat "$FLAGDIR/go.iface" 2>/dev/null || true)"
	[[ -n "$goIface" ]] && systemctl stop "wavelet-sinkctl@${goIface}.service" || true
	systemctl stop "wavelet-wpa@${IFACE}.service" || true
	# Return the iface to NetworkManager so it's available for normal use again.
	nmcli device set "$IFACE" managed yes || true
	rm -f "$FLAGDIR"/{go.iface,go.status,authorized,device.connected,inputstream}
}

cmd_status() {
	if systemctl is-active --quiet "wavelet-wpa@${IFACE}.service"; then echo up; else echo down; fi
}

event_check_screenCast_capable(){
	# checks for screenCasting capable WiFi Display/Chromecast/Apple Play devices
	local wifiAdapters=()
	local wifiAdapterID
	# nmcli dev status type=wireless
	# remove the adapter connected to the wavelet system from this list
	# interrogate available adapters for WiDi capability
	# iw dev / iw phy | grep "P2P-device" "P2P-client"
	echo "	Checking for Wi-Di capability in network adapter.."
	# Get the currently active WiFi adapter (the one Wavelet is using)
	local activeWifiDevice
	activeWifiDevice=$(nmcli -g DEVICE connection show --active | grep -E 'wlan[0-9]|wl[0-9]' | head -n1)
	# Enumerate all WiFi devices that are available
	while read -r device; do
		[[ -z "$device" ]] && continue
		# Skip the device that's currently in use
		[[ "$device" == "$activeWifiDevice" ]] && continue
		# Check if this adapter supports P2P
		if iw dev "$device" info 2>/dev/null | grep -qi "P2P"; then
			wifiAdapters+=("$device")
		fi
	done < <(nmcli -t -f DEVICE,TYPE dev status | awk -F: '$2=="wifi"{print $1}')
	if [[ "${#wifiAdapters[@]}" -gt 0 ]]; then
		# PERFORM CAPABILITY CHECK for Wi-Di/MiraCast
		capableDevs=()
		for i in "${wifiAdapters[@]}"; do
			wifiResult="$(iw phy | grep -A 20 'Supported interface modes:')"
			# Adapter must support both AP and HT40 capability
			if [[ "$wifiResult" == *"P2P-client"* ]] && [[ "$wifiResult" == *"P2P-GO"* ]]; then
				capableDevs+=("$i")
			fi
		done
		echo "	Found ${#capableDevs[@]} additional WiFi adapter(s) for screenCasting."
		KEYNAME="/HOSTS/$(hostname)/control/screenCastCapable"; KEYVALUE="${capableDevs[0]}"; write_etcd_global &
	else
		echo "	No additional WiFi adapters available for screenCasting."
	fi
}

configure_wifi_device(){
	# Releases the named interface from NetworkManager's control
	# Reversed by `nmcli device set ... managed yes` in cmd_down().
	local iface="$1"
	if [[ -z "$iface" ]]; then
		echo "	configure_wifi_device: iface argument required" >&2
		return 2
	fi
	# Disconnect first - if NM has it up with an IP, going straight to
	# 'managed no' leaves the link in a half-released state and supplicant
	# can fail to claim it cleanly.
	nmcli device disconnect "$iface" >/dev/null 2>&1 || true
	nmcli device set "$iface" managed no
	iw dev "$iface" interface add "p2p-$iface" type __ap
	# generate a 4 char pin from /dev/urandom - this changes on each enablement.
	p2p_pin="$()"
	# Generate conf file (just for testing here, it needs rootful)
	cat > "/etc/wavelet/wpa_p2p-$iface.conf" <<- EOF
		ctrl_interface=/run/wavelet_wpa
		ctrl_interface_group=wavelet
		update_config=1
		device_name=Wavelet-$hostNameSys
		device_type=7-0050F204-1
		driver_param=use_p2p_group_interface=1
		ap_scan=1
		p2p_go_intent=15
		p2p_go_ht40=1
		country=US
		config_methods=keypad display pin pbc
	EOF
	supplicant_output="$(mktemp)"
	# Run supplicant only on p2p interface and direct output to a file
	wpa_supplicant -i "p2p-$iface" -c "/etc/wavelet/wpa_p2p-$iface.conf" -D nl80211 -B
	# verify socket exists
	if [[ ! -f "/run/wavelet_wpa/p2p-$iface" ]]; then
		echo "	ERR:  wpa_supplicant did not create proper interface socket!"
	fi
	# Set connection
	wpa_cli -p /run/wavelet_wpa -i "$iface" set device_type 7-0050F204-1
	wpa_cli -p /run/wavelet_wpa -i "$iface" set p2p_go_ht40 1
	wpa_cli -p /run/wavelet_wpa -i "$iface" wfd_subelem_set 0 000600111c44012c
	wpa_cli -p /run/wavelet_wpa -i "$iface" wfd_subelem_set 1 0006000000000000
	wpa_cli -p /run/wavelet_wpa -i "$iface" wfd_subelem_set 6 000700000000000000
	wpa_cli -p /run/wavelet_wpa -i "$iface" p2p_listen
	wpa_cli p2p_group_add -p /run/wavelet_wpa -i "$iface" persistent
	# When a device connects, get its hostname+IP+any other info and write to UI.
	deviceHostName=""
	deviceMACAddress=""
	otherUsefulDeviceInfo=""
	cat > /var/home/wavelet/config/screencast/device.connected <<-EOF
		$deviceHostName:$deviceMACAddress:$otherUsefulDeviceInfo
	EOF
	# The client controller subshell in this instance should be waiting for this connection attempt
	# it may be better to handle this blocking operation someplace else
	# The controller will parse this data, and then write it up to etcd so we get the authorize widget.
	# Then another watch event will trigger authorize_screencast in the client_controller.sh, finishing the process.
	# The device.connected file will be removed if the connection is terminated, and the process must be repeated.
}

logName=/var/home/wavelet/logs/screencast.log
exec >> "$logName" 2>&1
hostNameSys="$(hostname)"
case "$CMD" in
	up) cmd_up ;;
	auth) cmd_auth ;;
	down) cmd_down ;;
	status) cmd_status ;;
	capable) event_check_screenCast_capable ;;
	-dev=*) configure_wifi_device "${CMD#*=}";;
	*) echo "unknown subcommand $CMD" >&2; exit 2 ;;
esac