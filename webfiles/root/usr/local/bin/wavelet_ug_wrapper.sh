#!/bin/bash
# Wrapper for UltraGrid Decoder
# Handles logging and feedback to the unit's healthStatus.
# This will improve in future with some self-healing capability to troubleshoot common failureModes

ETCDINTERACTIONHOOKS=""
if [[ -f "/var/wavelet_ramfs/etcd_interaction_hooks.sh" ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source "/usr/local/bin/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/usr/local/bin/etcd_interaction_hooks.sh"
fi


cleanup(){
    local sig="${1:-EXIT}"
    echo "Cleanup triggered by $sig - terminating all processes..." >&2
    # Kill processes in parallel
    for pid in "$SWAYIMG_PID" "$NC_PID" "$TAIL_PID" "$UG_PID"; do
        [[ $pid -gt 0 ]] && kill -0 "$pid" 2>/dev/null && kill -TERM "$pid" &
    done
    # Wait for graceful exit
    wait
    # Force kill if still alive
    for pid in "$SWAYIMG_PID" "$NC_PID" "$TAIL_PID" "$UG_PID"; do
        [[ $pid -gt 0 ]] && kill -0 "$pid" 2>/dev/null && kill -9 "$pid" &
    done
    wait
    # Cleanup temp file
    [[ -f "$UG_LOG_FILE" ]] && rm -f "$UG_LOG_FILE"
    /bin/systemd-notify "STOPPING=1"
}

handle_signal() {
	# Trap handler for all signals
    local sig="$1"
    echo "Received $sig - systemd watchdog timeout!" >&2
    /bin/systemd-notify "STOPPING=1"
    exit 1
}

start_ultragrid(){
	set -x
	# ~/.config/sway/config contains system-level settings for where the UltraGrid window should go
	# In UI Mode, top-left, in normal mode, fullscreen.
	# Note that the UG_ARGUMENTS parsed from the client controller are also different here
    timeout=5
    rm -f /var/home/wavelet/config/errorState.flag
    # Get sway socket and move the UltraGrid window to workspace 2 (2nd monitor if one exists, or 2nd workspace on primary monitor)
	swaySocket="$(ls "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/sway-ipc.*.sock 2>/dev/null | xargs -I{} sh -c 'swaymsg -s {} -t get_tree >/dev/null 2>&1 && echo {}')"
    [[ -z "$swaySocket" ]] && swaySocket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    while ! swaymsg -t get_tree -s "$swaySocket" | jq -e '.nodes[] | select(.name? == "2")' >/dev/null 2>&1; do
		sleep 0.1
		timeout=$((timeout - 1))
		[[ $timeout -le 0 ]] && break
	done
    swaymsg -s "$swaySocket" workspace 2
    local binaryPath
    if [[ -f "/var/wavelet_ramfs/ultragrid/squashfs-root/AppRun" ]]; then
    	binaryPath="/var/wavelet_ramfs/ultragrid/squashfs-root/AppRun"
    else
    	binaryPath="/usr/local/bin/ultragrid/squashfs-root/AppRun"
    fi
    "$binaryPath" "${UG_ARGUMENTS[@]}" > "$UG_LOG_FILE" 2>&1 &
	systemd-notify "READY=1"
	echo "	UltraGrid AppImage started successfully!"
	send_keepalive
	# Wait for UltraGrid window to appear before issuing swaymsg commands
	waitTimeout=5
	while ! swaymsg -t get_tree -s "$swaySocket" | jq -e '.nodes[] | select(.app_id? == "uv")' >/dev/null 2>&1; do
		sleep 0.1
		waitTimeout=$((waitTimeout - 1))
		[[ $waitTimeout -le 0 ]] && break
	done
	swaymsg -s "$swaySocket" "[app_id=\"uv\"] move container to workspace 2, fullscreen enable"
	init_switch
    set +x
}

send_keepalive(){
	# Send watchdog keepalive to systemd if everything looks good
	systemd-notify "WATCHDOG=1"
}

init_switch(){
	local channelIndex
	local errorMessage
	printvalue=""
	# channelData is compound of index-sourcehash (I.E 4-123456hashvalue)
	KEYNAME="/HOSTS/$(hostname)/control/channel-Source"; read_etcd_global; channelIndex="${printvalue%%-*}"
	if [[ -z "$channelIndex" ]]; then
		errorMessage="ERR:  Channel Index is null, retrying read then setting to static Image channel as fallback."
		notify-send -e "$errorMessage" & echo "$errorMessage"
		KEYNAME="/HOSTS/$(hostname)/control/channel-Source"; read_etcd_global; channelIndex="${printvalue%%-*}"
		if [[ -z "$channelIndex" ]]; then
			channelIndex=1
		fi
	fi
	systemd-notify "STATUS=Initializing switcher to channel $channelIndex"
	response=""
	port="6161"; controlPortCmd="capture.data $channelIndex"; netCat
	if [[ "$response" == *"400"* ]]; then
		# 400 Bad Request, means the channelIndex wasn't valid
		channelIndex=1; netCat
		KEYNAME="/HOSTS/$(hostname)/control/healthStatus"; KEYVALUE="ERR: Invalid Channel Index"; write_etcd_global &
	else
		echo -e "\033[32m	Switcher initialized, sending channel init!\033[0m" | systemd-cat -t "UltraGrid"
	fi
}

netCat(){
    # Simple function to submit data to netcat
    echo "Running:  nc -w 1 127.0.0.1 $port <<<$controlPortCmd"
    response="$(nc -w 1 127.0.0.1 "$port" <<<"$controlPortCmd")"
    NC_PID=$!
}

inputError(){
	# Handle input errors
	errorCase="$1"
	if [[ -z "$errorTimer_$1" ]]; then
		start_timer "errorTimer_$1"
		error_timers["$1"]="$timer_id_out"
		start_timer "badReset"
	else
		timer_elapsed="$(get_timer_elapsed "$errorTimer_$1")"
		if (( "$timer_elapsed" > 30 )); then
           	echo -e "\033[32m	Error: $1 exceeds 30 seconds!  Terminating process!\033[0m" | systemd-cat -t "UltraGrid"
           	# Serious > 30second error, we let the watchdog kill the process
			echo "1" > "$UG_RESTARTING"
			exit 1
		elif (( "$timer_elapsed" > 15 )); then
			send_keepalive
			generate_errorDisplay "ERR: $1"
			echo -e "\033[32m	Experiencing +15s of error: $1!\033[0m" | systemd-cat -t "UltraGrid"
		elif (( "$timer_elapsed" > 10 )); then
			echo "$errorCase" > /var/home/wavelet/config/errorState.flag
			echo -e "\033[32m	Experiencing error: $1!\033[0m" | systemd-cat -t "UltraGrid"
			decoder_checkSubscription
			send_keepalive
		elif (( "$timer_elapsed" > 5 )); then
			echo -e "\033[32m	Experiencing error: $1!\033[0m" | systemd-cat -t "UltraGrid"
		else
			send_keepalive
		fi
	fi
	if (( badCounter > 50 )); then
		echo "BURST_ERROR" > /var/home/wavelet/config/errorState.flag
		generate_errorDisplay "ERR: ERROR BURST DETECTED"
		send_keepalive
	fi
}

check_sourceHashStatus(){
    KEYNAME="/UI/GROUPS/$hostNameSys/control/sourceHashStatus"; read_etcd_global
    case "$printvalue" in
        2) echo "	Encoder is priming, waiting..."; encoderStatus=2 ;;
        1) echo "	Encoder ready."; encoderStatus=1 ;;
        3|*)
            # Encoder dead or unknown — trigger fallback
            inputError "ENCODER_DEAD"; encoderStatus=3
            ;;
    esac
}

