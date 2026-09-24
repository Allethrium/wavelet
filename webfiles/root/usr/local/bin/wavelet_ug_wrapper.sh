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

if [[ -f "/var/wavelet_ramfs/ultragrid/squashfs-root/AppRun" ]]; then
	binaryPath="/var/wavelet_ramfs/ultragrid/squashfs-root/AppRun"
else
	binaryPath="/usr/local/bin/ultragrid/squashfs-root/AppRun"
fi

# Load the client's exports file.  This MUST exist for normal operation.
hostNameSys="$HOSTNAME"
source "/etc/wavelet.conf"
sourceFile="$HOME/config/$hostNameSys.conf"
if [[ -f "$sourceFile" ]]; then
	source "$sourceFile"
else
	echo "	ERR: Client configuration file is not available!  This indicates a provisioning error."
	exit 1
fi

cleanup(){
	local sig="${1:-EXIT}"
	trap - EXIT TERM INT USR1
	echo "Cleanup triggered by $sig - terminating child processes..." >&2
	/bin/systemd-notify "STOPPING=1"
	for pid in "$TAIL_PID" "$UG_PID"; do
		(( pid > 0 )) && kill -TERM "$pid" 2>/dev/null
	done
	# Give UG up to ~1s (TimeoutStopSec is 2s), then force.
	local i
	for (( i = 0; i < 10; i++ )); do
		kill -0 "$UG_PID" 2>/dev/null || break
		sleep 0.1
	done
	for pid in "$SWAYIMG_PID" "$TAIL_PID" "$UG_PID"; do
		(( pid > 0 )) && kill -KILL "$pid" 2>/dev/null
	done
	[[ -f "$UG_LOG_FILE" ]] && rm -f "$UG_LOG_FILE"
}


handle_signal(){
	echo "Received $1" >&2
	cleanup "$1"
	exit 1
}

start_ultragrid(){
	# ~/.config/sway/config contains system-level settings for where the UltraGrid window should go
	# In UI Mode, top-left, in normal mode, fullscreen.
	# Note that the UG_ARGUMENTS parsed from the client controller are also different here
	# Note this is a .5s timeout to start UG, not a 5second timeout.
    timeout=5
	if [[ -n "${ISOLATED_CPU:-}" ]]; then
		local cpuList="${ISOLATED_CPU//[[:space:]]/}"
		taskset -c "$cpuList" "$binaryPath" "${UG_ARGUMENTS[@]}" > /var/home/wavelet/logs/ugDirect.log 2>&1 &
	else
		"$binaryPath" "${UG_ARGUMENTS[@]}" > /var/home/wavelet/logs/ugDirect.log 2>&1 &
	fi
	UG_PID=$!
    if [[ -z "$swaySocket" ]]; then
        local runtimeDir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        for sock in "${runtimeDir}"/sway-ipc.*.sock; do
            # Verify it's a socket and that sway is actually responding on it
            if [[ -S "$sock" ]] && swaymsg -s "$sock" -t get_tree >/dev/null 2>&1; then
                swaySocket="$sock"
                break
            fi
        done
    fi
    # Get sway socket and move the UltraGrid window to workspace 2 (2nd monitor if one exists, or 2nd workspace on primary monitor)
	swaymsg -t get_tree 2>/dev/null | jq '.nodes[] | select(.name? == "uv")' >/dev/null 2>&1
    while ! swaymsg -t get_tree -s "$swaySocket" 2>/dev/null | jq -e '.nodes[] | select(.name? == "2")' >/dev/null 2>&1; do
		sleep 0.1
		timeout=$((timeout - 1))
		[[ $timeout -le 0 ]] && break
	done
	[[ -z "$swaySocket" ]] && swaySocket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    swaymsg -s "$swaySocket" workspace 2 >/dev/null 2>&1
	systemd-notify "READY=1"
	echo "	UltraGrid AppImage started successfully at: $EPOCHSECONDS"
	# SEND INITIAL KEEPALIVE FOR WATCHDOG HERE
	send_keepalive
	# Wait for UltraGrid window to appear before issuing swaymsg commands
	waitTimeout=5
	while ! swaymsg -t get_tree -s "$swaySocket" | jq -e '.nodes[] | select(.app_id? == "uv")' >/dev/null 2>&1; do
		sleep 0.1
		waitTimeout=$((waitTimeout - 1))
		[[ $waitTimeout -le 0 ]] && break
	done
	swaymsg -s "$swaySocket" "[app_id=\"uv\"] move container to workspace 2, fullscreen enable" >/dev/null 2>&1
	init_switch
}

