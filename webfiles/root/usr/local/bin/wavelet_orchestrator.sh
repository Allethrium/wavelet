#!/bin/bash
trap 'stop_timer' EXIT
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
		echo -e "The orchestrator will not run on anything other than the server!"
		exit 1
	fi
}

event_server(){
	# Filter our trigger env and generate local environment data
	triggerKey="${ETCD_WATCH_KEY//\"}"
	triggerValue="${ETCD_WATCH_VALUE//\"}"
	keyHostName="${triggerKey#*/HOSTS/}"; keyHostName="${keyHostName%%/*}"
	KEYNAME="/HOSTS/$keyHostName"; read_etcd_global; hostHash="$printvalue"
    if [[ -z "$hostHash" ]]; then
    	echo "	No hostHash available!  Skipping event for $triggerKey"
    	exit 0
    fi
	KEYNAME="/HOSTS/$keyHostName/control/GROUP"; read_etcd_global; hostGroup="$printvalue"
	KEYNAME="HOSTS/$hostNameSys/control/GROUP"; read_etcd_global; primaryGroup="$printvalue"
	if [[ "$keyHostName" != *"$(dnsdomainname)" ]]; then
		echo "Invalid client hostname.."
		exit 0
	fi
	echo "Triggered with: $triggerKey, $triggerValue"
	case "$triggerKey" in
		*healthStatus*)
			health_status_update;; # Updates the device health status in UI prefix
		*inputUpdate*)
			input_device_update;; # Looks for inputs registered on this host and updates UI prefix
		*wavelet_build_completed*)
			new_host;; # Proceeds to update UI with new host keys
		*TOGGLES*)
			toggle_control;; # Handles any toggles we may need
		*HOSTUPDATE*)
			host_update;; # Generalized flag for informing orchestrator host status has changed
		*reflectorRequest*)
			event_subscription_request;; # Adds the decoder to a reflector subscription
		*unsubRequest*)
			event_unsubscription_request;;# Removes the decoder from a reflector subscription
		*DECODER_ERR*)
			event_decoder_sub_error;; # Responds to a reflector noting a ping failure/network error with a decoder
		*NETWORK_SENSE*)
			event_network_sense;; # Responds to a network_sense key being written from DHCP.
		*/IP)
			event_update_ip;; # Updates a host IP
		*/control/encoder_primed)
			event_encoder_primed;; # Signal the encoder process is up and we are nearly streaming
		*/control/encoder_ready)
			event_encoder_ready;; # Encoder is correctly streaming video
		*/control/GROUP)
			event_change_group;;
		*/control/screenCastCapable)
			# Enable screencasting, as a suitable WiFi device has been detected.
			KEYNAME="/UI/HOSTS/$hostHash/control/screenCastCapable"; KEYVALUE="$triggerValue"; write_etcd_global & ;;
		*)
			exit 0;; # noop
		esac
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
    KEYNAME="/HOSTS/$keyHostName/control/inputUpdate"; delete_etcd_key &
}

get_hosts_in_group(){
	echo "      Searching for hosts within the group $hostGroup.."
	hostsInGroup=()
	local hostName
  	while IFS= read -r line; do
   		if [[ "$line" == *"/control/GROUP"* ]]; then
   	  		KEYNAME="$line"; read_etcd_global
   	  		if [[ "$printvalue" == "$hostGroup" ]]; then
   		  		hostName="${line#*/HOSTS/}"
   		  		hostName="${hostName%%/control/GROUP*}"
   		  		KEYNAME="/HOSTS/$hostName/IP"; read_etcd_global; ipAddr="$printvalue"
   		  		if [[ "$hostName" == "$targetHostName" ]]; then
   		  			echo "      Skipping adding the encoder to its own reflector in order to avoid transmission loops!"
   		  			continue
   		  		else
   		  			hostsInGroup+=("$hostName:$ipAddr")
   		  		fi
   			fi
   		fi
	done <<<"$allHostKeys"
}

