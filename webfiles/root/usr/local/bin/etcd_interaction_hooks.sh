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
read_etcd_json_revision(){
	# Gets the revision value of the current key
	printvalue=$("$targetFile" "read_etcd_json_revision" "$KEYNAME")
}
read_etcd_lastrevision(){
	# reads the previous revision value of the key at a specific revision ID
	printvalue=$("$targetFile" "read_etcd_revisionID" "$KEYNAME" "$REVISIONID")
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
	# serviceName populated in parent shall and parsed down
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
	# $hostNameSys populated in caller module, should be available in this subshell
	if [[ -z "$1" ]]; then
		exit 0
	fi
	# Notify the appliance immediately via etcd.  This MUST NOT block the caller
	# (the UltraGrid wrapper's main loop), or video output gets disrupted.
	KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="$1"; write_etcd_global &
	# Desktop notification visible until the error state clears (UG_ERROR_STATE=0)
	# or give up after 30s so the subshell
	# Runs in a subshell so the caller is never blocked.
	(
		ERRORCONF="${ERRORCONF:-$HOME/config/$hostNameSys.conf}"
		notify-send -u critical -a "Wavelet Error" -r 9000 \
			-h string:x-mako-align:center \
			"WAVELET ERROR" "$1"
		for _ in $(seq 1 60); do
			sleep .5
			grep -q "^UG_ERROR_STATE=0" "$ERRORCONF" 2>/dev/null && break
		done
		# Dismiss the notification (same replace-id, instant expire).
		notify-send -a "Wavelet Error" -r 9000 -t 1 "WAVELET ERROR" "$1"
	) &
}

generate_timer_id(){
	echo "timer_$(tr -d '-' </proc/sys/kernel/random/uuid)"
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
	local timer_id; local end_time; local start_time; timer_duration=""
    timer_id="${1:-}"
    if [[ -z "$timer_id" ]]; then
        return 0
    fi
    end_time=$(date +%s.%N)
    start_time=${timer_start_times[$timer_id]:-$end_time}
    timer_duration=$(echo "$end_time - $start_time" | bc)
    unset 'timer_start_times[$timer_id]'
    unset 'timer_running_flags[$timer_id]'
}

get_timer_elapsed() {
	timer_id=""; local start_time; local now
    timer_id="${1:-}"
    if [[ -z "$timer_id" ]] || [[ -z "${timer_start_times[$timer_id]:-}" ]]; then
        echo "0"
        return 0
    fi
    start_time=${timer_start_times[$timer_id]}
    now=$(date +%s.%N)
    # Truncate to integer seconds so the value is safe to use in bash (( )) arithmetic.
    echo "($now - $start_time) / 1" | bc
}

time_operation() {
	local label; local start; local end; local duration
    label="$1"
    shift
    start=$(date +%s.%N)
    "$@"
    end=$(date +%s.%N)
    duration=$(echo "$end - $start" | bc)
    echo "		[$label] took $duration" >&2
}