decoder_checkSubscription(){
	# This function checks whether a decoder is supposed to be subscribed to a reflector, and if not unsubs.
	KEYNAME="/HOSTS/$hostNameSys/control/channel-Source"; read_etcd_global
	channelIndex="${printvalue%%-*}"; sourceHash="${printvalue##*-}"
	KEYNAME="/HOSTS/$hostNameSys/reflectorRequest"; read_etcd_global; reflectorHash="$printvalue"
	if [[ "$printvalue" == "$sourceHash" ]]; then
		echo "	Video source and reflector match, resetting channel index"
		check_sourceHashStatus
		if [[ $encoderStatus -eq 1 ]]; then
			port="6161"; controlPortCmd="capture.data $channelIndex"; netCat
			if [[ "$response" == *"400"* ]]; then
				# 400 Bad Request, means the channelIndex wasn't valid,.
				# Don't send keepalive and let decoder process regenerate ug servicefile.
				echo "	ERROR: supplied channel index invalid, allowing systemd unit regeneration."
				echo "1" > "$UG_RESTARTING"
				exit 1
			fi
		else
			# We wait until the source hash shows ready from the encoder
			local max_wait=60  # 6 seconds
			until [[ "$encoderStatus" == 1 ]] || (( wait_count >= max_wait )); do
				check_sourceHashStatus
				sleep 0.1
				((wait_count++))
			done
			if [[ "$encoderStatus" != 1 ]]; then
				inputError "ENCODER_TIMEOUT"
			fi
		fi
	else
		# The reflector and source hash do not match, this isn't an UltraGrid source and reflector is not necessary
		echo "	ERR: Video source hash and reflector do not match, unsubscribing from reflector!"
		send_keepalive
	fi
}

