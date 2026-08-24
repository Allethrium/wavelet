#!/bin/bash
# Is launched from a systemd prefix watcher looking at /HOSTS/
# Must filter out keys from /HOSTS/$hostname and parse in order to do anything useful

# The general flow of information through Wavelet's layers is in a single direction.
# Provisioning HOSTS assume defaults and "tell" the orchestrator where they want to go
# After this is completed, the UI then "tells" the HOSTS which "tell" the orchestrator where to put everything.

# In this approach, HOSTS can write only their own keys under /HOSTS/ - this results in a better security model
# The UI component can only notify hosts with readOnly access to the UI, and the server coordinates everything.
# This serverside component is responsible for taking the client machine's requests, filtering them
# and then applying them to key prefixes they don't have access to write back to (IE UI)


# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
ETCDINTERACTIONHOOKS=""
if [[ -f "/var/wavelet_ramfs/etcd_interaction_hooks.sh" ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source "/usr/local/bin/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/usr/local/bin/etcd_interaction_hooks.sh"
fi

detect_self(){
	# test if i'm the server
	if [[ "$(hostname)" = *"svr"* ]]; then
		event_server
	else
		echo "The orchestrator will only run on the server!"
		exit 1
	fi
}

event_server(){
	# Filter our trigger env and generate local environment data
	local control_suffix
	triggerKey="${ETCD_WATCH_KEY//\"}"
	triggerValue="${ETCD_WATCH_VALUE//\"}"
	# Sanitize triggerValue
	triggerValue="${triggerValue//\"/}"
	triggerValue="${triggerValue//\'/}"
	triggerValue="${triggerValue//$'\n'/}"
	triggerValue="${triggerValue//$'\r'/}"
	triggerValue="${triggerValue//$'\t'/}"
	keyHostName="${triggerKey#*/HOSTS/}"; keyHostName="${keyHostName%%/*}"
	hostHash=""; hostGroup=""; primaryGroup=""
	configFileExists=false
	# This will strip only everything past /control, is this what we want?
	# Are we sure the orchestrator responds only to /HOSTS/$HOST/control/xxaabb?
	control_suffix="${triggerKey#/HOSTS/"$keyHostName"/control/}"
	control_suffix="${control_suffix##*/}"
	case "$control_suffix" in
		"healthStatus")	handler_function="health_status_update";;
		"inputUpdate")	handler_function="input_device_update";;
		"wavelet_build_completed")	handler_function="new_host";;
		"reflectorRequest")	handler_function="event_subscription_request";;
		"unsubRequest")	handler_function="event_unsubscription_request";;
		"NETWORK_SENSE")	handler_function="event_network_sense";;
		"IP")	handler_function="event_update_ip";;
		"encoder_primed")	handler_function="event_encoder_primed";;
		"encoder_ready")	handler_function="event_encoder_ready";;
		"GROUP")	handler_function="event_change_group";;
		"screenCastCapable")	handler_function="event_screenCastCapable";;
		"generateConf")	handler_function="event_generate_client_conf";;
		*) exit 0;; #noop
	esac
	if [[ -n "$handler_function" ]] && declare -f "$handler_function" > /dev/null; then
		echo "Triggered with: $triggerKey, $triggerValue"
		declare -A host_config
		configFile="/var/home/wavelet/config/$keyHostName.conf"
		echo "	Searching for:  $configFile"
		if [[ -f "$configFile" ]]; then
			configData="$(<"$configFile")"
