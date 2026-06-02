#!/bin/bash


#	Etcd interaction hooks for use in many of the wavelet modules
#	This module is not executed directly, but included in most other modules requiring etcd interaction.
#	Contains some other commonly used functions

targetFile=""
if [[ -f "/var/wavelet_ramfs/wavelet_etcd_interaction.sh" ]]; then
  targetFile="/var/wavelet_ramfs/wavelet_etcd_interaction.sh"
else
  targetFile="/usr/local/bin/wavelet_etcd_interaction.sh"
fi

read_etcd(){
	printvalue="$("$targetFile" "read_etcd" "$KEYNAME")"
	#echo -e "		Key Name: {$KEYNAME} read from etcd\n		Value: $printvalue\n		Host: ${hostNameSys}\n"
}
read_etcd_global(){
	printvalue=$("$targetFile" "read_etcd_global" "$KEYNAME")
	#echo -e "		Key Name: {$KEYNAME} read from etcd\n		Global Value: $printvalue\n"
}
read_etcd_prefix(){
	printvalue=$("$targetFile" "read_etcd_prefix" "$KEYNAME")
	#echo -e "		Key Name: {$KEYNAME} read from etcd\n		Value $printvalue\n		Host: ${hostNameSys}\n"
}
read_etcd_prefix_global(){
	printvalue=$("$targetFile" "read_etcd_prefix_global" "$KEYNAME")
}
read_etcd_prefix_list(){
    # Gets both KEYS and VALUES in a specified range one after the other
	printvalue=$("$targetFile" "read_etcd_prefix_list" "$KEYNAME")
}
read_etcd_prefix_keys(){
	# Gets the KEYS ONLY in a specified range
	printvalue=$("$targetFile" "read_etcd_prefix_keys" "$KEYNAME")
}
read_etcd_prefix_values(){
	# Gets the VALUES ONLY in a specified range
	printvalue=$("$targetFile" "read_etcd_prefix_values" "$KEYNAME")
}
write_etcd(){
	"$targetFile" "write_etcd" "$KEYNAME" "$KEYVALUE"
	#echo -e "		Key Name: ${KEYNAME}\n		Set as: ${KEYVALUE}\n		Host: /${hostNameSys}/\n"
}
write_etcd_global(){
	"$targetFile" "write_etcd_global" "$KEYNAME" "$KEYVALUE"
	#echo -e "		Key Name: ${KEYNAME}\n 		Set as Global Value: ${KEYVALUE}\n"
}
write_etcd_txn(){
	# As this is an ATOMIC operation, multiple etcd calls may be applied, so it submits only the KEYDATA var.
	# REF: https://github.com/etcd-io/etcd/blob/main/etcdctl/README.md#key-value-commands
	#<Txn> ::= <CMP>* "\n" <THEN> "\n" <ELSE> "\n"
	#<CMP> ::= (<CMPCREATE>|<CMPMOD>|<CMPVAL>|<CMPVER>|<CMPLEASE>) "\n"
	#<CMPOP> ::= "<" | "=" | ">"
	#<CMPCREATE> := ("c"|"create")"("<KEY>")" <CMPOP> <REVISION>
	#<CMPMOD> ::= ("m"|"mod")"("<KEY>")" <CMPOP> <REVISION>
	#<CMPVAL> ::= ("val"|"value")"("<KEY>")" <CMPOP> <VALUE>
	#<CMPVER> ::= ("ver"|"version")"("<KEY>")" <CMPOP> <VERSION>
	#<CMPLEASE> ::= "lease("<KEY>")" <CMPOP> <LEASE>
	#<THEN> ::= <OP>*
	#<ELSE> ::= <OP>*
	#<OP> ::= ((see put, get, del etcdctl command syntax)) "\n"
	#<KEY> ::= (%q formatted string)
	#<VALUE> ::= (%q formatted string)
	#<REVISION> ::= "\""[0-9]+"\""
	#<VERSION> ::= "\""[0-9]+"\""
	#<LEASE> ::= "\""[0-9]+\""

	# Typical construction for "if key has never had a modification event, put these three keys"
#	KEYDATA="mod(\"/KEY\") = \"0\"
#
#put \"key1\" -- \"value1\"
#put \"key2\" -- \"value2\"
#put \"key3\" -- \"value3\"
#
#"
	"$targetFile" "write_etcd_txn" "$KEYDATA"
}
delete_etcd_key(){
	"$targetFile" "delete_etcd_key" "$KEYNAME"
}
delete_etcd_key_global(){
	"$targetFile" "delete_etcd_key_global" "$KEYNAME"
}
delete_etcd_key_prefix_global(){
	# Dangerous!  If used improperly it would wipe every key this host has access to modify via its role.
	"$targetFile" "delete_etcd_prefix_global" "$KEYNAME"
}
generate_service(){
	# Can be called with more args with "generate_service" "$keyToWatch" 0 0 "$serviceName"
	"$targetFile" "generate_service" "$serviceName"
}