send_keepalive(){
	# Rate-limited watchdog keepalive
	set -x
	(( EPOCHSECONDS - lastkeepalive < WATCHDOG_INTERVAL )) && return 0
	lastkeepalive=$EPOCHSECONDS
	systemd-notify "WATCHDOG=1"
	set +x
}

note_good(){
	(( goodCounter++ ))
	lastGoodLine=$EPOCHSECONDS
	send_keepalive
}

init_switch(){
	local channelIndex
	local errorMessage
	printvalue=""
	# channelData is compound of index-sourcehash (I.E 4-123456hashvalue)
	source "$HOME/config/$hostNameSys.conf"
	if [[ -z "$channelData" ]]; then
		KEYNAME="/HOSTS/$hostNameSys/control/channelData"; read_etcd_global; channelIndex="${printvalue%%-*}"
	else
		channelIndex="${channelData%%-*}"
	fi
	if [[ -z "$channelIndex" ]]; then
		printvalue=""
		KEYNAME="/HOSTS/$hostNameSys/control/channel-Source"; read_etcd_global
		if [[ -n "$printvalue" ]]; then
			decoder_checkSubscription
		fi
	fi
	if [[ -z "$channelIndex" ]]; then
		errorMessage="ERR:  Channel Index is null, retrying read then setting to static Image channel as fallback."
		notify-send -e "$errorMessage" & echo "$errorMessage"
		KEYNAME="/HOSTS/$hostNameSys/control/channelData"; read_etcd_global; channelIndex="${printvalue%%-*}"
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
		KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="ERR: Invalid Channel Index"; write_etcd_global &
	else
		echo -e "\033[32m	Switcher initialized, sending channel init!\033[0m" | systemd-cat -t "UltraGrid"
	fi
}

netCat(){
    # Simple function to submit data to netcat
    local fd
    response=""
    if exec {fd}<>"/dev/tcp/127.0.0.1/$port" 2>/dev/null;then
    	printf '%s\n' "$controlPortCmd" >&"$fd"
    	IFS= read -r -t 1 response <&"$fd"
    	exec {fd}>&-
    else
    	response="ERR: control port $port uncreachable"
    fi
	echo -e "Control port ($port) <<< $controlPortCmd\n  >>> $response" >&2
}

maintenanceTask(){
	if (( EPOCHSECONDS - badResetSince > 30 )); then
		badCounter=0
		badResetSince=$EPOCHSECONDS
	fi
	if (( goodCounter > 100 )); then
		if [[ "$lastHealthWritten" != "OK" ]]; then
			KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="OK"; write_etcd_global &
			lastHealthWritten="OK"
		fi
		reset_error_state
		goodCounter=0
	fi
}