event_subscription_request(){
	# This should take a subscription request from a host writing its key in /HOSTS/$hostName/reflectorRequest
	# The key is written when the decoder launches wavelet_run in order to start a display task.
	local hostName; local inputHash; local hostIPAddress; local KEYNAME;
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
	# Dig would be quicker than an etcd read, however the cached IP address is not always correct.
	# This is because the host will initially populate with the wired IP address, but switches to wireless
	# It can take some minutes to failover, resulting in the wired IP being provided to the reflector.
	KEYNAME="/HOSTS/$keyHostName/IP"; read_etcd_global; hostIpAddress="$printvalue"
	if [[ -z "$hostIpAddress" ]]; then
        hostIpAddress="$(dig +short "$keyHostName")"
    fi
    if valid_ipv4 "$hostIpAddress"; then
        echo "      Resolved valid IP, updating the host.."
        KEYNAME="/HOSTS/$keyHostName/IP"; write_etcd_global &
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

	KEYNAME="/HOSTS/$targetHostName/DECODER_SUB_LIST/$keyHostName"; KEYVALUE="$hostIpAddress"; write_etcd_global &
	KEYNAME="/HOSTS/$keyHostName/control/currentUGReflectorHost"; KEYVALUE="$targetHostName"; write_etcd_global &
	echo "      Requesting port from reflector at $targetHostName for host $keyHostName with IP Address: $hostIpAddress"
	# Since we don't need to worry about indexing anymore, we can just forward this on to the reflector
	# At this point, the reflector should swing into action, and be able to read the populated IP addresses directly.
	# This is preferable to hostnames because the IP addresses as print-values-only come out as a simple list in ETCD
	return 0
}

event_unsubscription_request(){
    # Removes a decoder/UltraGrid client from an UltraGrid reflector on the targeted host
	supplicantHostName="${triggerKey#*/HOSTS/}"
	supplicantHostName="${supplicantHostName%%/*}"
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
    # Perform an atomic write with an etcdctl check that the key exists and it not null included
    KEYDATA="mod(\"/HOSTS/$targetHostName\") > \"0\"

put /UI/HOSTS/$hostHash/control/healthStatus \"$triggerValue\"
put /UI/HOSTS/$hostHash/control/lastError \"$(date +%s)\"
put /UI/HOSTS/$hostHash/control/errorCode \"$triggerValue\"

put /UI/HOSTS/$hostHash/control/healthStatus \"$triggerValue\"
put /UI/HOSTS/$hostHash/control/lastError \"$(date +%s)\"
put /UI/HOSTS/$hostHash/control/errorCode \"$triggerValue\"

"
    write_etcd_txn "$KEYDATA"
    # Note, this transaction is designed to fail if the host key is NOT present in the UI (stops writing a key for a nonprovisioned device!)
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
	ip_count=$(echo "$triggerValue" | grep -oP '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b' | wc -l)
	if [[ $ip_count -gt 1 ]]; then
		echo "	ERROR! Host has $ip_count IP addresses in field: '$triggerValue'"
		exit 1
	fi
	KEYNAME="/UI/HOSTS/$hostHash/IP"; KEYVALUE="$triggerValue"; write_etcd_global &
	echo "	Updating host $keyHostName UI key: $KEYNAME to IP: $triggerValue"
}

event_encoder_primed(){
	# Set sourceHashstatus to primed
	KEYNAME="/UI/GROUPS/$hostGroup/control/sourceHashStatus"; KEYVALUE="2"; write_etcd_global &
}
event_encoder_ready(){
	# Set sourceHashStatus to ready
	KEYNAME="/UI/GROUPS/$hostGroup/control/sourceHashStatus"; KEYVALUE="1"; write_etcd_global &
}
event_encoder_error(){
	# Set sourceHashStatus to error/dead
	KEYNAME="/UI/GROUPS/$hostGroup/control/sourceHashStatus"; KEYVALUE="3"; write_etcd_global &
}