decoder_unSub(){
	# Send an unsubscribe request to a reflector
	local channelData; local channelIndex; local channelSourceHash
	# channelData is compound of index-sourcehash (I.E 4-123456hashvalue)
	KEYNAME="/HOSTS/$(hostname)/control/channelData"; channelData="$printvalue"
	channelIndex="${channelData%%-*}"
	channelSourceHash="${channelData##*-}"
	KEYNAME="/HOSTS/$(hostname)/unsubRequest"; KEYVALUE="$channelSourceHash"; write_etcd_global &
}

switcherError(){
	# This is called if we get a known switcher error message
	(( badSwitchCounter++ ))
	start_timer "badReset"
	echo "		Switcher error! remediating.."
	# we need to "do something here"
}

process_fecData(){
	# Video dec stats (cumulative): 893 total / 867 disp / 26 drop / 1 corr / 0 miss FEC noerr/OK/NOK: 892/0/1
	echo "	Processing Error Data: $line"
	# Here, we'd calculate the error ratio for FEC/dropped frames, and if above a certain threshhold, do something abt it.
}

reset_error_state(){
    echo "Resetting error state — stability detected" | systemd-cat -t "UltraGrid"
    rm -f /var/home/wavelet/config/errorState.flag
    badCounter=0
    goodCounter=0
    badSwitchCounter=0
    # Clear any timer-based error states
    for key in "${!error_timers[@]}"; do
        stop_timer "${error_timers[$key]}"
        unset "error_timers[$key]"
    done
    systemd-notify "STATUS=Stable"
}


#####
#
# Main
#
#####


#set -m
exec >>/var/home/wavelet/logs/UltraGrid.log 2>&1
UG_ARGUMENTS=("$@")
UG_PID=0
UG_RESTARTING="/var/home/wavelet/config/ug_restarting.flag"
SWAYIMG_PID=0
swaySocket=""
NC_PID=0
goodCounter=0
badCounter=0
sampleCounter=0
badSwitchCounter=0
declare -gA error_timers

trap 'handle_signal SIGINT'  SIGINT
trap 'handle_signal SIGTERM' SIGTERM
trap 'handle_signal SIGUSR1' SIGUSR1
trap 'stop_timer "$timer_id_out"; echo "Total: ${timer_duration}s" >&2' EXIT


# Note that each timer has a specific timer_id
start_timer

UG_LOG_FILE="$(mktemp)"
echo "Log Begin" > "$UG_LOG_FILE"
echo "	Starting up.." | systemd-cat -t "UltraGrid"
ln -sf "$UG_LOG_FILE" /var/home/wavelet/logs/ugDirect.log
start_ultragrid
start_timer "badReset"
exec 3< <(stdbuf -oL tail -n0 -F "$UG_LOG_FILE")
TAIL_PID=$!

echo -e "Reading log outputs..\nPID: $UG_PID\nLOG: $UG_LOG_FILE\n" | systemd-cat -t "UltraGrid"
while IFS= read -r line <&3; do
    if [[ -n "${error_timers[badReset]}" ]]; then
    	reset_timer_elapsed="$(get_timer_elapsed "badReset")"
    	if (( "$reset_timer_elapsed" > 30 )); then
    		badCounter=0
    		rm -rf /var/home/wavelet/config/errorState.flag
    		echo "Error counter reset - 30s of stability" | systemd-cat -t "UltraGrid"
    	fi
    fi
	if [[ "$goodCounter" -gt 100 ]]; then
		if [[ -f "/var/home/wavelet/config/errorState.flag" ]]; then
			echo "Noting system stability is good" | systemd-cat -t "UltraGrid"
			KEYNAME="/HOSTS/$(hostname)/control/healthStatus"; KEYVALUE="OK: "; write_etcd_global &
			reset_error_state
			goodCounter=0
		fi
	fi