inputError(){
	# Design note:
	# This function is the input error handler.
	# It starts a timer and generates counts for each error class that is produced.
	# The assumption is that error generation is "bursty" in nature and multiple errors
	# will appear in a short space of time.  They must all be noted, but they cannot produce
	# etcd/notification events for each error because that may occur multiple times per second and create
	# additional load for the client, resulting in performance issue, glitches and journald/etcd spam.
	local errorCase="$1"
	local timer_elapsed stage level

	# Design note:
	# Classify the error case up front, BEFORE any timer/notification machinery.
	# Some error classes are EXPECTED / benign for a short window during normal
	# operation — for example LAVC_DATA, which commonly produces a full GOP worth
	# of "Invalid data" lines before the first keyframe arrives on an excl_init
	# switch.  Within LAVC_GRACE_SECONDS such errors are suppressed (they recur
	# many times per second and must not spam journald/etcd or drive the
	# escalation timer).  If an error class spams past its grace window, it is
	# treated as genuine and falls through to the normal escalation logic below.
	case "$errorCase" in
		LAVC_DATA)
			if [[ -z "${errorSince[$1]:-}" ]]; then
				errorSince["$1"]=$EPOCHSECONDS
				(( benignCounter++ ))
				return
			fi
			if (( EPOCHSECONDS - errorSince[$1] <= LAVC_GRACE_SECONDS )); then
				(( benignCounter++ ))
				return
			fi
			unset "errorSince[$1]"
			;;
	esac

	# This is a genuine error event.  Count it toward the burst detection window
	# so that a sustained flood of real errors still trips the BURST_ERROR state.
	(( badCounter++ ))
	if [[ -z "${errorSince[$1]:-}" ]]; then
		errorSince["$1"]=$EPOCHSECONDS
		badResetSince=$EPOCHSECONDS
		error_stages["$1"]=1
		send_keepalive
		return
	fi

	timer_elapsed=$(( EPOCHSECONDS - errorSince[$1] ))
	# Map elapsed time to an escalation level (1..5).  5 = fatal, let watchdog restart us.
	if (( timer_elapsed > 30 )); then
		level=5
	elif (( timer_elapsed > 15 )); then
		level=4
	elif (( timer_elapsed > 10 )); then
		level=3
	elif (( timer_elapsed > 5 )); then
		level=2
	else
		level=1
	fi

	stage="${error_stages[$1]:-1}"
	# Step up through any newly-reached levels, running each stage's actions once.
	while (( stage < level )); do
		(( stage++ ))
		error_stages["$1"]=$stage
		case "$stage" in
			2)
				echo -e "\033[32m	Experiencing error: $1!\033[0m" | systemd-cat -t "UltraGrid"
				;;
			3)
				sed -i "s/export UG_ERROR_STATE=.*/export UG_ERROR_STATE=$errorCase/" "$HOME/config/$hostNameSys.conf"
				echo -e "\033[32m	Experiencing error: $1!\033[0m" | systemd-cat -t "UltraGrid"
				decoder_checkSubscription
				;;
			4)
				generate_errorDisplay "ERR: $1"
				echo -e "\033[32m	Experiencing +15s of error: $1!\033[0m" | systemd-cat -t "UltraGrid"
				;;
			5)
				echo -e "\033[32m	Error: $1 exceeds 30 seconds!  Terminating process!\033[0m" | systemd-cat -t "UltraGrid"
				# Serious > 30second error, we let the watchdog kill the process
				sed -i "s/^UG_RESTARTING=.*/UG_RESTARTING=1/" "$HOME/config/$hostNameSys.conf"
				exit 1
				;;
		esac
	done

	# Keep the watchdog alive while we're still attempting to run.
	send_keepalive
	if (( badCounter > 50 && burstNotified == 0 )); then
		burstNotified=1
		sed -i "s/export UG_ERROR_STATE=.*/export UG_ERROR_STATE=BURST_ERROR/" "$HOME/config/$hostNameSys.conf"
		generate_errorDisplay "ERR: ERROR BURST DETECTED"
	fi
}

check_sourceHashStatus(){
	if [[ -z "$GROUP_HASH" ]]; then
		# The GROUP_HASH value is not populated in our conf!
		KEYNAME="/UI/HOSTS/$CLIENT_HOSTHASH/control/GROUP"; read_etcd_global
		if [[ -z "$printvalue" ]]; then
			echo "	ERR:	NO GROUPHASH AVAILABLE!"
			inputError "NO_GROUP_HASH"
			return 1
		fi
		# Guarantee a trailing newline so the appended line doesn't glue onto the
		# end of the last existing line in the conf file.
		[[ -s "/var/home/wavelet/config/$hostNameSys.conf" && -n "$(tail -c1 "/var/home/wavelet/config/$hostNameSys.conf")" ]] && echo >> "/var/home/wavelet/config/$hostNameSys.conf"
		GROUP_HASH="$printvalue"
		echo "export GROUP_HASH=\"$GROUP_HASH\"" >> "/var/home/wavelet/config/$hostNameSys.conf"
	fi
    KEYNAME="/UI/GROUPS/$GROUP_HASH/control/sourceHashStatus"; read_etcd_global
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
				sed -i "s/^UG_RESTARTING=.*/UG_RESTARTING=1/" "$HOME/config/$hostNameSys.conf"
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
	KEYNAME="/HOSTS/$hostNameSys/control/channelData"; read_etcd_global; channelData="$printvalue"
	channelIndex="${channelData%%-*}"
	channelSourceHash="${channelData##*-}"
	KEYNAME="/HOSTS/$hostNameSys/unsubRequest"; KEYVALUE="$channelSourceHash"; write_etcd_global &
}