valid_ipv4() {
	local ip
	if [[ -z "$1" ]]; then
		return 1
	else
		ip=$(echo "$1" | tr -d '[:space:]' | sed 's/[[:cntrl:]]//g')
	fi
	local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
	if [[ "$ip" =~ $regex ]]; then
		# Additional check: ensure each octet is 0-255
		IFS='.' read -ra octets <<< "$ip"
   		for octet in "${octets[@]}"; do
   			if ((octet < 0 || octet > 255)); then
   				echo "	Octet value $octet is not in valid range 0-255!"
   				return 1
   			fi
   		done
		return 0
	else
		echo "	Input string does not match a valid IP address pattern!"
    	echo "	Actual value received: '$ip'"
		return 1
	fi
}

generate_errorDisplay(){
	# We may wish to change this to mako-based transient error messages.
	if [[ -z "$1" ]]; then
		exit 0
	fi
	local staticImageFile="/var/home/wavelet/config/errorDisplay.png"
	color="rgba(20, 20, 20, 128)"  # 50% transparent (alpha=128/255)
	# Get our current desktop resolution
	swaySocket="$(ls "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/sway-ipc.*.sock 2>/dev/null | xargs -I{} sh -c 'swaymsg -s {} -t get_tree >/dev/null 2>&1 && echo {}')"
	output_info="$(swaymsg -t -s "$swaySocket" get_outputs -r | jq -r '.[0].rect | {width, height}')"
	local screen_width; local screen_height
	screen_width=$(echo "$output_info" | jq -r '.width')
    screen_height=$(echo "$output_info" | jq -r '.height')
	local imgWidth=$(( screen_width * 80 / 100 ))
	local imgHeight=$(( screen_height * 50 / 100 ))
	local xPos=$(( screen_width / 2 - imgWidth / 2 ))
	local yPos=$(( screen_height / 3 ))
	# Uses swayImg to throw up an error whilst the UG window is busy or inoperable
	if [[ ! -f "$staticImageFile" ]]; then
		magick \
			-size 800x50 \
			-background black \
			-fill white \
			-pointsize 32 \
			-gravity NorthWest \
			xc:"rgb(30,30,30)" \
			\( -size 800x200 label:"W Δ V E L E T | ERR: $1" \) \
			-composite \
			-colorspace RGB "$staticImageFile"
	fi
	swayimg "$staticImageFile" & sleep .5
    swaymsg -s "$swaySocket" "[app_id=\"swayimg\"] floating enable, fullscreen disable, move container to position -200 -300"
    SWAYIMG_PID=$!
	local swayimg_pid=$!
	KEYNAME="/HOSTS/$(hostname)/controls/healthStatus"; KEYVALUE="$1"; write_etcd_global
	while [[ -f /var/home/wavelet/config/errorState.flag ]]; do
		if [[ -f "$staticImageFile" ]]; then
			kill -HUP "$swayimg_pid" 2>/dev/null || true
		fi
		sleep .1
	done
	kill "$swayimg_pid" 2>/dev/null || true
}

generate_timer_id(){
	echo "timer_"$(cat /proc/sys/kernel/random/uuid | tr -d '-')""
}

start_timer() {
    declare -gA timer_start_times
    declare -gA timer_running_flags
    local timer_id="${1:-$(generate_timer_id)}"
    timer_start_times[$timer_id]=$(date +%s.%N)
    timer_running_flags[$timer_id]=true
    # Return the ID via a global var rather than stdout, to avoid subshell scope loss
    timer_id_out="$timer_id"
}

stop_timer() {
    local timer_id="${1:-}"
    if [[ -z "$timer_id" ]]; then
        return 0
    fi
    local end_time=$(date +%s.%N)
    local start_time=${timer_start_times[$timer_id]:-$end_time}
    timer_duration=$(echo "$end_time - $start_time" | bc)
    unset 'timer_start_times[$timer_id]'
    unset 'timer_running_flags[$timer_id]'
}

get_timer_elapsed() {
    local timer_id="${1:-}"
    if [[ -z "$timer_id" ]] || [[ -z "${timer_start_times[$timer_id]:-}" ]]; then
        echo "0"
        return 0
    fi
    local start_time=${timer_start_times[$timer_id]}
    local now=$(date +%s.%N)
    echo "$now - $start_time" | bc
}

time_operation() {
    local label="$1"
    shift
    local start=$(date +%s.%N)
    "$@"
    local end=$(date +%s.%N)
    local duration=$(echo "$end - $start" | bc)
    echo "		[$label] took $duration" >&2
}