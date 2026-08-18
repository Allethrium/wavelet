#!/bin/bash
# encoder_shutdown_watcher.sh

log_file="/var/home/wavelet/logs/shutdown_encoder.log"
exec >> "$log_file" 2>&1

ETCDINTERACTIONHOOKS=""
if [[ -f "/var/wavelet_ramfs/etcd_interaction_hooks.sh" ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source "/usr/local/bin/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/usr/local/bin/etcd_interaction_hooks.sh"
fi

trap 'echo "$(date): encoder_shutdown_timer.sh exited gracefully (PID $$)" >&2' EXIT

encoder_shutdown(){
	systemctl --user stop UltraGrid.Encoder.service
	systemctl --user stop UltraGrid.Reflector.service
	echo "$(date): Encoder process stopped - timeout expired, zero subscribers." >> "$log_file"
	rm -f /var/tmp/encoder_shutdown_at
	KEYNAME="/HOSTS/$(hostname)/control/healthStatus"; KEYVALUE="OK: ENCODER SHUTDOWN TIMEOUT"; write_etcd_global &
	exit 0
}


shutdown_at="$(cat /var/tmp/encoder_shutdown_at)"
echo "Watching $KEYNAME for activity with termination time set to: $shutdown_at"
source "$HOME/config/$(hostname).conf"

KEYNAME="/UI/HOSTS/$GROUP_HASH/control/encoderTimeout"; read_etcd_global
timerIncrement=0
encoderTimeoutSeconds=0
if [[ -z "$printvalue" ]]; then
	# default 10 minutes in seconds
	encoderTimeoutSeconds=600
else
	# etcd returns the value as a string; force integer with $(( ))
	# UI inputs MINUTES, so convert to SECONDS (x60)
	encoderTimeoutSeconds=$(( printvalue * 60 ))
fi
KEYNAME="/HOSTS/$(hostname)/DECODER_SUB_LIST/"
while true; do
    count="$(read_etcd_prefix_keys | wc -l)"
    if (( count > 0 )); then
        rm -f "/var/tmp/encoder_shutdown_at"
        pid="$(cat /var/home/wavelet/config/encoder_shutdown_timer.pid 2>/dev/null)"
    	echo "Client added to decoder_sub_list, ending process PID: $pid" >> $log_file
        kill -TERM "$pid"
        exit 0
    fi
    sleep 1
    if [[ "$timerIncrement" -gt "$encoderTimeoutSeconds" ]]; then
    	encoder_shutdown
    fi
    case "$timerIncrement" in
    	60)
    		echo "	Inactive 1 Minute..";;
    	120)
    		echo "	Inactive 2 Minutes..";;
  		180)
  			echo "	Inactive 3 Minutes..";;
 		240)
 			echo "	Inactive 4 Minutes..";;
		300)
			echo "	Inactive 5 Minutes, no further notes will be added until timer exceeds value";;
		*) ;;
	esac
	(( timerIncrement++ ))
done