#			echo "	Config data found:"
#			echo "$configData"
			while IFS= read -r line; do
				line="${line//$'\r'/}"
				[[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
				[[ "$line" != *=* ]] && continue
				key="${line%%=*}"
				key="${key#export }"
				value="${line#*=}"
				value="${value#\"}"
				value="${value%\"}"
				host_config["$key"]="$value"
			done <"$configFile"
			# Populate host configuration variables from the parsed host_config array
			hostHash="${host_config[CLIENT_HOSTHASH]:-}"
			groupHash="${host_config[GROUP_HASH]:-}"
			hostType="${host_config[HOST_TYPE]:-}"
			serverHostname="${host_config[SERVER_HOSTNAME]:-}"
			clusterId="${host_config[CLUSTER_ID]:-}"
			primaryGroupHash="${host_config[PRIMARY_GROUPHASH]:-}"
			serverHostHash="${host_config[SERVER_HOSTHASH]:-}"
			hostIp="${host_config[HOST_IP]:-}"
			inputDevicePresent="${host_config[INPUT_DEVICE_PRESENT]:-}"
			modRevision="${host_config[MOD_REVISION]:-}"
		else
			if [[ "$handler_function" == "event_generate_client_conf" ]] && [[ "$keyHostName" != "$hostNameSys" ]]; then
            	# This is a new host and we are going to generate the config directly
            	event_generate_client_conf
            	exit 0
            else
            	# The host keys are in the process of being provisioned or this is an orphan key
				echo "Config file $configFile for host does not exist yet, or this is the server.  noop."
				exit 0
			fi
		fi
		if [[ -z "$hostHash" ]]; then
			echo "	No hostHash available!  Skipping event for $triggerKey"
			exit 0
		fi
        $handler_function
    fi
}

event_screenCastCapable(){
	# Notifies the UI that this device is screen cast capable and will (eventually) display a widget in adv. settings.
	KEYNAME="/UI/HOSTS/$hostHash/control/screenCastCapable"; KEYVALUE="$triggerValue"; write_etcd_global &
}

input_device_update(){
	# obtain a list of inputs available on the host
	declare -A host_inputs_map
	KEYNAME="${triggerKey%%/control/inputUpdate*}"; read_etcd_prefix_list
    while IFS= read -r line; do
		if [[ "$line" == *"/inputs/"* ]]; then
		    if [[ "$line" == *"/devpath_lookup/"* ]] ||
               [[ "$line" == *"/cmd/"* ]] ||
               [[ "$line" == *"/hash_lookup/"* ]]; then
                continue  # Skip this key and move to next iteration
            else
                local inputHash="${line##*/inputs/}"
                IFS= read -r next_line
                if [[ -n "$next_line" ]]; then
                    host_inputs_map[$inputHash]="$next_line"
                fi
            fi
        fi
    done <<<"$printvalue"
	for key in "${!host_inputs_map[@]}"; do
		(
			KEYNAME="/UI/HOSTS/$hostHash/inputs/$key"; KEYVALUE="${host_inputs_map[$key]}"; write_etcd_global
			echo "Wrote Input: $KEYNAME == $KEYVALUE"
		) &
	done
	wait
	# Next we compare entries and delete entries that did not exist in the /HOSTS/ prefix.
    # This should happen on EVERY UI inputUpdate event.
    compare_entries
}

compare_entries(){
	# We pull a prefix list of keys on this host, and the same on the UI.
	# The UI will always be wrong vs. the host
	# We remove any keys not found on the host because they would not work regardless.
	echo "	Comparing UI and host input keys for host: $keyHostName, keys in the UI not on the host will be deleted.."
	inputHashes=()
	KEYNAME="/UI/HOSTS/$hostHash/inputs/"; read_etcd_prefix_keys
	while read -r line; do
	    inputKey="${line##*/inputs/}"
	    if [[ -n "$inputKey" ]]; then
		    inputHashes+=("$inputKey")
		fi
	done <<<"$printvalue"
	if [[ -z "${inputHashes[*]}" ]]; then
		echo "	No inputs found in UI, nothing to prune."
	else
	    # we delete orphan inputs
        deleteFile="$(mktemp)"
        for key in "${inputHashes[@]}"; do
            (
                KEYNAME="/HOSTS/$keyHostName/inputs/$key"; read_etcd_global
                if [[ -z "$printvalue" ]]; then
                    echo "$key" >> "$deleteFile"
                fi
            ) &
        done
        wait
        if [[ -s "$deleteFile" ]]; then
            while read -r key; do
                if [[ -z "$key" ]]; then
                    continue
                else
                    if [[ -z "$hostHash" ]] || [[ -z "$key" ]]; then
                        # Since we are using etcd delete prefix, it is imperative that both vars are populated
                        continue
                    else
                        (
                            KEYNAME="/UI/HOSTS/$hostHash/inputs/$key"; delete_etcd_key_prefix_global
                            echo "Deleted $KEYNAME from UI.."
                        ) &
                    fi
                fi
            done < "$deleteFile"
            wait
        fi
        rm -rf "$deleteFile"
        # And we reset the update key to 0
	fi
   	# NOTE: this key is an absolute /HOSTS/ path, so we must use the global delete.
   	# delete_etcd_key would re-prepend /HOSTS/$hostNameSys/ and produce a malformed double-path key.
   	KEYNAME="/HOSTS/$keyHostName/control/inputUpdate"; delete_etcd_key_global &
}

event_subscription_request(){
	# This should take a subscription request from a host writing its key in /HOSTS/$hostName/reflectorRequest
	# The key is written when the decoder launches wavelet_run in order to start a display task.
	local hostName; local inputHash; local KEYNAME;
	local KEYVALUE; local targetHostName; local ipAddr
#	echo "      Working on subscription request for hostname: $keyHostName"
	inputHash=$(xargs -I {} printf "%s" {} <<< "$triggerValue")
	# Find the Encoder host with an input key matching this input hash
	KEYNAME="/HOSTS/"; read_etcd_prefix_list
	allHostKeys="$printvalue"
	while IFS= read -r line; do
		if [[ "$line" == *"/inputs/$inputHash"* ]]; then
			# We matched our input, get the hostName, and write supplicant IP into the target subscription list
			# This is read in by the reflector service, and acted upon there.
			KEYNAME=\"/HOSTS/${line#*/HOSTS/}\"; read_etcd_global
			targetHostName="${line#*/HOSTS/}"
			targetHostName="${targetHostName%%/*}"
#			echo "      Located supporting host $targetHostName for the input hash: $inputHash"
	    fi
	done <<<"$allHostKeys"
	# We try and get a good IP address for the host
	if [[ -z "$hostIp" ]]; then
        hostIp="$(dig +short "$keyHostName")"
    fi
    if valid_ipv4 "$hostIp"; then
        echo "      Resolved valid IP, updating the host.."
        KEYNAME="/HOSTS/$keyHostName/control/IP"; write_etcd_global &
    else
        echo "      Cannot resolve valid host IP address, exiting."
        exit 0
    fi

    # Finally, check for direct or indirect mode on the source
    if [[ "$targetHostName" == *"NDI"* ]]; then # or RTSP, whatever else
    	# This is a net device and we want to check it for direct mode
    	KEYNAME="/HOSTS/$targetHostName"; read_etcd_global
    	KEYNAME="/UI/HOSTS/$printvalue/control/directMode"; read_etcd_global
    	if [[ "$printvalue" != 1 ]]; then
			targetHostName="$hostNameSys" # targetHostName should be the server
	    fi
	fi

	KEYNAME="/HOSTS/$targetHostName/DECODER_SUB_LIST/$keyHostName"; KEYVALUE="$hostIp"; write_etcd_global &
	KEYNAME="/HOSTS/$keyHostName/control/currentUGReflectorHost"; KEYVALUE="$targetHostName"; write_etcd_global &
	echo "      Requesting port from reflector at $targetHostName for host $keyHostName with IP Address: $hostIp"
	# Since we don't need to worry about indexing anymore, we can just forward this on to the reflector
	# At this point, the reflector should swing into action, and be able to read the populated IP addresses directly.
	# This is preferable to hostnames because the IP addresses as print-values-only come out as a simple list in ETCD
	return 0
}

event_unsubscription_request(){
    # Removes a decoder/UltraGrid client from an UltraGrid reflector on the targeted host
	supplicantHostName="${triggerKey#*/HOSTS/}"
	supplicantHostName="${supplicantHostName%%/*}"
	# Architectural note - read_etcd_prefix_list gives us all the host keys in one read
	# It's far more efficient to make this one grab, then iterate through the list.
	KEYNAME="/HOSTS/"; read_etcd_prefix_list; allHostKeys="$printvalue"
	local counter=0; local sourceHostKey; local videoSourceHost

	while read -r line; do
		# get the CURRENT video source for this host
		if [[ "$line" == "/HOSTS/$supplicantHostName/control/videoSource" ]]; then
			read -r currentHostVideoSource
			echo "		Supplicant $supplicantHostName has current video source: $currentHostVideoSource"
		fi
	done <<<"$allHostKeys"

	# Find which host owns this video source (which host has /inputs/$currentHostVideoSource)
	while read -r line; do
		if [[ "$line" == *"/inputs/$currentHostVideoSource" ]]; then
			sourceHostKey="$line"
			videoSourceHost="${sourceHostKey#*/HOSTS/}"
			currentVideoSourceHost="${videoSourceHost%%/inputs/*}"
			echo "		Video source $currentHostVideoSource is owned by host: $currentVideoSourceHost"
			break
		fi
	done <<<"$allHostKeys"

    while read -r line; do
        (
        	if [[ "$line" == "/HOSTS/$currentVideoSourceHost/DECODER_SUB_LIST/$supplicantHostName"* ]]; then
            	echo "		The current video source is on this reflector.  NOOP."
            	KEYNAME="$triggerKey"; delete_etcd_key_global &
            	exit 0
        	elif [[ "$line" == *"/DECODER_SUB_LIST/$supplicantHostName" ]] && \
        		[[ "$line" != "/HOSTS/$currentVideoSourceHost/"* ]]; then
            	echo "		Processing unsubscription request for: $line"
            	KEYNAME="$line"; delete_etcd_key_global &
            	KEYNAME="$triggerKey"; delete_etcd_key_global &
				KEYNAME="/HOSTS/$supplicantHostName/control/currentUGReflectorHost"; delete_etcd_key_global
            	(( counter ++ ))
            	# The reflector will be called by the change in DECODER_SUB_LIST, and remove the deleted key.
        	fi
        ) &
    done <<<"$allHostKeys"
    wait
}

health_status_update(){
    # Notifies the decoder that it's errored and that the subscription attempt to the reflector failed.  Also updates UI status
    local KEYDATA
    if [[ -z "$keyHostName" ]] || [[ "$keyHostName" == "0" ]]; then
        echo "health_status_update: Invalid keyHostName '$keyHostName', exiting."
        exit 0
    fi
    if [[ -z "$hostHash" ]] || [[ "$hostHash" == "0" ]]; then
		echo "health_status_update: Invalid hostHash for '$keyHostName', exiting."
		exit 0
    fi
    # We perform a test to see if the healthStatus has actually changed, and only update if it has.
    # The client itself also guards against this.
    KEYNAME="/UI/HOSTS/$hostHash/control/healthStatus"; read_etcd_global
    if [[ "$triggerValue" != "$printvalue" ]]; then
    	# Perform an atomic write with an etcdctl check that the key exists and it not null included
    	KEYDATA="val(\"/HOSTS/$keyHostName\") = \"$hostHash\"

put /UI/HOSTS/$hostHash/control/healthStatus \"$triggerValue\"
put /UI/HOSTS/$hostHash/control/lastError \"$(date +%s)\"
put /UI/HOSTS/$hostHash/control/errorCode \"$triggerValue\"

"
    	write_etcd_txn "$KEYDATA"
    	# Note, this transaction is designed to fail if the host key is NOT present in the UI (stops writing a key for a nonprovisioned device!)
    fi
}

event_network_sense(){
	# Calls the network_device script with our keyvalue as an argument, it will then proceed to process a new DHCP lease rq.
	if [[ -f "/var/wavelet_ramfs/wavelet_network_device.sh" ]]; then
		/var/wavelet_ramfs/wavelet_network_device.sh "$triggerValue"
	else
		/usr/local/bin/wavelet_network_device.sh "$triggerValue"
	fi
}

event_update_ip(){
	if [[ -z "$triggerValue" ]]; then
		exit 0
	fi
	ip_count=0
	temp_value="$triggerValue"
	while [[ "$temp_value" =~ ([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}) ]]; do
		((ip_count++))
		temp_value="${temp_value#*"${BASH_REMATCH[1]}"}"
	done
	if [[ $ip_count -gt 1 ]]; then
		echo "	ERROR! Host has $ip_count IP addresses in field: '$triggerValue'"
		exit 1
	fi
	# validate IP address and only parse forward if OK
	if valid_ipv4 "$triggerValue"; then
		KEYNAME="/UI/HOSTS/$hostHash/control/IP"; KEYVALUE="$triggerValue"; write_etcd_global &
		echo "	Updating host $keyHostName UI key: $KEYNAME to IP: $triggerValue"
		# Update the host config file with the new IP
		update_host_config_key "HOST_IP" "$triggerValue"
	else
		exit 0
	fi
}

event_encoder_primed(){
	# Set sourceHashstatus to primed
	if [[ -z "$groupHash" ]]; then
		echo "	ERR: no group hash populated for this host's conf"
		exit 0
	fi
	KEYNAME="/UI/GROUPS/$groupHash/control/sourceHashStatus"; KEYVALUE="2"; write_etcd_global &
}
event_encoder_ready(){
	# Set sourceHashStatus to ready
	if [[ -z "$groupHash" ]]; then
		echo "	ERR: no group hash populated for this host's conf"
		exit 0
	fi
	KEYNAME="/UI/GROUPS/$groupHash/control/sourceHashStatus"; KEYVALUE="1"; write_etcd_global &
}

event_change_group(){
	# A host has changed groups.
	# We need to populate the host with the group's current state to keep everything synced.
	if [[ -z "$triggerValue" ]]; then
		echo "	No group hash provided!  Using primary group.."
		KEYNAME="/GROUPS/$hostNameSys"; read_etcd_global; primaryGroup="$printvalue"
		triggerValue="$primaryGroup"
	fi
	echo "	Updating host to new group environment: $triggerValue"
	if [[ -z "$hostType" ]]; then
		KEYNAME="/HOSTS/$keyHostName/control/type"; read_etcd_global; hostType="$printvalue"
	fi
	# Read the group's entire keyspace and process for what we need
	KEYNAME="/UI/GROUPS/$triggerValue"; read_etcd_prefix_list; groupKeys="$printvalue"
#	echo "	Group Keys:"
#	echo "$groupKeys"
	exec 3<<<"$groupKeys"
	while read -u 3 -r keyLine && read -u 3 -r valueLine; do
		case "$keyLine" in
			*/control/blankStatus)
				blankStatusValue="$valueLine"
				echo "Got blank for $valueLine"
				;;
			*/control/revealStatus)
				revealStatusValue="$valueLine"
				echo "Got reveal for $valueLine"
				;;
			*/control/sourceHash)
				groupSourceHash="$valueLine"
				continue
				;;
			*/control/previousVideoSourceKey)
				groupPreviousVideoSource="$valueLine"
				continue
				;;
			*/control/sourceCapable)
				groupSourceCapable="$valueLine"
				continue
				;;
			*/control/staticImage)
				groupStaticImage="$valueLine"
				continue
				;;
		esac
	done <&3
	exec 3<&-
	# Determine group video source

	echo -e "Group keys:\n	blank:$blankStatusValue\n	reveal:$revealStatusValue\n	sourcehash: $groupSourceHash\n previous source: $groupPreviousVideoSource"
	# Note we are populating both UI and host keys here, less the /HOSTS/$hostname/control/GROUP key, which triggered this transaction.
	# This is to ensure that we don't get a momentarily "flash" of group input when a host is dragged.
    KEYDATA="