#	echo -e "Good Counter: $goodCounter\nBad Counter: $badCounter"
	case "$line" in
		*[switcher]*frames*seconds*FPS*)
			(( goodCounter++ ))
			send_keepalive
			;;
		*[File*cap\.]*Rewinding*the*file\.*)
#			echo -e "\033[32m	Incoming file rewind detected!\033[0m" | systemd-cat -t "UltraGrid"
			(( goodCounter++ ))
			send_keepalive
			;;
		*\[video\ dec\.\]*New*incoming*video*format*)
#			echo -e "\033[32m	Incoming video successfully detected!\033[0m" | systemd-cat -t "UltraGrid"
			(( goodCounter++ ))
			send_keepalive
			;;
		*[Pbuf]*[video]*packets*received*0*lost,*max*loss*0)
			echo -e "\033[32m	Zero packet loss, sending keepalive!\033[0m" | systemd-cat -t "UltraGrid"
			echo -e "\033[32m	Zero packet loss, sending keepalive!\033[0m"
			(( goodCounter++ ))
			send_keepalive
			;;
		*[display]*Successfully*reconfigured*display*to*)
			if [[ -f "$UG_RESTARTING" ]]; then
				init_switch
				rm -f "$UG_RESTARTING"
			fi
			(( goodCounter++ ))
			send_keepalive
			;;
		*WARNING:*Selected*capture*card*was*not*found/)
			echo -e "\033[33m	UltraGrid is unable to start with bad command line!\033[0m" | systemd-cat -t "UltraGrid"
			echo "UG_BAD_CMDLINE" > /var/home/wavelet/config/errorState.flag
			generate_errorDisplay "FTL: BAD ULTRAGRID COMMAND LINE"
			echo "1" > "$UG_RESTARTING"
			exit 1
			;;
		*\[ug_input\]*Dropping*frame!)
			# In this case, we have an error caused by excl_init in UG and may need to send an unsub command
			inputError "UG_FRAMEDROP"
			;;
		*Setting*GL*size*\.)
			(( goodCounter++ ))
			;;
		*[switcher]*Switched*from*device*to*device*)
			echo -e "\033[33m	Switcher success!\033[0m"
			(( goodCounter++ ))
			;;
		*NDI*cap*frames*in*seconds)
			(( goodCounter++ ))
			;;
		*Vulkan*SDL3*frames*in*seconds*)
			(( goodCounter++ ))
			;;
		*[lavd]*Invalid*data*found*when*processing*input*)
			inputError "LAVC_DATA"
			;;
		*Your*computer*may*be*too*SLOW*to*play*this*!!!)
			send_keepalive
			echo -e "\033[33m	This client is struggling to decode the stream in a timely manner!\033[0m" | systemd-cat -t "UltraGrid"
			echo -e "\033[33m	Consider: Reducing resolution, framerate, a lighter video codev or using a faster hardware platform.\033[0m" | systemd-cat -t "UltraGrid"
			generate_errorDisplay "WARN: SLOW MACHINE"
			(( goodCounter++ ))
			;;
		*lavc*Failed*to*find*convert*to*!!!)
			send_keepalive
			generate_errorDisplay "ERR: FORMAT CONVERSION ERROR!"
			echo -e "\033[33m	UltraGrid is unable to convert pixel formats for this input!\033[0m" | systemd-cat -t "UltraGrid"
			;;
		*Video*dec*stats*cumulative*:*total*867*disp*drop*corr*miss*FEC*noerr*OK*NOK*)
			process_fecData "$line"
			;;
		*)
			((sampleCounter++))
			if (( sampleCounter % 50 == 0 )); then
				if [[ "$line" == *"Could"* ]]; then
					switcherError
				fi
			fi
			;;
	esac
done

wait "$UG_PID"
UG_EXIT_CODE=$?
echo "UltraGrid exited with code $UG_EXIT_CODE" | systemd-cat -t "UltraGrid"
trap 'cleanup SIGTERM' TERM
trap 'cleanup SIGINT'  INT