event_change_group(){
	# A host has changed groups.  We need to populate the host with the group's current state to keep everything synced.
	if [[ -z "$triggerValue" ]]; then
		echo "	No group hash provided!  Using primary group.."
		KEYNAME="/GROUPS/$hostNameSys"; read_etcd_global; primaryGroup="$printvalue"
		triggerValue="$primaryGroup"
	fi
	echo "	Updating host to new group environment: $triggerValue"
	KEYNAME="/HOSTS/$keyHostName/type"; read_etcd_global; hostType="$printvalue"
	KEYNAME="/UI/GROUPS/$triggerValue"; read_etcd_prefix_list; groupKeys="$printvalue"
	echo "	Group Keys:"
	echo "$groupKeys"
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
		esac
	done <&3
	exec 3<&-
	echo -e "Group keys:\n	blank:$blankStatusValue\n	reveal:$revealStatusValue\n	sourcehash: $groupSourceHash\n previous source: $groupPreviousVideoSource"
	# Note we are populating both UI and host keys here, less the host/control/GROUP key, which triggered this transaction.
	# This is to ensure that we don't get a momentarily "flash" of group input when a host is dragged.
    KEYDATA="mod(\"/UI/HOSTS/$hostHash\") = \"0\"

put /HOSTS/$keyHostName/control/blankStatus \"$blankStatusValue\"
put /HOSTS/$keyHostName/control/revealStatus \"$revealStatusValue\"
put /UI/HOSTS/$hostHash/control/GROUP \"$triggerValue\"
put /UI/HOSTS/$hostHash/control/blankStatus \"$blankStatusValue\"
put /UI/HOSTS/$hostHash/control/revealStatus \"$revealStatusValue\"
put /UI/HOSTS/$hostHash/control/videoSource \"$groupSourceHash\"

put /HOSTS/$keyHostName/control/blankStatus \"$blankStatusValue\"
put /HOSTS/$keyHostName/control/revealStatus \"$revealStatusValue\"
put /UI/HOSTS/$hostHash/control/GROUP \"$triggerValue\"
put /UI/HOSTS/$hostHash/control/blankStatus \"$blankStatusValue\"
put /UI/HOSTS/$hostHash/control/revealStatus \"$revealStatusValue\"
put /UI/HOSTS/$hostHash/control/videoSource \"$groupSourceHash\"

"
	write_etcd_txn "$KEYDATA" &
	# For decoders switching groups, resolve the new group's source just like new_host() does.
	if [[ "$hostType" != *"svr"* ]] && [[ -n "$groupSourceHash" ]]; then
		resolve_group_source_for_host "$keyHostName" "$hostHash" "$groupSourceHash"
	fi
}

event_control_update() {
	# Updates the control key for the host in its UI
	if [[ "$triggerKey" == *"videoSource"* ]]; then
		# we don't do anything
		return
	else
		# This writes to the UI key to ensure the UI controls reflect the actual system state
		uiKey="${triggerKey##*/}"
		echo "		Updating UI control status for key $triggerKey and value $triggerValue.."
		KEYNAME="/UI/HOSTS/$hostHash/control/$uiKey"; KEYVALUE="$triggerValue"; write_etcd_global
	fi
}