put /HOSTS/$keyHostName/control/blankStatus \"$blankStatusValue\"
put /HOSTS/$keyHostName/control/revealStatus \"$revealStatusValue\"
put /UI/HOSTS/$hostHash/control/blankStatus \"$blankStatusValue\"
put /UI/HOSTS/$hostHash/control/revealStatus \"$revealStatusValue\"
put /UI/HOSTS/$hostHash/control/videoSource \"$groupSourceHash\"

"
	write_etcd_txn "$KEYDATA" &
	# For decoders switching groups, resolve the new group's source.
	# This is lighter than triggering a full group sourceHash refresh event.
	if [[ "$hostType" != *"svr"* ]] && [[ -n "$groupSourceHash" ]]; then
		resolve_group_source_for_host "$keyHostName" "$hostHash" "$groupSourceHash"
	fi
	update_host_config_key "GROUP_HASH" "$triggerValue"
}

new_host(){
	# Responsible for publishing a generated host into the UI.
	# The client controller on each host will subsequently pick up the written UI keys.
	# called via the newHost key from /HOSTS/hostname/control/newHost
    if [[ "$triggerValue" != "1" ]]; then
		echo "	build_completed set to 0, not a new host."
		exit 0
	fi
    # Check group membership
    hostGroup=""
    if [[ -z "$hostGroup" ]]; then
		echo "	Host is not currently a group member, adding to default server group."
		KEYNAME="/GROUPS/$hostNameSys"; read_etcd_global; hostGroup="$printvalue"
	fi
	if [[ -z "$hostHash" ]]; then
		# Note hostHash is not arbitrary - it's generated in etcd_management along with access roles.
		echo "	No host hash has been generated!  Cannot continue to provision the host.."
		exit 0
	fi
	# All of these keys should be populated by the config file available to the server and the host now.
    if ! valid_ipv4 "$hostIP"; then
    	# get the IP address of keyHostName
    	hostIP="$(dig +short "$keyHostName" 2>/dev/null)"
        if [[ -z "$hostIP" ]]; then
            hostIP="$(host "$keyHostName" 2>/dev/null | grep 'has address' | awk '{print $NF}')"
        fi
        if [[ -z "$hostIP" ]]; then
            hostIP="$(ping -c 1 -W 2 "$keyHostName" 2>/dev/null | grep -oP '(?<=from=)[0-9.]+')"
        fi
        KEYNAME="/HOSTS/$keyHostName/control/IP"; KEYVALUE="$hostIP"; write_etcd_global &
    fi
    # Build an etcd transaction
    if [[ "$hostType" == *"svr"* ]]; then
    	echo "	Setting server UI Config keys.."
    	KEYDATA="
put /UI/HOSTS/$hostHash/control/GROUP \"$hostGroup\"
put /UI/HOSTS/$hostHash \"$keyHostName\"
put /UI/HOSTS/$hostHash/control/IP \"$hostIP\"
put /UI/HOSTS/$hostHash/control/type \"$hostType\"
put /UI/HOSTS/$hostHash/control/label \"${hostLabel:-$keyHostName}\"
put /UI/HOSTS/$hostHash/control/blankStatus \"0\"
put /UI/HOSTS/$hostHash/control/directMode \"1\"
put /UI/HOSTS/$hostHash/control/resetStatus \"0\"
put /UI/HOSTS/$hostHash/control/revealStatus \"0\"
put /UI/HOSTS/$hostHash/control/rebootStatus \"0\"
put /UI/HOSTS/$hostHash/control/healthStatus \"0\"
put /UI/HOSTS/$hostHash/control/UIEnable \"1\"

		"
    else
		# New standard host
		echo "	Setting host UI Config keys.."
		KEYDATA="
put /UI/HOSTS/$hostHash/control/IP \"$hostIP\"
put /UI/HOSTS/$hostHash/control/type \"$hostType\"
put /UI/HOSTS/$hostHash/control/label \"${hostLabel:-$keyHostName}\"
put /UI/HOSTS/$hostHash/control/blankStatus \"0\"
put /UI/HOSTS/$hostHash/control/directMode \"1\"
put /UI/HOSTS/$hostHash/control/resetStatus \"0\"
put /UI/HOSTS/$hostHash/control/revealStatus \"0\"
put /UI/HOSTS/$hostHash/control/rebootStatus \"0\"
put /UI/HOSTS/$hostHash/control/healthStatus \"0\"
put /UI/HOSTS/$hostHash/control/UIEnable \"0\"
put /UI/HOSTS/$hostHash/control/GROUP \"$hostGroup\"
put /UI/HOSTS/$hostHash/newHost \"1\"

		"
	fi
	# Note that setting the /UI/control/GROUP key will invoke the server client_controller
	# Populated keys will be picked up by the client-side client_controller to start moving pixels.
	write_etcd_txn "$KEYDATA"
	# Update input devices
    input_device_update
}