switcherError(){
	# This is called if we get a known switcher error message
	(( badSwitchCounter++ ))
	badResetSince=$EPOCHSECONDS
	echo "		Switcher error! remediating.."
	# we need to "do something here"
}

process_fecData(){
	# Video dec stats (cumulative): 893 total / 867 disp / 26 drop / 1 corr / 0 miss FEC noerr/OK/NOK: 892/0/1
	echo "	Processing Error Data: $line"
	# Here, we'd calculate the error ratio for FEC/dropped frames, and if above a certain threshhold, do something abt it.
}

# Rotation policy for the wrapper's own log and the raw UltraGrid (ugDirect) log.
# Both files live under /var/home/wavelet/logs/ and grow without bound on long
# or heavily-erroring runs, so we rotate them in-place, size-based, with no
# external logrotate/timer dependency.
LOG_ROTATE_BYTES=10485760          # 10 MB
LOG_ROTATE_KEEP=5                  # retain .1 .. .5
# LAVC "Invalid data" errors are expected while a new stream/keyframe settles in
# after an excl_init switch.  Only past this window is a sustained LAVC_DATA
# flood treated as a genuine encoder-side corruption problem.
LAVC_GRACE_SECONDS=2

rotate_log_file(){
	# copytruncate-style rotation for the wrapper's own UltraGrid.log.  Because the
	# wrapper's fd is redirected (exec >> UltraGrid.log), we cannot simply move the
	# file away or the running fd keeps writing to the (now-rotated) inode.  We copy
	# the current contents out to .1 and truncate the original in place.
	local f="$1"
	if [[ -f "$f" ]] && (( "$(stat -c%s "$f")" > LOG_ROTATE_BYTES )); then
		# Shift retained copies: N -> N+1, dropping the oldest (LOG_ROTATE_KEEP).
		local i=$((LOG_ROTATE_KEEP - 1))
		while (( i > 0 )); do
			if [[ -f "${f}.$i" ]]; then
				mv -f "${f}.$i" "${f}.$((i+1))"
			fi
			((i--))
		done
		cp -f "$f" "${f}.1"
		: > "$f"
		echo "	Rotated $f (copytruncate) at $(stat -c%s "${f}.1") bytes." | systemd-cat -t "UltraGrid"
	fi
}

rotate_ug_log(){
	# Raw UltraGrid output.  The child binary writes through the ugDirect.log symlink
	# into our current mktemp file (UG_LOG_FILE), and tail -F follows the same path.
	# Both reference the same inode, so we copytruncate in place: copy the current
	# contents out to a persistent ugDirect.log.N, then truncate UG_LOG_FILE.  The
	# child's already-open fd and the tail follower both keep working across the
	# truncation with zero interruption to the live pipeline.
	if [[ -f "$UG_LOG_FILE" ]] && (( "$(stat -c%s "$UG_LOG_FILE")" > LOG_ROTATE_BYTES )); then
		# Shift retained copies of the raw log.
		local i=$((LOG_ROTATE_KEEP - 1))
		while (( i > 0 )); do
			if [[ -f "/var/home/wavelet/logs/ugDirect.log.$i" ]]; then
				mv -f "/var/home/wavelet/logs/ugDirect.log.$i" "/var/home/wavelet/logs/ugDirect.log.$((i+1))"
			fi
			((i--))
		done
		cp -f "$UG_LOG_FILE" "/var/home/wavelet/logs/ugDirect.log.1"
		: > "$UG_LOG_FILE"
		echo "	Rotated ugDirect.log (copytruncate) at $(stat -c%s "/var/home/wavelet/logs/ugDirect.log.1") bytes." | systemd-cat -t "UltraGrid"
	fi
}