new_host(){
	# Sets up for a totally new host
    if [[ "$triggerValue" != "1" ]]; then
		echo "	build_completed set to 0, not a new host."
		exit 0
	fi
    # Check group membership
    if [[ -z "$hostGroup" ]]; then
        echo "	Host is not currently a group member, adding to default server group."
        KEYNAME="/GROUPS/$hostNameSys"; read_etcd_global; hostGroup="$printvalue"
	fi
	if [[ -z "$hostHash" ]]; then
	    echo "	No host hash has been generated!  Cannot continue to provision the host.."
	    exit 0
	fi
	echo "      Generating a new host entry for: $keyHostName.."
	KEYNAME="/HOSTS/$keyHostName/IP"; read_etcd_global; hostIPAddress="$printvalue"
	KEYNAME="/HOSTS/$keyHostName/type"; read_etcd_global; hostType="$printvalue"
	KEYNAME="/HOSTS/$keyHostName/control/label"; read_etcd_global; hostLabel="$printvalue"
	KEYNAME="/UI/GROUPS/$hostGroup/control/sourceHash"; read_etcd_global; groupVideoSource="$printvalue"
    if ! valid_ipv4 "$hostIPAddress"; then
    	# get the IP address of keyHostName
    	hostIPAddress="$(dig +short "$keyHostName" 2>/dev/null)"
        if [[ -z "$hostIPAddress" ]]; then
            hostIPAddress="$(host "$keyHostName" 2>/dev/null | grep 'has address' | awk '{print $NF}')"
        fi
        if [[ -z "$hostIPAddress" ]]; then
            hostIPAddress="$(ping -c 1 -W 2 "$keyHostName" 2>/dev/null | grep -oP '(?<=from=)[0-9.]+')"
        fi
        KEYNAME="/HOSTS/$keyHostName/IP"; KEYVALUE="$hostIPAddress"; write_etcd_global &
    fi
    # Here we need to generate an appropriate videoSourcePayLoad key.
    if [[ "$groupVideoSource" == "1" ]]; then
    	videoSourcePayLoad="type:static|active:0|subType:static|cmd"
    fi
    # Build an etcd transaction - it doesn't matter if the key exists or not, we overwrite it.
    if [[ "$hostType" == *"svr"* ]]; then
    	KEYDATA="mod(\"/UI/HOSTS/$hostHash\") = \"0\"

put /UI/HOSTS/$hostHash/control/GROUP \"$hostGroup\"
put /UI/HOSTS/$hostHash \"$keyHostName\"
put /UI/HOSTS/$hostHash/IP \"$hostIPAddress\"
put /UI/HOSTS/$hostHash/type \"$hostType\"
put /UI/HOSTS/$hostHash/control/label \"${hostLabel:-$keyHostName}\"
put /UI/HOSTS/$hostHash/control/blankStatus \"0\"
put /UI/HOSTS/$hostHash/control/directMode \"1\"
put /UI/HOSTS/$hostHash/control/resetStatus \"0\"
put /UI/HOSTS/$hostHash/control/revealStatus \"0\"
put /UI/HOSTS/$hostHash/control/rebootStatus \"0\"
put /UI/HOSTS/$hostHash/control/healthStatus \"0\"
put /UI/HOSTS/$hostHash/control/UIEnable \"1\"
put /UI/HOSTS/$hostHash/control/videoSource \"$groupVideoSource\"

put /UI/HOSTS/$hostHash/control/GROUP \"$hostGroup\"
put /UI/HOSTS/$hostHash \"$keyHostName\"
put /UI/HOSTS/$hostHash/IP \"$hostIPAddress\"
put /UI/HOSTS/$hostHash/type \"$hostType\"
put /UI/HOSTS/$hostHash/control/label \"${hostLabel:-$keyHostName}\"
put /UI/HOSTS/$hostHash/control/blankStatus \"0\"
put /UI/HOSTS/$hostHash/control/directMode \"1\"
put /UI/HOSTS/$hostHash/control/resetStatus \"0\"
put /UI/HOSTS/$hostHash/control/revealStatus \"0\"
put /UI/HOSTS/$hostHash/control/rebootStatus \"0\"
put /UI/HOSTS/$hostHash/control/healthStatus \"0\"
put /UI/HOSTS/$hostHash/control/UIEnable \"1\"
put /UI/HOSTS/$hostHash/control/videoSource \"$groupVideoSource\"

		"
    else
    	# For decoders, resolve the group's video source and populate decoder-side keys.
        if [[ "$hostType" != *"svr"* ]] && [[ -n "$groupVideoSource" ]]; then
        	resolve_group_source_for_host "$keyHostName" "$hostHash" "$groupVideoSource"
        fi
    	KEYDATA="mod(\"/UI/HOSTS/$hostHash\") = \"0\"

put /UI/HOSTS/$hostHash/control/GROUP \"$hostGroup\"
put /UI/HOSTS/$hostHash \"$keyHostName\"
put /UI/HOSTS/$hostHash/IP \"$hostIPAddress\"
put /UI/HOSTS/$hostHash/type \"$hostType\"
put /UI/HOSTS/$hostHash/control/label \"${hostLabel:-$keyHostName}\"
put /UI/HOSTS/$hostHash/control/blankStatus \"0\"
put /UI/HOSTS/$hostHash/control/directMode \"1\"
put /UI/HOSTS/$hostHash/control/resetStatus \"0\"
put /UI/HOSTS/$hostHash/control/revealStatus \"0\"
put /UI/HOSTS/$hostHash/control/rebootStatus \"0\"
put /UI/HOSTS/$hostHash/control/healthStatus \"0\"
put /UI/HOSTS/$hostHash/control/UIEnable \"0\"
put /UI/HOSTS/$hostHash/control/videoSourceConfig \"$videoSourcePayLoad\"
put /UI/HOSTS/$hostHash/control/videoSource \"$groupVideoSource\"

put /UI/HOSTS/$hostHash/control/GROUP \"$hostGroup\"
put /UI/HOSTS/$hostHash \"$keyHostName\"
put /UI/HOSTS/$hostHash/IP \"$hostIPAddress\"
put /UI/HOSTS/$hostHash/type \"$hostType\"
put /UI/HOSTS/$hostHash/control/label \"${hostLabel:-$keyHostName}\"
put /UI/HOSTS/$hostHash/control/blankStatus \"0\"
put /UI/HOSTS/$hostHash/control/directMode \"1\"
put /UI/HOSTS/$hostHash/control/resetStatus \"0\"
put /UI/HOSTS/$hostHash/control/revealStatus \"0\"
put /UI/HOSTS/$hostHash/control/rebootStatus \"0\"
put /UI/HOSTS/$hostHash/control/healthStatus \"0\"
put /UI/HOSTS/$hostHash/control/UIEnable \"0\"
put /UI/HOSTS/$hostHash/control/videoSourceConfig \"$videoSourcePayLoad\"
put /UI/HOSTS/$hostHash/control/videoSource \"$groupVideoSource\"

		"
	fi
	echo "DEBUG: TXN KEYDATA: $KEYDATA"
	write_etcd_txn "$KEYDATA"
	# Write the new host key so the UI knows to generate this new host
	# Note this occurs after the host txn has fully populated other keys.
	KEYNAME="/UI/HOSTS/$hostHash/newHost"; KEYVALUE="1"; write_etcd_global &
	# Update input devices
    input_device_update
}