resolve_group_source_for_host(){
	# Replicates the resolution logic from event_process_group_videoSource_hosts() but for a single new host.
	local targetHost="$1"
	local targetHostHash="$2"
	local sourceHash="$3"
	if [[ "$sourceHash" =~ ^(0|1|2|3)$ ]]; then
		# Static input - no special keys needed; run_decoder handles this via sourceHash directly
		return 0
	else
		# Look up the input device matching this source hash across all hosts' UI inputs
		local foundInputKey=""
		KEYNAME="/UI/HOSTS/"; read_etcd_prefix_keys || true
		while IFS= read -r line; do
			if [[ "$line" == */inputs/"$sourceHash"* ]]; then
				foundInputKey="$line"
				break
			fi
		done <<<"$printvalue"
		if [[ -z "$foundInputKey" ]]; then
			# Source not found, default to static (mirrors run_decoder fallback)
			return 0
		fi
		KEYNAME="$foundInputKey"; read_etcd_global || true
		local sourceData="$printvalue"
		if [[ "$sourceData" == *"NDI"* ]] || [[ "$sourceData" == *"RTSP"* ]]; then
			# Network device - resolve stream command (mirrors event_get_subscribeStreamCommand)
			local srcIP="${sourceData%;*}"
			local srcHost="${srcIP#*;}"
			srcIP="${srcIP%%;*}"
			srcHost="${srcHost%%;*}.$(dnsdomainname)"
			KEYNAME="/HOSTS/$srcHost/control/directMode"; read_etcd_global || true
			local directMode="$printvalue"
			if [[ "$directMode" == "1" ]]; then
				# Direct mode - use subscribeStream command from the source device
				KEYNAME="/HOSTS/$srcHost/subType"; read_etcd_global || true
				local subType="$printvalue"
				KEYNAME="/HOSTS/$srcHost/uv_stream_cmd/subscribeStream"; read_etcd_global || true
			else
				# Indirect mode - use inputStream from the encoder on the source host (mirrors event_get_subscribeStreamCommand)
				subType="UG"
				KEYNAME="/HOSTS/$srcHost/uv_encode_cmd/inputStream"; read_etcd_global || true
			fi
			local streamCmd="$printvalue"
			if [[ -n "$streamCmd" ]]; then
				local encodedCmd="$(printf '%s' "$streamCmd" | base64)"
				KEYNAME="/HOSTS/$targetHost/control/videoSourceType"; KEYVALUE="network"; write_etcd_global &
				KEYNAME="/HOSTS/$targetHost/control/videoSourceActive"; KEYVALUE="1"; write_etcd_global &
				KEYNAME="/HOSTS/$targetHost/control/videoSourceSubType"; KEYVALUE="$subType"; write_etcd_global &
				KEYNAME="/HOSTS/$targetHost/VIDEO_SOURCE_CMD"; KEYVALUE="$encodedCmd"; write_etcd_global &
			else
				# No stream command available, fall back to UG mode (mirrors event_process_group_videoSource_hosts else branch)
				KEYNAME="/HOSTS/$targetHost/control/videoSourceType"; KEYVALUE="ug"; write_etcd_global &
				KEYNAME="/HOSTS/$targetHost/control/videoSourceActive"; KEYVALUE="1"; write_etcd_global &
				KEYNAME="/HOSTS/$targetHost/control/videoSourceSubType"; KEYVALUE="ug"; write_etcd_global &
			fi
		else
			# Local input - no special keys needed; run_decoder handles this via sourceHash directly
			return 0
		fi
	fi
}