reset_error_state(){
    sed -i "s/export UG_ERROR_STATE=.*/export UG_ERROR_STATE=0/" "$HOME/config/$hostNameSys.conf"
    badCounter=0
    goodCounter=0
    badSwitchCounter=0
    benignCounter=0
    burstNotified=0
    errorSince=()
    error_stages=()
    systemd-notify "STATUS=Stable"
}


#####
#
# Main
#
#####


#set -m
exec >> "/var/home/wavelet/logs/UltraGrid.log" 2>&1
UG_ARGUMENTS=("$@")
UG_PID=0
SWAYIMG_PID=0
swaySocket=""
goodCounter=0
badCounter=0
sampleCounter=0
badSwitchCounter=0
benignCounter=0
burstNotified=0
lastHealthWritten=""
lastkeepalive=0
lastGoodLine=$EPOCHSECONDS
badResetSince=$EPOCHSECONDS
lineCount=0
WATCHDOG_INTERVAL=2
ROTATE_CHECK_LINES=500
declare -gA errorSince
declare -gA error_stages

# Ensure the error-state marker exists in the config so sed replaces are reliable.
if ! grep -q "^export UG_ERROR_STATE=" "$HOME/config/$hostNameSys.conf"; then
	[[ -s "$HOME/config/$hostNameSys.conf" && -n "$(tail -c1 "$HOME/config/$hostNameSys.conf")" ]] && echo >> "$HOME/config/$hostNameSys.conf"
	echo "export UG_ERROR_STATE=0" >> "$HOME/config/$hostNameSys.conf"
fi

trap 'handle_signal SIGINT'  INT
trap 'handle_signal SIGTERM' TERM
trap 'handle_signal SIGUSR1' USR1
trap 'cleanup EXIT' EXIT


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
while :; do
	if ! IFS= read -r -t 1 line <&3; then
		# Idle ticks are effectively NOOPS because we *need* an output from UltraGrid
		# If there is no UltraGrid log output then the assumption is a crash, hang and need to restart.
		rc=$?
		(( rc > 128 )) || break            # rc<=128 means EOF on the tail pipe
		# --- idle tick: no log line for 1s ---
		if ! kill -0 "$UG_PID" 2>/dev/null; then
			echo "UltraGrid child exited unexpectedly" | systemd-cat -t "UltraGrid"
			exit 1
		fi
		maintenanceTask
		continue
	fi
	if (( ++lineCount % ROTATE_CHECK_LINES == 0 )); then
		rotate_ug_log
		rotate_log_file "/var/home/wavelet/logs/UltraGrid.log"
	fi
	maintenanceTask
	echo "	UltraGrid log output at $EPOCHSECONDS"
	case "$line" in
		*\[switcher\]*frames*seconds*FPS*)                 note_good ;;
		*\[File*cap\.\]*Rewinding*the*file\.*)              note_good ;;
		*\[video\ dec\.\]*New*incoming*video*format*)      note_good ;;
		*\[Pbuf\]*\[video\]*packets*received*0*lost,*max*loss*0) note_good ;;
		*\[display\]*Successfully*reconfigured*display*to*) note_good ;;
		*Setting*GL*size*\.)                                note_good ;;
		*\[switcher\]*Switched*from*device*to*device*)      note_good ;;
		*NDI*cap*frames*in*seconds)                         note_good ;;
		*Vulkan*SDL3*frames*in*seconds*)                    note_good ;;
		*WARNING:*Selected*capture*card*was*not*found*)
			echo -e "\033[33m	UltraGrid is unable to start with bad command line!\033[0m" | systemd-cat -t "UltraGrid"
			generate_errorDisplay "FTL: BAD ULTRAGRID COMMAND LINE"
			exit 1
			;;
		*\[ug_input\]*Dropping*frame!)                      inputError "UG_FRAMEDROP" ;;
		*\[lavd\]*Invalid*data*found*when*processing*input*) inputError "LAVC_DATA" ;;
		*Video*dec*stats*cumulative*)                       process_fecData "$line" ;;
		*Error*while*decoding*frame*Invalid*data*found*when*processing*input.)
			generate_errorDisplay "ERR: MAJOR CODEC ERROR"
			echo -e "\033[33m	UltraGrid reports corrupted codec data for input stream!\033[0m" | systemd-cat -t "UltraGrid"
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