# Replicates the resolution logic from event_process_group_videoSource_hosts() but for a single new host.
resolve_group_source_for_host(){
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
	if [[ "${printvalue}" -ne 0 ]]; then
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
	if [[ "${printvalue}" -eq "0" ]]; then
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

toggle_control() {
    # Handles toggle responses from the host, overwrites values in the UI and ensures it appropriately reflects the host state.
    echo "	Toggle activated on host $triggerKey for value: $triggerValue, updating UI"
    # Update the toggle value in the UI
   	KEYNAME="/UI/HOSTS/$hostHash/control/${triggerKey##*/control/}"; KEYVALUE="$triggerValue"; write_etcd_global
}

set_poll_key(){
    # Responsible for telling the UI which element to refresh
    # Ideally, the UI should look for the parent div to the presented hash, then remove and regenerate it.
	# generates a timestamp, concats with with the type after a three second delay to allow the system to settle
	sleep 3
	KEYNAME="/UI/POLL_UPDATE"; KEYVALUE="$(date +%s)|${1}"; write_etcd_global
	echo "/UI/POLL_UPDATE key updated with ${KEYVALUE}, UI should pick up changes on next polling cycle!"
}

host_update(){
    # Since HOSTUPDATE is provided with the update key in the value field, we do;
    KEYNAME="$ETCD_WATCH_VALUE"; read_etcd_global; KEYVALUE="$printvalue"
    # now we'd write the KEYNAME correspondant in the UI appropriately.
}

# These keys are what we will need to focus on.  Data can be pulled from /HOSTS/hostname mostly

#	Network_device should now populate itself in /HOSTS/ as it is.. well, a host.
#	We can store cred + certificate data here, as well as its group membership
#	Network devices are the only kind of input that gets its own group membership, because on a wavelet host
#	it would always be the host handling the reflector, and therefore being a better representative of the group

#	From these keys, we will be responsible for ensuring that group membership requests are processed
#	network inputs should be automatically provisioned with a groupHash UUID and reflector args,
#	in effect spinning up a reflector "instance" for every network device we detect.
#	Wavelet encoder HOSTS will get their own reflector by default
#	/$hostNameSys/DECODER_SUB_LIST -- $groupHash ID's the device with its hash
#	subkeys in DECODER_SUB_LIST are hostname - IPAddr and represent the decoder members of the group
#	I'd really like to explore the mDNS functionality more to get this working transparently...

#	We are also responsible for counting encoders when they have the device ENCODER_QUERY asks for.
#		KEYNAME="/UI/HOSTS/$hostHash/notify/HASH_ACTIVE/$hashValue"; KEYVALUE="1"; write_etcd_global > HASH_ACTIVE main key to UI?


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
time=0
detect_self