audio_toggle(){
	# TBD - update for group primitives
	KEYNAME="/UI/audio"; read_etcd_global
	if [[ "${printvalue}" != "0" ]]; then
		audioLevel="1.00"
	else
		audioLevel="0.00"
	fi
	# Check wpctl / pactl timeout, if freeze for more than 3 seconds, perform a systemctl reset of the wireplumber service
	# timeout 3s wpctl status >dev/null || echo "command timeout after three seconds! Restarting subsystem.." && systemctl --user restart pipewire.service wireplumber.service
	# get output of wpctl for devices, remove the tree ASCII characters
	output=$(wpctl status | sed 's/├//g; s/─//g; s/│//g; s/└//g')
	# trim output to only the audio block, we aren't interested in the video inputs or other lines
	outputTrimmed=${output#*Audio}
	outputTrimmed=${outputTrimmed%Video*}
	outputTrimmed=${outputTrimmed%Filters*}
	outputTrimmed=${outputTrimmed%Streams*}
	# values for sections we are interested in
	sinksBlock=false
	sourcesBlock=false
	declare -A sinksArr=()
	declare -A sourcesArr=()
	while IFS= read -r line || [[ -n "${line}" ]]; do
		if [[ "${line}" == *"Sinks:"* ]]; then
			sinksBlock=1; sourcesBlock=0; continue
		elif [[ "${line}" == *"Sources:"* ]]; then
			sinksBlock=0; sourcesBlock=1; continue
 		fi
 		if [[ $sinksBlock == 1 || $sourcesBlock == 1 ]]; then
 			# Trim volume arg from the end of the line to produce a valid device name
 			if [[ "${line}" =~ ([0-9]+)\.\ +(.*) ]]; then
 				id="${BASH_REMATCH[1]}"
 				name="${BASH_REMATCH[2]}"
 				# Are we processing a sink or a source?
 				if [[ "$sinksBlock" == 1 ]]; then
 					sinksArr[$id]="${name%[vol*}"
 				elif [[ "$sourcesBlock" == 1 ]]; then
 					sourcesArr[$id]="${name%[vol*}"
 				fi
 			fi
 		fi
 	done <<< "${outputTrimmed}"
 	#echo "Sources array:"
	for key in "${!sourcesArr[@]}"; do
    	echo "	Setting source: $key: ${sourcesArr[$key]} to volume level ${audioLevel}"
    	wpctl set-volume "${key}" "${audioLevel}"
	done
}

bluetooth_connect(){
	# TBD - update for group primitives
	# set bluetooth connection notification bit to 0
	KEYNAME="/audio/bluetooth_connect_notify"; KEYVALUE="0"; write_etcd_global
	# check to see if audio is even enabled, if not, we exit 0
	KEYNAME="/UI/TOGGLES/BLUETOOTH"; read_etcd_global
	if [[ "${printvalue}" == "0" ]]; then
	echo -e "\nAudio bit is not enabled, disabling bluetooth and exiting\n"
	echo -e 'power off\n' | bluetoothctl
	exit 0
	fi
	# Get bluetooth MAC for ExUBT (set in Audio control portion on webUI)
	KEYNAME="/UI/AUDIO/BLUETOOTH_MAC"; read_etcd_global; bluetoothMAC=${printvalue}
	# if bluetoothMAC=""; then
	# echo -e "Bluetooth MAC ID is not populated! Exiting and resetting connect bit"
	# KEYNAME="/interface/bluetooth_connect_active"
	# KEYVALUE="0"
	# write_etcd_global
	# we echo a set of commands to bluetoothctl here.  Obviously this won't work if the server machine has no bluetooth capability!
	# ... so we might want to include a test here and disable the entire area on the webUI if it isn't there?
	echo -e 'power on\n' | bluetoothctl
	echo -e 'default-agent\n' | bluetoothctl
	echo -e 'discoverable on\ndiscoverable-timeout 100\nscan on\n' | bluetoothctl
	sleep 10
	echo -e 'pairable on\n' | bluetoothctl
	echo -e "trust ${bluetoothMAC}\n" | bluetoothctl
	echo -e "pair ${bluetoothMAC}\n" | bluetoothctl
	echo -e "connect ${bluetoothMAC}\n" | bluetoothctl
	# Clean up to stop unauthorized pairing
	echo -e 'pairable off\n' | bluetoothctl
	# Set bluetooth connection successful for webUI tracking
	KEYNAME="/UI/AUDIO/BLUETOOTH_ACTIVE"; KEYVALUE="1"; write_etcd_global
	echo -e "	Bluetooth connection set for ${bluetoothMAC}"
	# do we need to do anything with Pipewire here to set the exUBT/BT device as the audio sink?
}

event_generate_client_conf(){
	# This is a client distress signal notifying the server to generate a proper conf file
	if [[ "$triggerValue" == "1" ]] && [[ "$keyHostName" != "$hostNameSys" ]]; then
		echo "	Generating conf file for a new client.."
		update_host_config_full
		# Absolute /HOSTS/ path - must use the global delete (delete_etcd_key re-prepends the host prefix).
		KEYNAME="/HOSTS/$keyHostName/control/generateConf"; delete_etcd_key_global
	else
		exit 0 # noop
	fi
}

update_host_config_key() {
	# Updates a single key for the host config file
	# Takes two positional args: configKey, configValue
	local short_keyHostName="${keyHostName%%.*}"
	local short_hostNameSys="${hostNameSys%%.*}"
	local configKey="$1"
	local configValue="$2"
	# Validate configValue to prevent sed injection (reject / and newlines)
	if [[ "$configValue" == *"/"* ]] || [[ "$configValue" == *$'\n'* ]] || [[ "$configValue" == *$'\r'* ]]; then
		echo "	ERR: Invalid characters in configValue, rejecting!"
		exit 0
	fi
	# Update the corresponding variable based on configKey
	case "$configKey" in
		HOST_IP)
			HOST_IP="$configValue"
			;;
		GROUP_HASH)
			GROUP_HASH="${configValue}"
			;;
		HOST_TYPE)
			HOST_TYPE="$configValue"
			;;
		INPUT_DEVICE_PRESENT)
			INPUT_DEVICE_PRESENT="$configValue"
			;;
		*) # Not an updatable config key, noop
			exit 0
			;;
	esac
	local configFile="/var/home/wavelet/config/$keyHostName.conf"
	local lockFile="/var/home/wavelet/config/$keyHostName.conf.lock"
	echo "Updating conf file $configFile"
	# Acquire file lock to prevent concurrent modifications
	exec 200>"$lockFile"
	flock -x 200
	# Find the key in our config file and update it
	# sed replace the line starting with "export $configKey=" to the updated value.
	if grep -q "^export $configKey=" "$configFile"; then
		sed -i "s/^export $configKey=.*/export $configKey=\"$configValue\"/" "$configFile"
	else
		echo "export $configKey=\"$configValue\"" >> "$configFile"
	fi
	# Release file lock
	flock -u 200
	# Upload the client config
	upload_client_config
}

