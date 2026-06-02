#!/bin/bash
# encoder_shutdown_watcher.sh

ETCDINTERACTIONHOOKS=""
if [[ -f "/var/wavelet_ramfs/etcd_interaction_hooks.sh" ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source "/usr/local/bin/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/usr/local/bin/etcd_interaction_hooks.sh"
fi

trap 'echo "$(date): encoder_shutdown_timer.sh exited gracefully (PID $$)" >&2' EXIT

while true; do
    count=$(read_etcd_prefix_keys | wc -l)
    if (( count > 0 )); then
        rm -f /var/tmp/encoder_shutdown_at
        exit 0
    elif [[ -f /var/tmp/encoder_shutdown_at ]]; then
        shutdown_at=$(cat /var/tmp/encoder_shutdown_at)
        now=$(date +%s)
        if (( now > shutdown_at )); then
            systemctl --user stop UltraGrid.Encoder.service
            echo "$(date): Encoder process stopped - timeout expired, zero subscribers." >&2
            exit 0
        fi
    fi
    sleep 15
done