#!/bin/bash
# This file concatenates appropriate command line values and passes them to a user systemd unit
# It is triggered by any change in /HOSTS/$hostName/DECODER_SUB_LIST
# This only handles requests for UltraGrid video sources, the clients themselves should know if its NDI/RTSP/other
# So if this has been called by an orchestrator/client_controller update request, all that checking has been done already.

# This reflector wrapper implementation REQUIRES patches from the patched UG build:
# https://github.com/CESNET/UltraGrid/pull/489
# https://github.com/armelvil/UltraGrid
# it will NOT work with the vanilla UltraGrid hd-rum-transcode implementation!!

# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
ETCDINTERACTIONHOOKS=""
if [[ -f /var/wavelet_ramfs/etcd_interaction_hooks.sh ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
	ETCDINTERACTIONHOOKS="/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source /usr/local/bin/etcd_interaction_hooks.sh
	ETCDINTERACTIONHOOKS="/usr/local/bin/etcd_interaction_hooks.sh"
fi

ETCDINTERACTIONMOD=""
if [[ -f /var/wavelet_ramfs/etcd_interaction_hooks.sh ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/var/wavelet_ramfs/wavelet_etcd_interaction.sh"
else
	source /usr/local/bin/etcd_interaction_hooks.sh
	ETCDINTERACTIONMOD="/usr/local/bin/wavelet_etcd_interaction.sh"
fi


test_etcd(){
	if [[ $("$ETCDINTERACTIONMOD" "check_status") != *"OK"* ]]; then
		sleep .1
		test_etcd
	else
#		echo "etcd test success! continuing.."
		return 0
	fi
}

add_client_port_patched(){
    # Adds the client port directly.
    echo "		Adding client IP: $1"
    nc -w 1 '127.0.0.1' 6159 <<<"root create-port $1:5004"
}

delete_client_port_patched(){
    echo "		Deleting client IP: $1"
    nc -w 1 127.0.0.1 6159 <<<"root delete-port $1:5004"
}

list_client_port(){
	echo "		Current client list:"
    nc -w 1 127.0.0.1 6159 <<<"list-ports"
}

# Extract the IP addresses currently configured on the reflector control port.
# The control API returns a table like:
#   200 OK
#   Ports:
#
#   Idx IP Address (AF_INET6)                      Port  Type
#   [0] [::ffff:192.168.1.8]:5004                  5004  forwarding
# We parse only the bracketed [N] rows and normalize the IPv4-mapped
# [::ffff:a.b.c.d] form down to a bare dotted-quad.
# NOTE: occurrences are NOT de-duplicated, so the deletion pass can clear every
# stale/duplicate port for an unsubscribed IP.
current_reflector_clients(){
    local raw rows entry
    raw="$(list_client_port)"
    # Keep only the bracketed [N] data rows, then pull the dotted-quad out of
    # the IPv4-mapped form "[::ffff:a.b.c.d]:port".
    rows="$(sed -n 's/^\[[0-9]*\] \[::ffff:\([0-9.]*\)\].*/\1/p' <<<"$raw")"
    while read -r entry; do
        [[ -n "$entry" ]] && printf '%s\n' "$entry"
    done <<<"$rows"
}

# Build the set of IPs etcd says should currently be subscribed.
desired_reflector_clients(){
    KEYNAME="/HOSTS/$hostNameSys/DECODER_SUB_LIST/"; read_etcd_prefix_values
    # read_etcd_prefix_values returns one IP per line (print-value-only).
    printf '%s\n' "$printvalue" | sed '/^[[:space:]]*$/d' | sort -u
}

# Reconcile the reflector control port against the authoritative DECODER_SUB_LIST.
# This is the single source of truth for membership. It is idempotent and
# self-healing: it removes stale/duplicate ports (e.g. clients whose unsubscribe
# event was missed, or who changed IP) and adds any that are missing.
reconcile_clients(){
    local desired present ip
    mapfile -t desired <<< "$(desired_reflector_clients)"
    # Present/actual occurrences (may contain duplicates for the same IP).
    mapfile -t present <<< "$(current_reflector_clients)"

    echo "	Reconciling reflector client list against DECODER_SUB_LIST.."
    echo "		Desired: ${desired[*]:-<none>}"
    echo "		Actual:  ${present[*]:-<none>}"

    # Delete every actual port not in the desired set. Iterating raw occurrences
    # (not de-duplicated) ensures multiple stale/duplicate ports for the same
    # unsubscribed IP all get removed, so the zero-client check below can fire.
    for ip in "${present[@]:-}"; do
        [[ -n "$ip" ]] || continue
        if ! printf '%s\n' "${desired[@]:-}" | grep -qxF -- "$ip"; then
            delete_client_port_patched "$ip"
        fi
    done

    # Add any desired IP that has no port present at all (re-adds missed ones).
    for ip in "${desired[@]:-}"; do
        [[ -n "$ip" ]] || continue
        if ! printf '%s\n' "${present[@]:-}" | grep -qxF -- "$ip"; then
            add_client_port_patched "$ip"
        fi
    done
}

init_reflector(){
	# Initialize reflector if not running
	echo "$(date): Initializing reflector, clients will be added via control port API" >> "$log_file"
	ugVidArgs="--tool hd-rum-transcode --control-port 6159 1M 5004"
	KEYVALUE="$ugVidArgs"; KEYNAME="/HOSTS/$hostNameSys/REFLECTOR_ARGS"; write_etcd_global &
	ugAudArgs="--tool hd-rum-transcode --control-port 6158 1M 5006"
	KEYVALUE="$ugAudArgs"; KEYNAME="/HOSTS/$hostNameSys/AUDIO_REFLECTOR_ARGS"; write_etcd_global &
	generate_reflector_systemd_units
	KEYNAME="/HOSTS/$hostNameSys/RELOAD_REFLECTOR"; KEYVALUE=0; write_etcd
	subscribe_clients
}

subscribe_clients(){
	# Called from init and runs a full list of clients in DECODER_SUB_LIST
	# Full membership reconciliation against the authoritative DECODER_SUB_LIST.
	reconcile_clients
}

generate_reflector_systemd_units(){
	# TBD we should look into using hd-rum-av.sh instead for a combined reflector.
	if [[ -z "$ugVidArgs" ]] || [[ -z "$ugAudArgs" ]]; then
		echo "  Reflector arguments are not populated, we will not generate and start a reflector task at this time."
		exit 0
	fi
	local binaryPath
    if [[ -f "/var/wavelet_ramfs/ultragrid/squashfs-root/AppRun" ]]; then
    	binaryPath="/var/wavelet_ramfs/ultragrid/squashfs-root/AppRun"
    else
    	binaryPath="/usr/local/bin/ultragrid/squashfs-root/AppRun"
    fi
    echo "	Generating Video and Audio reflectors with args: "
    echo "		$ugVidArgs"
    echo "		$ugAudArgs"
	cat > /home/wavelet/.config/systemd/user/UltraGrid.Reflector.service <<-EOF
		[Unit]
		Description=UltraGrid AppImage Reflector
		After=network-online.target
		Wants=network-online.target UltraGrid.Audio.Reflector.service

		[Service]
		ExecStart=${binaryPath} $ugVidArgs
		Type=simple
		KillMode=control-group
		KillSignal=SIGTERM
		TimeoutStopSec=5

		[Install]
		WantedBy=default.target
		EOF
	# Audio reflector
	cat > /home/wavelet/.config/systemd/user/UltraGrid.Audio.Reflector.service <<-EOF
		[Unit]
		Description=UltraGrid AppImage Audio Reflector
		After=network-online.target
		Wants=network-online.target

		[Service]
		ExecStart=${binaryPath} $ugAudArgs
		Type=simple
		KillMode=control-group
		KillSignal=SIGTERM
		TimeoutStopSec=5

		[Install]
		WantedBy=default.target
		EOF
	systemctl --user daemon-reload
	systemctl --user restart \
		UltraGrid.Reflector.service
}


#####
#
# Main
#
#####


start_timer
trap 'stop_timer "$timer_id_out"; echo "Total: ${timer_duration}s" >&2' EXIT

log_file="/var/home/wavelet/logs/reflector.log"
exec >> "$log_file" 2>&1
# Check for etcd connectivity before proceeding
test_etcd
#echo "ENV:"
#(env)
hostNameSys="$(hostname)"
triggerKey="${ETCD_WATCH_KEY//\"}"
triggerValue="${ETCD_WATCH_VALUE//\"}"
triggerType="${ETCD_WATCH_EVENT_TYPE//\"}"
triggerHostName="${triggerKey##*/}"

if [[ "$1" == "INIT" ]]; then
	# We got called from the encoder and need to run a full init and client add anyway
	triggerKey=""
	triggerValue=""
	# bring up reflector systemd unit
	init_reflector
	# subscribe_clients inside init_reflector already reconciled membership.
	reconciled=1
else
	# ensure the services are started
	systemctl --user start UltraGrid.Reflector.service
	systemctl --user start UltraGrid.Audio.Reflector.service
fi


# Any put/delete on DECODER_SUB_LIST triggers a full reconciliation.
# This is deliberately a full re-sync rather than a targeted add/delete:
# incremental ops drift (missed events, duplicate ports, clients that changed IP
# or unsubscribed without a clean DELETE), and the stale ports left behind then
# fool the zero-client check below and keep the encoder running forever.
if [[ "${reconciled:-0}" != "1" ]]; then
	reconcile_clients
fi

# This always runs last:
# Perform a check for zero clients and start a timer for the encoder to terminate
WAVELET_SHUTDOWN_MOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_encoder_shutdown_timer.sh" ]]; then
	WAVELET_SHUTDOWN_MOD="/var/wavelet_ramfs/wavelet_encoder_shutdown_timer.sh"
else
	WAVELET_SHUTDOWN_MOD="/usr/local/bin/wavelet_encoder_shutdown_timer.sh"
fi
clients="$(list_client_port)"
if [[ "$clients" == *"No ports configured."* ]]; then
	echo "	No clients listed!  initiating encoder shutdown timer"
	KEYNAME="/HOSTS/$hostNameSys/control/GROUP"; read_etcd_global; groupHash="$printvalue"
	KEYNAME="/UI/GROUPS/$groupHash/control/encoderTimeout"; read_etcd_global; timeoutMinutes="$printvalue"
	# timeoutMinutes is in minutes, convert to seconds
	timeoutSeconds="${timeoutMinutes:-24}"
	timeoutSeconds=$((timeoutSeconds * 60))
	# Ensure minimum timeout of 300 seconds (5 minutes) if timeoutMinutes is 0
	if [[ "$timeoutSeconds" -lt 300 ]]; then
		timeoutSeconds=300
	fi
	echo "$(($(date +%s) + timeoutSeconds))" > /var/tmp/encoder_shutdown_at
	"$WAVELET_SHUTDOWN_MOD" &
	echo $! > /var/home/wavelet/config/encoder_shutdown_timer.pid
else
	echo "	Clients still subscribed, terminating any active timers for the encoder."
    pid=$(cat /var/home/wavelet/config/encoder_shutdown_timer.pid 2>/dev/null)
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid"
        rm -f /var/home/wavelet/config/encoder_shutdown_timer.pid
        echo "$(date): encoder_shutdown_timer.sh terminated (PID $pid)" >&2
    fi
    rm -f /var/tmp/encoder_shutdown_at
fi