update_host_config_full() {
	# Updates the host config file completely.
	# Hosts refer to this file locally in order to reduce etcd reads and other waits.
	# Skip if this is the server host - server config is managed by bootstrap and should not be overwritten
	if [[ "$keyHostName" == "$hostNameSys" ]] || [[ "$keyHostName" == "$hostNameSys".* ]]; then
		echo "Server config file already generated by bootstrap, skipping orchestrator config update."
		return 0
	fi
	KEYNAME="/UI/GLOBALS/control/CLUSTERID"; read_etcd_global; CLUSTER_ID="$printvalue"
	# The primary group hash, clients with no group always return here.
	# Since we are in the orchestrator.sh module, this is only ever going to be svr.
	KEYNAME="/GROUPS/$hostNameSys"; read_etcd_global; PRIMARY_GROUPHASH="$printvalue"
	# must modify etcd_management so hosts can read this specific key (but not prefix behind it)
	KEYNAME="/HOSTS/$SVR_HOSTNAME"; read_etcd_global; SERVER_HOSTHASH="$printvalue"
	# the client often needs reference to its own hosthash.  This is generated by orchestrator during new_host setup.
	KEYNAME="/HOSTS/$keyHostName"; read_etcd_global; CLIENT_HOSTHASH="$printvalue"
	# Input device status
	KEYNAME="/HOSTS/$keyHostName/INPUT_DEVICE_PRESENT"; read_etcd_global; INPUT_DEVICE_PRESENT="${printvalue:-0}"
	KEYNAME="/HOSTS/$keyHostName/control/IP"; read_etcd_global; HOST_IP="$printvalue"
	KEYNAME="/HOSTS/$keyHostName/control/type"; read_etcd_global; HOST_TYPE="$printvalue"
	# Build the Mod configuration content
	# Orchestrator responds to /HOSTS/$clientHostName/control/GROUP
	KEYNAME="/HOSTS/$keyHostName/control/GROUP"; read_etcd_global; GROUP_HASH="$printvalue"
	# Clients ALWAYS start as a decoder, then it is controlled from /UI/HOSTS/$hostHash/control/type via event_promote
	if [[ -z "$HOST_TYPE" ]]; then
		if [[ "$keyHostName" == "$hostNameSys" ]]; then
			echo "Cannot modify server conf!"
			exit 0
		else
			# No, we aren't always a dec, sometimes we are a "net" device!
			HOST_TYPE="dec"
		fi
	fi
	if [[ -z "$hostHash" ]] && [[ -n "$CLIENT_HOSTHASH" ]]; then
		hostHash="$CLIENT_HOSTHASH"
	fi
	local newVersion=1
	# Ensure wavelet.conf is sourced to load vars
	source "/etc/wavelet.conf"
	# Unpopulated var guards, because apparently we need them.
	if [[ -z "$SVR_HOSTNAME" ]]; then
		echo "	ERR: SVR_HOSTNAME not populated.  Populating from local env.."
		SVR_HOSTNAME="$(hostname)"
	fi
	if [[ -z "$SERVER_HOSTHASH" ]]; then
		echo "	ERR: SVR_HOSTHASH not populated.  Reading from etcd.."
		KEYNAME="/HOSTS/$hostNameSys"; read_etcd_global; SERVER_HOSTHASH="$printvalue"
		# TODO etcdctl read for server hosthash
	fi
	if [[ -z "$GROUP_HASH" ]]; then
		echo "	ERR: GROUP_HASH not populated. Reading from etcd.."
		KEYNAME="/GROUPS/$hostNameSys"; read_etcd_global; GROUP_HASH="$printvalue"
	fi

	# Here, we build the file contents properly.
	local configFile="/var/home/wavelet/config/$keyHostName.conf"
	local lockFile="/var/home/wavelet/config/$keyHostName.conf.lock"
	# Acquire file lock to prevent concurrent modifications
	exec 200>"$lockFile"
	flock -x 200
	cat > "$configFile" <<-EOF
		export CLUSTER_ID="$CLUSTER_ID"
		export PRIMARY_GROUPHASH="$PRIMARY_GROUPHASH"
		export SERVER_HOSTNAME="$SVR_HOSTNAME"
		export SERVER_HOSTHASH="$SERVER_HOSTHASH"
		export CLIENT_HOSTHASH="$CLIENT_HOSTHASH"
		export GROUP_HASH="$GROUP_HASH"
		export HOST_TYPE="$HOST_TYPE"
		export HOST_IP="$HOST_IP"
		export INPUT_DEVICE_PRESENT="$INPUT_DEVICE_PRESENT"
		export MOD_REVISION="$newVersion"
	EOF
	# Release file lock
	flock -u 200
	upload_client_config
	# Populate our vars encase this was initial config and we are running through new_host subsequently.
	hostHash="$CLIENT_HOSTHASH"
	groupHash="$GROUP_HASH"
	hostType="$HOST_TYPE"
	serverHostname="$SERVER_HOSTNAME"
	clusterId="$CLUSTER_ID"
	primaryGroupHash="$PRIMARY_GROUPHASH"
	serverHostHash="$SERVER_HOSTHASH"
	hostIp="$HOST_IP"
	inputDevicePresent="$INPUT_DEVICE_PRESENT"
	modRevision="1"
}

upload_client_config(){
	local checksum; local encodedConfig
	echo "Uploading client config $configFile"
	# Handles the checksumming and actual uploading
#	echo -e "Generated config to $configFile:\n$(<$configFile)"
	# Calculate checksum
	checksum="$(sha256sum <"$configFile" | tr -d ' \t\n-')"
	# Encode to base64
	encodedConfig="$(base64 -w 0 <"$configFile")"
	# Atomic transaction to update config, checksum, and version
	# on the client side, the client_controller will activate on confHash being written and pull the new config
	# If checksum == confHash current val, fail txn as nothing changed.
	# TODO - how does it calculate < or > for the checksum?  this could break if it doesn't enumerate correctly!
	KEYNAME="/HOSTS/$keyHostName/confHash"; read_etcd_global; currentChecksum="$printvalue"
	if [[ "$checksum" == "$currentChecksum" ]]; then
		echo "	Checksum hasn't changed - noop"
		exit 0
	fi
	KEYDATA="
put /HOSTS/$keyHostName/conf \"$encodedConfig\"
put /HOSTS/$keyHostName/confHash \"$checksum\"
put /UI/HOSTS/$hostHash/confUpdate \"1\"

"
	echo "	Note:  FAIL means the conf does not need updating as config checksum = the current confHash value!"
	write_etcd_txn "$KEYDATA" &
}


#####
#
# Main
#
#####


start_timer
trap 'stop_timer "$timer_id_out"; echo "Total: ${timer_duration}s" >&2' EXIT

hostNameSys=$(hostname)
logName="/var/home/wavelet/logs/orch.log"
exec >> "$logName" 2>&1
#time=0
detect_self