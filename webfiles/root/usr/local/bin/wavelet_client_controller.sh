#!/bin/bash

# This module is responsible for orchestrating client activities based off key changes from /UI/HOSTS/$hostname/control
# It replaces the previous approach of having many different individual modules and watcher systemd services.
# The client controller runs on the client devices directly.

# /UI/HOSTS/$hostHash						-	the device prefix key and hostname
# /UI/HOSTS/$hostHash/control/IP			-	IP4 Addr
# /UI/HOSTS/$hostHash/control/blankStatus	-	function decides on what to do based off type, blanks the input/output
# /UI/HOSTS/$hostHash/control/rebootStatus	-	reboot flag for this host
# /UI/HOSTS/$hostHash/control/resetStatus	-	process term/restart to avoid cold reset
# /UI/HOSTS/$hostHash/control/revealStatus	-	displays a testcard from host if encoder, displays testcard on only host if decoder
# /UI/HOSTS/$hostHash/control/label 		-	changes the device pretty hostname
# /UI/HOSTS/$hostHash/control/PROMOTE 		-	switches clients between encoders or decoders
# /UI/HOSTS/$hostHash/hash 					-	does not change, this is the device's unique ID used to populate the webUI and identify it
# /UI/HOSTS/$hostHash/control/type			-	the device type
# /UI/HOSTS/$hostHash/groupHash				-	the identifying hash of the device's group membership

# Clients may also write to their own prefixes in /HOSTS/$hostNameSys///

# Therefore, this module may be thought of as informing hosts in /HOSTS/$hostNameSys, whereas the orchestrator handles the opposite flow.
# Note changes made by this module will automatically run through the orchestrator, so verification is built-in.
# This module should employ filtering to prevent malicious data being submitted from the UI, eventually.

# Source files
ETCDINTERACTIONHOOKS=""
if [[ -f /var/wavelet_ramfs/etcd_interaction_hooks.sh ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source /usr/local/bin/etcd_interaction_hooks.sh
	ETCDINTERACTIONMOD="/usr/local/bin/etcd_interaction_hooks.sh"
fi

WAVELET_DETECTV4L_MOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_detectv4l.sh" ]]; then
	WAVELET_DETECTV4L_MOD="/var/wavelet_ramfs/wavelet_detectv4l.sh"
else
	WAVELET_DETECTV4L_MOD="/usr/local/bin/wavelet_detectv4l.sh"
fi

WAVELET_ENCODER_MOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_encoder.sh" ]]; then
	WAVELET_ENCODER_MOD="/var/wavelet_ramfs/wavelet_encoder.sh"
else
	WAVELET_ENCODER_MOD="/usr/local/bin/wavelet_encoder.sh"
fi

WAVELET_SCREENCAST_MOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_screencast.sh" ]]; then
	WAVELET_SCREENCAST_MOD="/var/wavelet_ramfs/wavelet_screencast.sh"
else
	WAVELET_SCREENCAST_MOD="/usr/local/bin/wavelet_screencast.sh"
fi

# Process inputs
detect_operation(){
	# Inputs are specified from the etcdctl process which spawns this module
	# Therefore they will be populated along with their revision numbers in ENV
	thisHostHash="${etcdKey#/UI/HOSTS/}"
	thisHostHash="${thisHostHash%%/*}"
	local control_suffix="${etcdKey#/UI/HOSTS/$thisHostHash/control/}"
	control_suffix="${control_suffix##*/}"

	if [[ "$thisHostHash" != "$hostHash" ]]; then
		# Not meant for this machine
		echo "	No match for this host hash: $thisHostHash"
		exit 0
	fi
#	echo -e "	Host Matching:\n		Key: $etcdKey\n		Value: $etcdValue"
	case "$control_suffix" in
		"label")			handler_function="event_relabel";;
		"authScreencast")	handler_function="authorize_screencast";;
		"blankStatus")		handler_function="event_blank";;
		"deprovision")		handler_function="event_deprovision";;
		"directMode")		handler_function="event_set_directMode";;
		"enableScreencast")	handler_function="toggle_screencast";;
		"GROUP")			handler_function="event_change_group";;
		"promote")			handler_function="event_promote";;
		"rebootStatus")	    handler_function="event_reboot";;
		"resetStatus")	    handler_function="event_reset";;
		"revealStatus")	    handler_function="event_reveal";;
		"updateImage")		handler_function="regenerate_staticImage";;
		"UIEnable")			handler_function="toggle_userInterface";;
		"videoSource")		handler_function="wavelet_run";;
		"confUpdate")		handler_function="update_config";;
		*) echo "	Invalid function key: $control_suffix"; exit 0;; #noop
	esac
	if [[ -n "$handler_function" ]] && declare -f "$handler_function" > /dev/null; then
        $handler_function
    fi
}

detect_operation_server(){
	# This specifically runs from the server and handles group and other UI signals
	if [[ "$etcdKey" == *"//"* ]] || [[ -z "$etcdKey" ]]; then
		# getting a double // delimeter or a null means we have a bad key, and we should noop it.
		exit 0
	fi
	echo "	Server Matching $etcdKey -- $etcdValue"
	if [[ "$etcdKey" == *"/deprovision"* ]]; then
		# we should start a deprovision timer here.
		event_deprovision_timer
	fi
	local control_suffix="${etcdKey#/UI/HOSTS/$thisHostHash/control/}"
	control_suffix="${control_suffix%%/*}"
	if [[ "$etcdKey" == "/UI/GLOBALS/control/GROUP-CREATE" ]]; then
		event_create_group
	elif [[ "$etcdKey" == "/UI/GLOBALS/control/GROUP-DELETE" ]]; then
		event_delete_group
	elif [[ "$etcdKey" == "/UI/GROUPS/"* ]]; then
		groupHash="${etcdKey#/UI/GROUPS/}"
		local control_suffix="${groupHash##*/}"
		groupHash="${groupHash%%/*}"
		# Guard: a valid group key is always a full sha256 hash. Anything else
		# is malformed/phantom data (e.g. source values like "1" or "2--2" that
		# were once used as group keys). Delete it so it cannot pollute the UI
		# or keep being re-emitted on every SSE reconnect.
		# Note the second if block prevents deletion of the entire groups prefix.
		if [[ ! "$groupHash" =~ ^[a-f0-9]{64}$ ]] && [[ "$groupHash" != "/UI/GROUPS/" ]]; then
			echo "	Auto-cleaning malformed group key: /UI/GROUPS/$groupHash"
			KEYNAME="/UI/GROUPS/$groupHash"; delete_etcd_key_prefix_global &
			exit 0
		fi
		case "$control_suffix" in
			"audioStatus")		handler_function="event_group_enable_audio";;
			"bannerStatus")		handler_function="event_group_enable_banner";;
			"blankStatus")		handler_function="event_group_host_blank";;
			"liveStreamStatus")	handler_function="event_group_liveStream";;
			"persistStatus")	handler_function="event_group_input_persist";;
			"rebootStatus")		handler_function="event_group_host_reboot";;
			"resetStatus")		handler_function="event_group_host_reset";;
			"revealStatus")		handler_function="event_group_host_reveal";;
			"bannercontent")	handler_function="event_group_set_bannerContent";;
			"liveStreamData")	handler_function="event_group_set_liveStreamConfig";;
			"blueToothMAC")		handler_function="event_group_set_blueToothMAC";;
			"sourceHash")		handler_function="event_group_set_video_source";;
			"staticImage")		handler_function="event_group_set_staticImage";;
			"activeCodec")		handler_function="event_group_set_codec";;
			*) exit 0;;
		esac
		if [[ -n "$handler_function" ]] && declare -f "$handler_function" > /dev/null; then
			$handler_function
		fi
	elif [[ "$etcdKey" == "/UI/HOSTS/"* ]]; then
		local thisHostHash
		thisHostHash="${etcdKey#/UI/HOSTS/}"
		thisHostHash="${thisHostHash%%/*}"
		# Note the second if block prevents deletion of the entire groups prefix.
    	if [[ ! "$thisHostHash" =~ ^[a-f0-9]{64}$ ]] && [[ "$thisHostHash" != "/UI/HOSTS/" ]]; then
    		# Guard: host keys are full sha256 hashes. Auto-clean malformed ones.
    		echo "	Auto-cleaning malformed host key: /UI/HOSTS/$thisHostHash"
    		KEYNAME="/UI/HOSTS/$thisHostHash"; delete_etcd_key_prefix_global &
    		exit 0
    	fi
    	if [[ "$thisHostHash" == "$hostHash" ]]; then
    		echo "	HOSTS operation targeted at server, proceeding to detect_operation.."
    		detect_operation
    	fi
	else
		echo "  Invalid key match, exiting."
		exit 0
	fi
}

# GROUP functionality
event_group_enable_audio() {
	# Enables audio output from the encoder in the group via bluetooth.
	# Note this does NOT enable audio output to wavelet decoders for latency and sync reasons.
	echo "		Enabling audio output to the MAC specified in group settings."
	echo "		Please note the installation engineer is responsible for ensuring the bluetooth device is available."
	# Get bluetooth MAC
	# ensure encoder is aware of these data
	# encoder handles the rest
}

event_group_enable_banner() {
	# Enables the graphical banner
	# TODO - this should now be printed on the decoder side via swayimg, as wlroots will be quicker than UG
	# This also avoids watermarking the stream
	echo "	Banner enabled"
	# encoder handles the rest
}

process_hostlist() {
	# Performs $1 for value $2 on $hostsInGroup array
    local groupHash="${groupHash:-}"
    if [[ "${processing_group[$groupHash]:-0}" == "1" ]]; then
        echo "	Warning: Already processing group $groupHash, skipping."
        return 0
    fi
	local hostFunction="$1"
	local hostValue="$2"
	local serverReboot
	serverReboot=0
	write_cmds=()
#	echo "	Getting hosts in group hash: $groupHash"
	get_hosts_in_group
	if [[ -z "${hostsInGroup[*]}" ]]; then
		echo "	No hosts in this group."
		return 0
	fi
    for host in "${hostsInGroup[@]}"; do
        if [[ "$host" == *"svr"* ]]; then
        	if [[ "$1" =~ ^(blank|reveal|promote)$ ]] ; then
        		# server should not respond to these toggle requests
        		# it will also check when directly activated with these control keys
        		continue
        	fi
        	if [[ "$1" == "reboot" ]]; then
        		serverReboot=1
        	fi
        fi
        write_cmds+=("/UI/HOSTS/$host/control/$hostFunction=$hostValue")
    done
	if [[ "$hostFunction" == "rebootStatus" ]] && [[ "$serverReboot" -eq 1 ]]; then
		# If the server is part of this group (IE daily reboot) the clients need to delay themselves rebooting
		hostValue="SVR"
    fi
	local txn_buffer=""
	for cmd in "${write_cmds[@]}"; do
		local k="${cmd%=*}"
		local v="${cmd#*=}"
		# Validate k and v to prevent etcd transaction injection
		if [[ ! "$k" =~ ^/UI/HOSTS/[^/]+/control/[a-zA-Z0-9_-]+$ ]] || [[ ! "$v" =~ ^[a-zA-Z0-9_-]+$ ]]; then
			echo "	ERR: Invalid characters in etcd transaction key/value, rejecting!"
			return 1
		fi
		txn_buffer+="put \"$k\" \"$v\""$'\n'
	done
	# Execute as a single transaction
	if [[ ${#write_cmds[@]} -gt 0 ]]; then
		local KEYDATA
		KEYDATA="
${txn_buffer}

"
#		echo "	Writing txn Data:"
#		echo "$KEYDATA"
		write_etcd_txn "$KEYDATA" &
		wait
	fi
	unset write_cmds
}

event_group_host_blank() {
	# Blanks all hosts in the group
	local KEYVALUE
	if [[ "$etcdValue" == "1" ]]; then
	  echo "	Blanking all hosts for group $groupHash"
	  KEYVALUE="1"
	else
	  echo "	Un-blanking all hosts for group $groupHash"
	  KEYVALUE="0"
	fi
	process_hostlist "blankStatus" "$KEYVALUE"
}
event_group_host_reboot() {
	# Reboots all hosts in the group
	if [[ "$etcdValue" != "1" ]]; then
		exit 0
	fi
	echo "	Rebooting all hosts for group $groupHash"
	process_hostlist "rebootStatus" "1"
	KEYNAME="$etcdKey"; write_etcd_global &
}
event_group_host_reset() {
	# Resets all hosts in the group
	if [[ "$etcdValue" != "1" ]]; then
		exit 0
	fi
	echo "	Resetting all hosts for group $groupHash"
	process_hostlist "resetStatus" "1"
}
event_group_host_reveal() {
	# Reveals all hosts in the group
	if [[ "$etcdValue" != "1" ]]; then
		exit 0
	fi
	echo "	Revealing all hosts for group $groupHash"
	process_hostlist "revealStatus" "1"
	(
    	# subshell so we don't hang the rest of the process
      	sleep 15
		echo "	Reverting reveal keyvalue after 15s wait"
      	KEYNAME="$etcdKey"; KEYVALUE=0; write_etcd_global &
    ) &
}
event_group_liveStream() {
	# Turns on group livestreaming (how are we going to handle this?)
	if [[ "$etcdValue" != "1" ]]; then
		# disable liveStreaming
		echo "	Disable livestreaming on this group.."
	fi
	echo "	Enable livestreaming on this group.."
}
event_group_input_persist() {
	# This tells wavelet_init to not reset the default to the static image option on system restart
	echo "	Enabling input persistence for this group.."
	# NOOP, by enabling it on the UI it's parsed on boot appropriately by the server/encoders.  Or should be pending testing.
}

# HOST functionality
event_deprovision(){
	# Deprovision functionality
	if [[ $hostNameSys == *"svr"* ]]; then
		echo "	ERR:  Server may not be deprovisioned!"
		exit 0
	fi
	if [[ "$etcdValue" == "1" ]]; then
		echo "	Deprovision flag is set.  System will deprovision itself.."
		echo "	Setting hard deprovision flag to start teardown timer.."
		targetHostName="/UI/HOSTS/$thisHostHash"; read_etcd_global; targetHostName="$printvalue"
		KEYNAME="/HOSTS/$targetHostName/DEPROVISION"; KEYVALUE="1"; write_etcd_global
		security_layer_deprovision
		echo "	Host deprovisioning.."
		shred -u /var/home/wavelet/.ssh/secrets
		shred -u /var/home/wavelet/config
		shutdown -P now
	else
		echo "	Deprovision key is set to 0, doing nothing.."
		exit 0
	fi
}
event_deprovision_timer(){
	if [[ $hostNameSys == *"svr"* ]]; then
		echo "	ERROR: Server may not deprovision!"
		exit 0
	fi
	if [[ "$etcdValue" == "1" ]]; then
		# This starts a timer which will activate wavelet_deprovision_watcher to perform cleanup
		if [[ -z "$thisHostHash" ]]; then
			echo "	ERR: hostHash is null, cannot continue!"
			exit 0
		fi
		echo "	Deprovision flag is set.  System will deprovision itself.."
		echo "	Setting hard deprovision flag to start teardown timer.."
		# Get hostname from the UI/HOSTS/hostHash key
		# As we already know our own hostname, this is another guard to ensure etcd set everything correctly.
		KEYNAME="/UI/HOSTS/$thisHostHash"; read_etcd_global
		targetHostName="$printvalue"
		if [[ -z "$targetHostName" ]]; then
			echo "	ERR: target host name is null, cannot continue!"
			exit 0
		fi
		echo "	Writing deprovision key for $targetHostName"
		KEYNAME="/HOSTS/$targetHostName/DEPROVISION"; KEYVALUE="1"; write_etcd_global
	else
		echo "	Deprovision key is set to 0, doing nothing.."
		exit 0
	fi
}
security_layer_deprovision(){
	echo "		Removing client from IPA Domain.."
	ipa-client-install --uninstall
	echo "		Removing pregenerated configs.."
	rm -rf /var/home/wavelet/config
	echo "		Removal complete.  This host may be redeployed by imaging from scratch via PXE.  It will not be able to reconnect to Wavelet in its current state."
}
# Device redetect functionality
device_redetect(){
	# Populate available devices
	echo "		Calling detectv4l with redetect flag.."
	"$WAVELET_DETECTV4L_MOD" "redetect"
	exit 0
}
# Reboot functionality
event_reboot(){
	if [[ -z "$etcdValue" ]]; then
		exit 0
	fi
    if [[ "$etcdValue" == 1 ]]; then
    	# Normal reboot
	    echo -e "\n     System Reboot \n\n\n\n***SYSTEM IS GOING DOWN FOR REBOOT IMMEDIATELY***\n\n\n"
	    KEYNAME="/HOSTS/$hostNameSys/control/rebootStatus"; KEYVALUE=0; write_etcd_global &
	    KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="UNR: REBOOTING"; write_etcd_global
	    systemctl reboot -i
    elif [[ "$etcdValue" == "SVR" ]]; then
    	# This reboot occurs daily, and therefore clients must wait for the server to come back up before rebooting.
    	if [[ "$hostNameSys" != *"svr"* ]]; then
			KEYNAME="/HOSTS/$hostNameSys/control/rebootStatus"; KEYVALUE=0; write_etcd_global &
			# Error display generates a visual, and also updates the host health key,
			generate_errorDisplay "UNR: REBOOT IN $sleepTimer"
    		sleep $sleepTimer
			systemctl reboot -i
    	else
    		# we are the server and reboot immediately with a 30+ second head start.
			KEYNAME="/HOSTS/$hostNameSys/control/rebootStatus"; KEYVALUE=0; write_etcd_global &
    		systemctl reboot -i
	    fi
	else
		exit 0
    fi
}
# Reset functionality
event_reset(){
	# Reset the appImage service
	echo "		Decoder Reset flag change detected, resetting flag and restarting the UltraGrid service.."
	if [[ "$etcdValue" == 1 ]]; then
		systemctl --user restart UltraGrid.Decoder.service --no-block
		KEYNAME="/HOSTS/$hostNameSys/control/resetStatus"; KEYVALUE="0"; write_etcd_global &
	    KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="WARN: RESTARTING ULTRAGRID"; write_etcd_global &
		echo  "     Task Complete."
		exit 0
	fi
}
updatelocalConfig(){
	# Takes input ARG=$KEYVALUE
	# possible bug - ensure export KEY=VAL is always on a new line! -- may reside in ug_wrapper.sh
	configFile="/var/home/wavelet/config/$hostNameSys.conf"
	if grep -q "export $1=" "$configFile"; then
		# this command needs to replace the entire line
		sed -i "/^export $1=/c\export $1=$KEYVALUE" "$configFile"
	else
		echo "export $1=$KEYVALUE" >> "$configFile"
	fi
}
# Blank functionality
event_blank(){
	# Work out which subfunction to call based off our type and key value.
	echo "	Testing call-in value for blankStatus: $etcdValue"
	if [[ "$hostNameSys" == *"svr"* ]]; then
		exit 0
	fi
	# Get current channelData
	if [[ "$etcdValue" == "0" ]]; then
		event_unblank
		pactl set-sink-unmute "$(pactl get-default-sink)" 1
		KEYNAME="/HOSTS/$hostNameSys/control/blankStatus"; KEYVALUE="0"; write_etcd_global &
		updatelocalConfig "blankStatus"
	else
		echo "	Blank flag change detected (blank), switching host to blank input channel (3).."
		# mute audio for this output as privacy is implied
		pactl set-sink-mute "$(pactl get-default-sink)" 1
		# Now, we switch channel to option 3 which is always the blank screen
		controlPortCmd="capture.data 3"; netCat "6161" "$controlPortCmd"
		KEYNAME="/HOSTS/$hostNameSys/control/blankStatus"; KEYVALUE="1"; write_etcd_global &
		updatelocalConfig "blankStatus"
		# Update local config with the channel data so that we can switch back
		KEYNAME="/HOSTS/$hostNameSys/control/channelData"; read_etcd_global; KEYVALUE="$printvalue"
		updatelocalConfig "channelData"
	fi
}
event_unblank(){
	# Separate function because we need to read channelData to discover our last state.
	if [[ "$hostNameSys" == *"svr"* ]]; then
		exit 0
	fi
	local channelIndex; local channelSourceHash
	echo -e "	Blank flag change detected (unblank), switching host to selected input channel..\n"
    pactl set-sink-mute "$(pactl get-default-sink)" 0
    # Get channel data from persistent key
    if [[ -z "$channelData" ]]; then
    	KEYNAME="/HOSTS/$hostNameSys/control/channelData"; read_etcd_global
    	channelData="$printvalue"
    	if [[ -z "$channelData" ]]; then
	    	echo "	Warning: No channelData value found, defaulting to channel 1"
	    	channelData="1-1"
	    fi
	    KEYVALUE="$channelData"
	    updatelocalConfig "channelData"
	fi
    channelIndex="${channelData%%-*}"
    channelSourceHash="${channelData##*-}"
    echo "	Previous video source is on channel: $channelIndex with source hash: $channelSourceHash"
	controlPortCmd="capture.data $channelIndex"; netCat "6161" "$controlPortCmd"
}
event_relabel(){
	# Relabel Functionality
	if [[ "$hostNameSys" != *"svr"* ]]; then
		echo "      Relabeling this host.."
		hostnamectl --pretty hostname "$etcdValue"
	else
		echo "		Server cannot be relabeled."
	fi
}
event_reveal(){
	# shows a test card on the host(s) in question for 15 seconds, then reverts to previous channel
	if [[ "$hostNameSys" == *"svr"* ]] || [[ "$etcdValue" == "0" ]] || [[ -z "$etcdValue" ]]; then
		exit 0
	fi
   	local channelIndex; local channelSourceHash
   	echo "	Showing testcard on this client for 15 seconds.."
    # Get channel data from persistent key
    if [[ -z "$channelData" ]]; then
    	KEYNAME="/HOSTS/$hostNameSys/control/channelData"; read_etcd_global
    	channelData="$printvalue"
    	if [[ -z "$channelData" ]]; then
	    	echo "	Warning: No channelData value found, defaulting to channel 1"
	    	channelData="1-1"
	    fi
	    KEYVALUE="$channelData"
	    updatelocalConfig "channelData"
	fi
    channelIndex="${channelData%%-*}"
    channelSourceHash="${channelData##*-}"
   	controlPortCmd="capture.data 2"; netCat "6161" "$controlPortCmd"
   	(
   		# subshell so we don't hang the rest of the process
   		sleep 15
   		KEYNAME="/HOSTS/$thisHostHash/control/revealStatus"; KEYVALUE=0; write_etcd_global &
    	echo "	Previous video source is on channel: $channelIndex with source hash: $channelSourceHash"
		controlPortCmd="capture.data $channelIndex"; netCat "6161" "$controlPortCmd"
	) &
}
event_prefix_set(){
	# Switches the type designator under /hostLabel/$(hostname)/control/type
	# This is now checking and modifying the local host's /type key from what was set in the UI.
		if [[ "$hostType" = "dec" ]]; then
			echo "      I am currently a decoder, switching to an encoder"
			KEYNAME="/HOSTS/$hostNameSys/control/type"; KEYVALUE="enc"; write_etcd_global
			# Launch detectV4l so that we generate a list of attached devices
			"$WAVELET_DETECTV4L_MOD" "redetect"
			# terminate existing UG decoder tasks
			systemctl --user disable \
				UltraGrid.Decoder.service --now
			# Generate reflector service
			local targetFile
			if [[ -f "/var/wavelet_ramfs/wavelet_reflector.sh" ]]; then
				targetFile="/var/wavelet_ramfs/wavelet_reflector.sh"
			else
				targetFile="/usr/local/bin/wavelet_reflector.sh"
			fi
			# Note the wrapper files do not reside on the ramdisk
			cat > /var/home/wavelet/.config/systemd/user/wavelet_reflector.service <<-EOF
				[Unit]
				Description=Wavelet wavelet_reflector
				After=network-online.target
				Wants=network-online.target

				[Service]
				Type=simple
				ExecStart=/var/lib/wavelet/bin/wavelet/wavelet_client_controller_wrapper.sh 'wavelet' '/HOSTS/%H/DECODER_SUB_LIST' "$targetFile"
				Restart=always
				RestartSec=10s
				# Security hardening
				NoNewPrivileges=true
				PrivateTmp=true
				ProtectSystem=strict
				# ProtectHome=true
				RuntimeDirectory=wavelet_reflector
				RuntimeDirectoryMode=0700
				# Memory protection
				MemoryDenyWriteExecute=true
				SystemCallArchitectures=native

				[Install]
				WantedBy=default.target
				EOF
			systemctl --user daemon-reload
			# Update config file with new data
			configKey="HOST_TYPE"
            if grep -q "^export $configKey=" "$configFile"; then
            	sed -i "s/^export $configKey=.*/export $configKey=\"enc\"/" "$configFile"
            else
            	echo "export $configKey=\"enc\"" >> "$configFile"
            fi
			# launch encoder process and ensure we have the proper blank image available
			notifyID="$(notify-send -h string:x-mako-align:center "Currently Running Encoder Process")"
			echo "$notifyID" > /var/home/wavelet/config/notifyID
			event_encoder
		else
			echo "      I am not a decoder, switching to become a decoder.."
			# Update config file with new data
			configKey="HOST_TYPE"
            if grep -q "^export $configKey=" "$configFile"; then
            	sed -i "s/^export $configKey=.*/export $configKey=\"dec\"/" "$configFile"
            else
            	echo "export $configKey=\"dec\"" >> "$configFile"
            fi
			KEYNAME="/HOSTS/$hostNameSys/control/type"; KEYVALUE="dec"; write_etcd_global
			remove_associated_inputs
			# Terminate encoder processes
			systemctl --user disable \
				UltraGrid.Encoder.service \
				wavelet_reflector.service \
				UltraGrid.Reflector.service --now
			notifyID="$(cat /var/home/wavelet/config/notifyID)"
			notify-send -r="$notifyID" -e "Encoder task stopped"
			# Call decoder
			run_decoder
		fi
}
remove_associated_inputs(){
	echo "      Removing input devices associated with my hostname.."
	# Since we are running on the affected host here, all we need do is look at an array output of /hostname/inputs/devpath_lookup
	KEYNAME="/HOSTS/$hostNameSys/inputs/devpath_lookup"; read_etcd_prefix_global; devPath=("$printvalue")
	for i in "${devPath[@]}"; do
		echo "      Calling d4vl to remove $i"
		# Detectv4l will now handle graceful removal of all device keys from the videopath of the device I.E /dev/video0 parsed as _dev_video0
		"$WAVELET_DETECTV4L_MOD" "delete" "${i//_\//}"; sleep 2
	done
	KEYNAME="/HOSTS/$hostNameSys/INPUT_DEVICE_PRESENT"; delete_etcd_key_global &
}
set_newHostName(){
	myNewHostname="$1"
	if hostnamectl hostname --pretty "$myNewHostname"; then
		echo -e "\n     Host Name set as $myNewHostname successfully!, writing relabel_active to 0."
		KEYNAME="/HOSTS/$hostNameSys/relabel_active"; KEYVALUE="0";	write_etcd_global &
		KEYNAME="/HOSTS/$hostNameSys/RECENT_RELABEL"; KEYVALUE="1"; write_etcd_global &
		echo "      Done, no further actions needed."
	else
		echo "     Hostname change command failed, please check logs"
	fi
}
# Promotion functionality
event_promote(){
	echo "      Host type is: $hostType"
	case "$hostType" in
		enc*)
			echo -e "	I am an Encoder \n"; event_prefix_set; "$WAVELET_SCREENCAST_MOD" "capable"
			;;
		dec*)
			echo -e "	I am a Decoder \n"; event_prefix_set;
			;;
		svr*)
			echo -e "	I am a Server, ending process \n"; exit 0
			;;
		*)
			echo -e "	This device is other, ending process\n"; exit 0
			;;
	esac
}
toggle_userInterface() {
	# Enables the UI and switches UltraGrid from fullscreen mode to windowed mode.
	# perform workspace config.  In non-UI mode, UG's args will be :fs for fullscreen.
	# Legacy settings from config file
	# for_window [app_id="uv"] floating enable, fullscreen enable
	# for_window [class="uv"] floating enable, fullscreen enable
	get_swaySocket
	echo "	Checking for running UltraGrid container.."
	local width; local height; local displayResolution; local noDecoderWindow; local workspace
	noDecoderWindow=false
	if [[ "$etcdValue" == 0 ]] || [[ -z "$etcdValue" ]]; then
		echo "	Disabling UI functionality on this device.."
		notify-send -e "UI Disabled"
		rm -rf "/var/home/wavelet/config/webui.enabled"
		uiDisable_moveUGWindow
		swaymsg -s "$swaySocket" "[app_id="org.mozilla.firefox"] kill" 2>/dev/null
		# We always revert to workspace 1 if disabling UI.
		# On the server, this will be the log window, on a client, the UG output window.
		swaymsg -s "$swaySocket" "workspace 1"
		# Send more insistent termination signal to firefox if still running (hung etc.)
		# pkill firefox
	else
		echo "	Enabling Web interface on this host.  Recommend kb/mouse as Human Interface Device!"
		notify-send -e "UI Enabled"
		# Determine workspace for enabling UI
		if [[ "$hostNameSys" == *"svr"* ]]; then
			elapsedBootTime="$(uptime | awk '{print $3}')"
			if [[ $elapsedBootTime -lt 3 ]]; then
				workspace=2
			else
				workspace=3
			fi
		else
			workspace=3
		fi
		uiEnable_moveUGWindow
		echo "$workspace" > "/var/home/wavelet/config/webui.enabled"
		swaymsg -s "$swaySocket" "workspace $workspace"
		echo "	Launching web browser with args:  /usr/bin/firefox $SVR_HOSTNAME"
		swaymsg -s "$swaySocket" exec "/usr/bin/firefox $SVR_HOSTNAME"
	fi
}
toggle_screencast(){
	# Screencasting has been enabled for this client.  Implies already encoder.
	# The button shouldn't appear on hosts without a capable WiFi card (control/screenCastCapable)
	if [[ -f "/var/home/wavelet/config/screenCastActive" ]]; then
    	echo "		ScreenCast already active, disabling service."
    	# disable the quadlet
    	# remove input data from host to depopulate the input option on UI
    	# remove all screencast keys from the host entry.
		/usr/local/bin/wavelet_screencast.sh down "$screenCastDevice"
    	rm -rf "$HOME/.config/containers/systemd/screencast.container"
    	# screencast must have been enabled at least once for this to work.
		KEYDATA="mod(\"$BASEKEYNAME/control/enableScreencast\") > \"0\"

del \"$BASEKEYNAME/control/authorizeScreencast\"
del \"$BASEKEYNAME/control/screencastActive\"
del \"$BASEKEYNAME/control/screencastRequest\"

"
		write_etcd_txn "$KEYDATA" &
		rm -rf "/var/home/wavelet/config/screenCastActive"
		rm -rf "/var/home/wavelet/config/screencast/device.connected"
    	exit 0
	else
		local screenCastDevice
		BASEKEYNAME="/HOSTS/$hostNameSys"
		if [[ "$hostType" != "enc" ]]; then
			echo "	Enabling screenCast for this encoder"
			KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="ERR: Not encoder"; write_etcd_global &
			exit 0
			# If not encoder -> exit ERR (log to frontend client control)
		fi
		KEYNAME="/HOSTS/$hostNameSys/control/screenCastCapable"; read_etcd_global; screenCastDevice="$printvalue"
		if [[ -z "$screenCastDevice" ]]; then
			message="	ERR: No device name available!"
			echo "$message"; KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="$message"; write_etcd_global &
			exit 0
		fi
		if ! /usr/local/bin/wavelet_screencast.sh up "$screenCastDevice"; then
			KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"
			KEYVALUE="ERR: Screencast bring-up failed on $screenCastDevice"
			write_etcd_global &
			exit 0
		fi
		touch "/var/home/wavelet/config/screenCastActive"
		# Block until a peer arrives (sinkctl wrapper writes this).
		until [[ -f "/var/home/wavelet/config/screencast/device.connected" ]]; do
			sleep 0.1
		done
		# TODO change this to the local machine $HOME/config/$hostname.conf file.
		peerInfo="$(< /var/home/wavelet/config/screencast/device.connected)"
		KEYNAME="/HOSTS/$hostNameSys/control/screencastRequest"; KEYVALUE="$peerInfo"; write_etcd_global &
		rm -f /var/home/wavelet/config/screencast/device.connected
		# authorize_screencast() is invoked later by the /control/authScreencast key path.
		# Listen for connections, when connection detected a local flag is written
		until [[ -f "/var/home/wavelet/config/screencast/device.connected" ]]; do
			sleep .1
		done
		KEYNAME="/HOSTS/$hostNameSys/control/screencastRequest"; KEYVALUE="screenCastDevice"; write_etcd_global &
		rm -rf "/var/home/wavelet/config/screencast/device.connected"
		# Now nothing happens until we get the authorized flag back from the frontend.
	fi
}

authorize_screencast(){
	# Step 2 of screencasting.   Called from /control/screencastApproved
	echo "	Pending screencast is authorized! Setting up screencast sink and enabling as UG source!"
	# Here we would in broad strokes
	# perform the most efficient command line tasks to inject the streaming source to UltraGrid as an additional switcher option
	# Write the appropriate key in our inputs to populate this additional input under this host's encoder options
}

# Video source functionality
event_group_set_video_source() {
	# Server-only
	# Triggered by activity in /UI/GROUPS/$groupHash/control/sourceHash
	# Our first task is to get a list of hosts within the group
	echo "	Working on group video source event.."
	local KEYNAME; local KEYVALUE; local groupHash; local hostSourceData; local hostSourceKey
	groupHash="${etcdKey#/UI/GROUPS/}"
	groupHash="${groupHash%%/*}"
	get_hosts_in_group
	echo "	Hosts in group (hash value):"
	for h in "${hostsInGroup[@]}"; do
		echo "		$h"
	done
	if [[ "$etcdValue" =~ ^(0|1|2|3)$ ]]; then
	    KEYNAME="/UI/GROUPS/$groupHash/control/previousVideoSourceKey"; KEYVALUE="$etcdValue--$etcdValue"; write_etcd_global &
		unset decoderSubscribecmd
		cmd="del"
		event_process_group_videoSource_hosts
	else
		echo "	Not static input, setting source hash and stream data for hosts in group.."
    	cmd="put"
    	# Capture the output of event_get_subscribeStreamCommand into local variables
    	mapfile -t cmdOutput < <(event_get_subscribeStreamCommand)
    	local directMode="${cmdOutput[0]}"
    	local decoderSubType="${cmdOutput[1]}"
    	local decoderSubscribecmd="${cmdOutput[2]}"
    	if [[ -n "$decoderSubscribecmd" ]]; then
    		echo "	Populated base64 commandline: $decoderSubscribecmd, for subType $decoderSubType, with mode: $directMode"
    	else
    		echo "	No special decoder commands required.  UltraGrid local source."
    	fi
    	event_process_group_videoSource_hosts
	fi
}

event_get_subscribeStreamCommand(){
   	# Server only
   	# This returns the correct subscribe stream command for the input device that's been selected --
   	# If that device is a network device which requires specific inputs
   	# Outputs: decoderSubType decoderSubscribecmd
   	local KEYNAME; local KEYVALUE; local printvalue; local deviceHostName; local hostIP
	if [[ -n "${_inputDeviceMap[$etcdValue]:-}" ]]; then
		hostSourceKey="${_inputDeviceMap[$etcdValue]}"
	else
		return 1
	fi
	KEYNAME="$hostSourceKey"; read_etcd_global; hostSourceData="$printvalue"
#	hostUIKey="${hostSourceKey%/inputs/*}"
	# Generate the device fields hostSourceData - note ordering
	hostIP="${hostSourceData%;*}"
	deviceHostName="${hostIP#*;}"
	hostIP="${hostIP%%;*}"
	deviceHostName="${deviceHostName%%;*}.$(dnsdomainname)"
	if [[ "$hostSourceData" == *"NDI"* ]] || [[ "$hostSourceData" == *"RTSP"* ]]; then
		# Check directMode in the HOSTS prefix (not UI)
		KEYNAME="/HOSTS/$deviceHostName/control/directMode"; read_etcd_global
		local directMode="$printvalue"
		if [[ "$directMode" == "1" ]]; then
			# Verify the device still has the subscription command available
			KEYNAME="/HOSTS/$deviceHostName/uv_stream_cmd/subscribeStream"; read_etcd_global
			if [[ -n "$printvalue" ]]; then
				KEYNAME="/HOSTS/$deviceHostName/subType"; read_etcd_global
				local decoderSubType="$printvalue"
				if [[ "$decoderSubType" == "NDI" ]] || [[ "$decoderSubType" == "RTSP" ]]; then
					KEYNAME="/HOSTS/$deviceHostName/uv_stream_cmd/subscribeStream"
					read_etcd_global
					local decoderSubscribecmd="$printvalue"
					echo "$directMode"
					echo "$decoderSubType"
					echo "$decoderSubscribecmd"
				else
					echo ""
					echo ""
				fi
			else
				echo ""
				echo ""
			fi
		else
			# We provide the stream command for an encoder to use
			KEYNAME="/HOSTS/$deviceHostName/uv_encode_cmd/inputStream"; read_etcd_global
			echo "0"
			echo "UG"
			echo "$printvalue"
		fi
	else
		echo ""
		echo ""
	fi
}

event_process_group_videoSource_hosts(){
	# Server only
    if [[ -z "$cmd" ]]; then
        exit 0
    fi
    local tempTxn; tempTxn=$(mktemp)
    for hostHash in "${hostsInGroup[@]}"; do
        (
            local deviceHostName="${_hostNameMap[$hostHash]:-}"; local configPayload
#            local versionKey; versionKey="/HOSTS/$deviceHostName/control/sourceCheckVersion"
#            KEYNAME="$versionKey"; read_etcd_global
            local currentVersion; currentVersion="0"
            if [[ "$directMode" -eq 1 ]]; then
                # Direct NDI mode: keep cmd, set streamMode to subType
                configPayload="type:network|active:1|subType:$decoderSubType|cmd:$decoderSubscribecmd"
				cat >> "$tempTxn" <<-EOF
					put "/HOSTS/$deviceHostName/control/videoSourceConfig" "$configPayload"
				EOF
            elif [[ -z "$decoderSubscribecmd" ]]; then
                # No direct subscription: set explicit inactive state
                # Note the video source subtype being "static" doesn't mean a the static image option.
                configPayload="type:static|active:0|subType:static|cmd:"
                cat >> "$tempTxn" <<-EOF
					put "/HOSTS/$deviceHostName/control/videoSourceConfig" "$configPayload"
				EOF
            else
                # We are feeding a network video source through UltraGrid
                configPayload="type:ug|active:1|subType:ug|cmd:"
            	cat >> "$tempTxn" <<-EOF
            		put "/HOSTS/$deviceHostName/control/videoSourceConfig" "$configPayload"
				EOF
            fi
            # Increment version counter to trigger client re-evaluation
			# local newVersion=$((currentVersion + 1))
			#put "$versionKey" "$newVersion"
			cat >> "$tempTxn" <<-EOF
				put "/UI/HOSTS/$hostHash/control/videoSource" "$etcdValue"
			EOF
        ) &
    done
    wait
    txnArray="$(< "$tempTxn")"
    rm -rf "$tempTxn"
    # /UI/HOSTS will always have been modified more than once, at this point.
    KEYDATA="
$txnArray

"
    echo -e "Txn Data:\n$KEYDATA"
    write_etcd_txn &
    stop_timer
}

event_group_set_staticImage(){
	# Run on the server only!
	# Generates a static image file for the affected group, and applies an available URL to the key value
	# Hosts will download the generated file directly.
	local staticImageFile;
	if [[ "$etcdValue" == *"://"* ]]; then
	  # this is a URL and this task has already run
	  # If an actual update, this will just be a filename
	  exit 0
	fi
	echo "		$etcdValue is not a URL, updating static image for this group.."
	staticImageFile="/var/home/wavelet/http-php/html/images/staticImage_$groupHash.mp4"
	if [[ ! -f "$staticImageFile" ]]; then
		echo "		ERROR: Image file $staticImageFile does not exist"
		exit 0
	fi
	clamscan "$staticImageFile" || {
		echo "		CRITICAL: Malicious payload detected in image file: $staticImageFile"
		rm -rf "$staticImageFile"
		exit 0
	}
	ffmpeg \
		-fflags +genpts -loop 1 -i "$staticImageFile" \
		-t 30 -c:v mjpeg -q:v 0 "/var/home/wavelet/http-php/html/images/staticImage_$groupHash.mp4" 2>/dev/null
	cat > "staticImage_$groupHash.sha256" <<- EOF
$(sha256sum < "/var/home/wavelet/http-php/html/images/staticImage_$groupHash.mp4")
EOF
	KEYVALUE="https://$hostNameSys/images/staticImage_$groupHash.mp4"
	KEYNAME="/UI/GROUPS/$groupHash/control/staticImage"; write_etcd_global # This will call this function again, but now it'll be a URL.
	get_hosts_in_group
	for groupHostHash in "${hostsInGroup[@]}"; do
		(
			KEYNAME="/UI/HOSTS/$groupHostHash/control/updateImage"
			KEYVALUE="1"
			write_etcd_global
		) &
	done
	wait
	rm -rf "$staticImageFile"
}

event_group_set_codec(){
	# Changes the active codec for any UltraGrid clients in the group.
	# Non-UG clients will not be affected, and have their own vendor-specific codec controls.
	# For this we should get the full keyvalue back for the codec which was selected in the dropdown, fairly direct.
	# We should verify we have an active encoder task running and that we own the active input first.
	# if no, exit 0
	# Example input: "ffv1")           	KEYVALUE="$codeCmd;FFMPEG FFV1.  High bandwidth, high quality, lossless";;
	#	strip anything after the semicolon delimiter, this is our codec command
	codecCmd="${etcdValue%%;*}"
	controlPortCmd="compress $codecCmd"; netCat "6162" "$controlPortCmd"
	# here we'd check for video output and if something went wrong, we should restart our encoder process to self-heal.
}
event_set_directMode(){
	# This sets the direct mode for the network host in question.  Server handles this.
	KEYNAME="${etcdKey%%/control/directMode*}"; read_etcd_global
	KEYNAME="/HOSTS/$printvalue/control/directMode"; KEYVALUE="$etcdValue"; write_etcd_global &
}

# Group membership
event_create_group(){
	if [[ "$etcdValue" != "PLEASE" ]]; then
		#..how rude!
		KEYVALUE="$etcdKey"; delete_etcd_key_global &
		exit 0
	fi
	# Generate a new group hash
	# Check that this hash doesn't already exist (REALLY small chance of a collision but.. why not)
	local newGroupHash; newGroupHash="$(sha256sum < /proc/sys/kernel/random/uuid | tr -d ' -')"
	if [[ -z "$newGroupHash" ]]; then
		echo "	ERR:  Failure generating a group hash value!"
		exit 0
	fi
	# Declare vars locally
	local KEYNAME
	local KEYVALUE
	local KEYDATA
	local BASEKEYNAME
	BASEKEYNAME="/UI/GROUPS/$newGroupHash"
	# Pick a random swatch color from a palette that fits the dark teal UI theme
	local swatchColors=( "#1d5161" "#08507c" "#113b53" "#133446" "#143b51" "#4cede1" "#0f2b39" "#0a3d5c" "#1a6b8a" "#0d4f6e" )
	local newSwatch; newSwatch="${swatchColors[$((RANDOM % ${#swatchColors[@]}))]}"
	# Create a txn which will complete only if the generated hash doesn't exist
	KEYDATA="mod(\"$BASEKEYNAME\") = \"0\"

put \"$BASEKEYNAME/control/newGroup\" \"1\"
put \"$BASEKEYNAME\" \"New Group\"
put \"$BASEKEYNAME/control/label\" \"New Group\"
put \"$BASEKEYNAME/control/audioStatus\" \"0\"
put \"$BASEKEYNAME/control/bannerStatus\" \"0\"
put \"$BASEKEYNAME/control/blankStatus\" \"0\"
put \"$BASEKEYNAME/control/chainedToGroup\" \"\"
put \"$BASEKEYNAME/control/liveStreamStatus\" \"0\"
put \"$BASEKEYNAME/control/persistStatus\" \"0\"
put \"$BASEKEYNAME/control/PRIMARY\" \"0\"
put \"$BASEKEYNAME/control/rebootStatus\" \"0\"
put \"$BASEKEYNAME/control/resetStatus\" \"0\"
put \"$BASEKEYNAME/control/revealStatus\" \"0\"
put \"$BASEKEYNAME/control/sourceHash\" \"1\"
put \"$BASEKEYNAME/control/sourceHashStatus\" \"1\"
put \"$BASEKEYNAME/control/encoderTimeout\" \"5\"
put \"$BASEKEYNAME/control/swatchValue\" \"$newSwatch\"
del \"/UI/GLOBALS/control/GROUP-CREATE\"

"
	write_etcd_txn "$KEYDATA"
}

event_change_group(){
	# Runs on host
	KEYNAME=""; KEYVALUE=""
   	if [[ "$hostNameSys" == *"svr"* ]]; then
   		echo "		The server may not change groups from the primary group."
   		exit 0
	fi
   	if [[ "$etcdValue" == "$groupHash" ]]; then
   		echo "      Group value was updated to the same value as current group membership, doing nothing."
   		exit 0
   	fi
   	if [[ -z "$etcdValue" ]]; then
   		# Restore the host to the primary group because something went wrong, we should get a valid groupHash here.
   		echo "		No groupHash populated, resetting to server group.."
		KEYNAME="/GROUPS/$serverHostname"; read_etcd_global; etcdValue="$printvalue"
   		# Write the group key back and let the server orchestrator update the UI.
   	fi
	echo "	Changing client group to hash: $etcdValue"
	# Will also trigger a conf update, but since the checksum should match, no issue
	# If it doesn't, server conf will overwrite host conf.
	KEYNAME="/HOSTS/$hostNameSys/control/GROUP"; KEYVALUE="$etcdValue"; write_etcd_global &
	configKey="GROUP_HASH"
	# Validate etcdValue to prevent sed injection (reject / and newlines)
	if [[ "$etcdValue" == *"/"* ]] || [[ "$etcdValue" == *$'\n'* ]] || [[ "$etcdValue" == *$'\r'* ]]; then
		echo "	ERR: Invalid characters in group hash, rejecting!"
		exit 0
	fi
	if grep -q "^export $configKey=" "$configFile"; then
		sed -i "s/^export $configKey=.*/export $configKey=\"$etcdValue\"/" "$configFile"
	else
		echo "export $configKey=\"$etcdValue\"" >> "$configFile"
	fi
}

#delete a group
event_delete_group(){
	# Server only
	echo "      Finding components in specified group.."
	# Validate etcdValue is not empty and matches hash format
	if [[ -z "$etcdValue" ]]; then
		echo "      Cannot delete group: etcdValue is empty!"
		exit 0
	fi
	if [[ ! "$etcdValue" =~ ^[a-f0-9]{64}$ ]]; then
		echo "      Cannot delete group: etcdValue '$etcdValue' is not a valid hash format!"
		exit 0
	fi
	# We also need the hash of the primary group
	if [[ -z "$primaryGroupHash" ]]; then
		# We are now in an error state because primaryGroupHash wasn't in the loaded client conf file!
		echo "	ERR: Primary group hash not populated in client conf!  Retrieving from etcd.."
		KEYNAME="/GROUPS/$hostNameSys"; read_etcd_global; primaryGroupHash="$printvalue"
	fi
	# As this is always run on the server, and the server is always in the primary group:
	if [[ "$etcdValue" == "$primaryGroupHash" ]]; then
		echo "      Cannot delete the primary group!!"
		exit 0
	fi
	# TODO - dead code, we don't need this read here.
#	KEYNAME="/UI/GROUPS/$primaryGroupHash"; read_etcd_prefix_list; primaryGroupKeys="$printvalue"
	KEYNAME="/UI/HOSTS/"; read_etcd_prefix_keys
	hostsGroupMemberArray=()
	while read -r line; do
		if [[ "$line" == *"GROUP"* ]]; then
			hostsGroupMemberArray+=("$line")
		fi
	done <<<"$printvalue"
	for hostKey in "${hostsGroupMemberArray[@]}"; do
		KEYNAME="$hostKey"; read_etcd_global
		if [[ "$etcdValue" == "$printvalue" ]]; then
			echo "		Moving host $hostKey to primary group.."
			KEYNAME="$hostKey"; KEYVALUE="$primaryGroupHash"; write_etcd_global &
			declare -g -A GROUP_KEYS
			get_group_keys "$primaryGroupHash"
			for key in "${!GROUP_KEYS[@]}"; do
				case $key in
					blankStatus)
						etcdValue="${GROUP_KEYS[$key]}"; event_blank
						;;
					revealStatus)
						etcdValue="${GROUP_KEYS[$key]}"; event_reveal
						;;
					sourceHash)
						echo "		SourceHash changed: ${GROUP_KEYS[$key]} (triggers wavelet_run)"
						etcdValue="${GROUP_KEYS[$key]}"
						# Don't exit early - continue processing other controls first
						;;
					*)
						continue
						;;
				esac
			done
#			KEYNAME="/HOSTS/$hostNameSys/control/sourceCheckVersion"; KEYVALUE="$(date +%s)"; write_etcd_global &
			KEYNAME="/HOSTS/$hostNameSys/control/GROUP"; KEYVALUE="$etcdValue"; write_etcd_global &
			wavelet_run
		fi
	done
	# delete the group prefix (this includes everything inside the group)
	KEYNAME="/UI/GROUPS/$etcdValue"; delete_etcd_key_prefix_global &
	KEYNAME="/UI/GLOBALS/control/GROUP-DELETE"; delete_etcd_key_global &
	echo "		Group deleted!"
	# SSE should pick up the changes
}

get_ipValue(){
	# Gets the current IPv4 address for this host from active ethernet/wifi connections
	# Prioritizes wired connections, falls back to wifi if no wired connection active
	local ipValue; local connectionName; local connType; local uuid
	local ipValue_wired=""; local ipValue_wireless=""
	# First try to get IP from active wired (ethernet) connection
	while read -r uuid; do
		connType=$(nmcli -g connection.type con show "$uuid")
		if [[ "$connType" == "802-3-ethernet" ]]; then
			connectionName=$(nmcli -g connection.id con show "$uuid")
			# Todo try to replace with bash param expansion
			ipValue=$(nmcli -g IP4.ADDRESS con show "$uuid" | head -n1 | cut -d'/' -f1)
			if [[ -n "$ipValue" && "$ipValue" != "--" ]]; then
				echo -e "	Found active wired connection \"$connectionName\" with IP: $ipValue"
				break
			fi
		fi
	done < <(nmcli -g UUID con show --active)
	# If no wired connection with IP found, try wifi
	if [[ -z "$ipValue" || "$ipValue" == "--" ]]; then
		while read -r uuid; do
			connType=$(nmcli -g connection.type con show "$uuid")
			if [[ "$connType" == "802-11-wireless" ]]; then
				connectionName=$(nmcli -g connection.id con show "$uuid")
				# Todo try to replace with bash param expansion
				ipValue=$(nmcli -g IP4.ADDRESS con show "$uuid" | head -n1 | cut -d'/' -f1)
				if [[ -n "$ipValue" && "$ipValue" != "--" ]]; then
					echo -e "	Found active wireless connection \"$connectionName\" with IP: $ipValue"
					break
				fi
			fi
		done < <(nmcli -g UUID con show --active)
	fi
	# Null value guard
	if [[ -z "$ipValue" || "$ipValue" == "--" ]]; then
		echo -e "	No valid IP address found, using alternative approach.....\n"
		# Todo try to replace with bash param expansion
		ipValue="$(ip -4 route get 1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -n1)"
		return
	fi
	# Validate
	if valid_ipv4 "$ipValue"; then
		echo "	IP Address is valid: $ipValue, continuing.."
		# Update config file with new data
		configKey="HOST_IP"
        if grep -q "^export $configKey=" "$configFile"; then
           	sed -i "s/^export $configKey=.*/export $configKey=\"$ipValue\"/" "$configFile"
		else
			echo "export $configKey=\"$ipValue\"" >> "$configFile"
		fi
		KEYNAME="/HOSTS/$hostNameSys/control/IP"; KEYVALUE="$ipValue"; write_etcd_global &
	else
		echo -e "	IP Address '$ipValue' is not valid, retrying...\n"
		sleep .25
		get_ipValue
	fi
}

# Replaces wavelet_run.sh
wavelet_run(){
	# Detect_self in this case relies on the etcd type key
	case "$hostType" in
		enc*)
			event_encoder
			;;
		decX.*)
			echo -e "	    ERR: DECODER HOSTNAME NOT SET.\n	Terminating process.\n"
			exit 0
			;;
		dec*)
			run_decoder
			;;
		svr*)
			run_server
			;;
		*)
			echo -e "	    This device Hostname is not set appropriately, exiting\n"
			exit 0
			;;
	esac
}

run_server(){
	# Check for input devices
	if [[ "$inputDevicePresent" -eq 1 ]]; then
		echo "	An input device is present on this server, proceeding"
		# Is this input on this host?
		if [[ -z "$serverHostHash" ]]; then
			serverHostHash="$CLIENT_HOST_HASH"
		fi
		KEYNAME="/UI/HOSTS/$serverHostHash/inputs/"; read_etcd_prefix_keys
		if [[ "$etcdValue" == 0 ]] || [[ "$etcdValue" == 1 ]] || [[ "$etcdValue" == 2 ]]; then
			# The requested input device is a static.  Taking no further action
			exit 0
		else
            if [[ "$printvalue" != *"$etcdValue"* ]]; then
                echo "	The requested input device is not present on this server.  Checking for indirect NET devices.."
                check_ndiDirectMode
            else
                echo "	The requested input device: $etcdValue is not a static selection, and is present on this server, running encoder."
                event_encoder
            fi
        fi
	else
		echo "		No detectable input devices are present on this server."
		echo "		The server will handle only primary group streaming and system coordination tasks."
	fi
}

check_ndiDirectMode() {
	# Interrogate the selected device hash to see if its parent host is in directMode.  If so, clients subscribe directly.
	if [[ -z "${_inputDeviceMap[$etcdValue]:-}" ]]; then
		echo "	Input device $etcdValue not found in cache."
		exit 0
	fi
	local hostKey="${_inputDeviceMap[$etcdValue]}"
	KEYNAME="$hostKey"; read_etcd_global; hostSourceData="$printvalue"
	if [[ "$hostSourceData" != *"NDI"* ]] && [[ "$hostSourceData" != *"RTSP"* ]]; then
		echo "	Input device $etcdValue is not a network device (type: $hostSourceData). Skipping."
		exit 0
	fi
	local hostHash="${hostKey#/UI/HOSTS/}"
	hostHash="${hostHash%%/*}"
	local targetHostName="${_hostNameMap[$hostHash]:-}"
	if [[ -z "$targetHostName" ]]; then
		echo "	Hostname not found for host hash $hostHash."
		exit 0
	fi
	KEYNAME="/HOSTS/$targetHostName/control/directMode"; read_etcd_global
	echo "directMode for device is $printvalue"
	if [[ "$printvalue" == 1 ]]; then
		# The NDI device is in direct mode and clients subscribe directly.
		exit 0
	else
		# We regenerate our encoder process and handle this as an UltraGrid input
		KEYNAME="/HOSTS/$targetHostName/uv_encode_cmd/inputStream"; read_etcd_global
		echo "		NDI Device set to indirect mode!  Adding UltraGrid encoder argument (base64): $printvalue"
		event_encoder "$printvalue"
	fi
}

event_encoder(){
	# An encoder runs:
	# A video compression systemd unit
	# A reflector + reflector reload systemd unit
	# An encoder CAN display the stream it generates, at some performance cost of running an additional display process
	# The blank/unblank button controls that function in this context.
	# We may want to ensure the group mass blank/unblank controls do NOT affect encoders!
    if [[ "$(systemctl --user is-active wavelet_reflector.service 2>/dev/null)" != "active" ]]; then
        systemctl --user enable wavelet_reflector.service --now
    fi
	echo -e "	Calling wavelet_encoder module with args:\n		$etcdValue\n	$thisHostHash\n			$1\n"
	"$WAVELET_ENCODER_MOD" "inputHash=$etcdValue" "groupHash=$groupHash" "netDevIngest=$1" &
}

check_reflector_subscription(){
	# Reflector subscription logic
	KEYNAME="/HOSTS/$hostNameSys/control/previousVideoSourceKey"; read_etcd_global; previousVideoSourceValue="$printvalue"
	KEYNAME="/UI/GROUPS/$groupHash/control/currentVideoSourceKey"; read_etcd_global; currentVideoSourceHash="${printvalue%%-*}"
	if [[ "$streamMode" == "ug" ]]; then
		echo "	Moving to an UltraGrid source, sending reflector subscription request"
		KEYNAME="/HOSTS/$hostNameSys/reflectorRequest"; KEYVALUE="$etcdValue"; write_etcd_global &
	else
		echo "	UltraGrid source, sending a reflector unsubscribe request"
		KEYNAME="/HOSTS/$hostNameSys/control/unsubRequest"; KEYVALUE="$previousVideoSourceValue"; write_etcd_global &
		return 0
	fi
	get_ipValue

	if [[ -z "$currentVideoSourceHash" ]]; then
		# This is technically an error state.
		# Assume everything is brand new, no reflector and static image by default.
		previousVideoSourceValue=1
	fi
	# We should have a source hash for our previous input
	if [[ "$previousVideoSourceValue" =~ ^[0-3]$ ]] || [[ "$etcdValue" == "$previousVideoSourceValue" ]]; then
		echo "	Moving from static video source or previous source is the same as current source."
	else
		# Is the previous source value an UltraGrid reflector?
		KEYNAME="/HOSTS/$hostNameSys/control/previousVideoSourceType"; read_etcd_global
		echo "	Previous video source type: $printvalue"
		if [[ "$printvalue" == "ug" ]]; then
			echo "	Previous video source is an UltraGrid source, checking reflector data"
			# Is it the SAME reflector?
			# need the host reflector for previous video source and current video source both!
			previousReflectorHost="$(cat /var/home/wavelet/config/previousReflectorHost)"
			KEYNAME="/HOSTS/$hostNameSys/control/currentUGReflectorHost"; read_etcd_global # Populated by orchestrator
			if [[ -n "$printvalue" ]] ; then
				# update this value to the current reflector host for future reference
				echo "		Reflector host updated to: $printvalue"
				echo "$printvalue" > /var/home/wavelet/config/previousReflectorHost
			else
				# ensure it's overwritten
				echo "	Reflector host set to null!"
				echo "" > /var/home/wavelet/config/previousReflectorHost
			fi

			if [[ "$previousReflectorHost" == "$printvalue" ]]; then
				echo "	Reflector host $previousReflectorHost the same as $printvalue, continuing.."
			else
				echo "	Reflector host has changed, issuing unsubscribe request.."
				KEYNAME="/HOSTS/$hostNameSys/control/unsubRequest"; KEYVALUE="$previousVideoSourceValue"; write_etcd_global &
				KEYNAME="/HOSTS/$hostNameSys/control/currentUGReflectorHost"; delete_etcd_key_global &
			fi
		else
			echo "	Previous source was NOT an UltraGrid reflector.."
		fi
	fi
}

reconstruct_configPayload(){
	local sourceHash
	local configPayload=""
	# Determine sourceHash
	if [[ -n "${firstRunState:-}" ]]; then
		sourceHash="$etcdValue"
	else
		KEYNAME="/HOSTS/$hostNameSys/control/channelData"; read_etcd_global
		local channelData="$printvalue"
		if [[ -z "$channelData" ]]; then
			channelData="1-1"
		fi
		sourceHash="${channelData##*-}"
	fi
	# Check if static input (0|1|2|3)
	if [[ "$sourceHash" =~ ^(0|1|2|3)$ ]]; then
		configPayload="type:static|active:0|subType:static|cmd:"
	else
		# Not a static input, default to UltraGrid network source payload
		configPayload="type:ug|active:1|subType:ug|cmd:"
		# Try to determine if it's direct NDI mode
		local hostSourceKey=""
		if [[ -n "${_inputDeviceMap[$sourceHash]:-}" ]]; then
			hostSourceKey="${_inputDeviceMap[$sourceHash]}"
		else
			# Search etcd for the input key if not in map
			local inputKeys
			inputKeys=$(etcdctl get /UI/HOSTS --prefix --keys-only | grep "/inputs/$sourceHash$")
			if [[ -n "$inputKeys" ]]; then
				hostSourceKey=$(echo "$inputKeys" | head -n1)
			fi
		fi
		if [[ -n "$hostSourceKey" ]]; then
			KEYNAME="$hostSourceKey"; read_etcd_global; hostSourceData="$printvalue"
			if [[ "$hostSourceData" == *"NDI"* ]] || [[ "$hostSourceData" == *"RTSP"* ]]; then
				local deviceHostName
				local hostIP="${hostSourceData%;*}"
				deviceHostName="${hostIP#*;}"
				hostIP="${hostIP%%;*}"
				deviceHostName="${deviceHostName%%;*}.$(dnsdomainname)"
				KEYNAME="/HOSTS/$deviceHostName/control/directMode"; read_etcd_global
				local directMode="$printvalue"
				if [[ "$directMode" == "1" ]]; then
					# Direct NDI mode: reconstruct full network payload
					KEYNAME="/HOSTS/$deviceHostName/subType"; read_etcd_global
					local decoderSubType="$printvalue"
					KEYNAME="/HOSTS/$deviceHostName/uv_stream_cmd/subscribeStream"; read_etcd_global
					local decoderSubscribecmd="$printvalue"
					if [[ -n "$decoderSubscribecmd" ]]; then
						configPayload="type:network|active:1|subType:$decoderSubType|cmd:$decoderSubscribecmd"
					fi
				fi
			fi
		fi
	fi
	echo "$configPayload"
}

run_decoder(){
	# Begins the decoder process
	# On run, the decoder should be able to lookup the primary video source for the group it resides within.
	# On UltraGrid sources, this means joining a reflector in order to get a video stream
	ugName="UltraGrid.Decoder.service"
	ugPath="/var/home/wavelet/.config/systemd/user"
	staticImageFile="/var/home/wavelet/config/staticImage.mp4"
	blankImageFile="/var/home/wavelet/config/blankImage.bmp"
	local printvalue; local display; local ugArgs; local tries; local inputs
	local display; local audio; local command; local keyValue; local blankStatus
	local streamMode; local externalArg; local activeFlag
	local videoSourceCmd; local videoSourceType; local videoSourceSubType; local configPayload
	KEYNAME="/HOSTS/$hostNameSys/control/videoSourceConfig"; read_etcd_global
	if [[ -z "$printvalue" ]]; then
		# We have an error and need to get a proper configPayload or build it from scratch here.
		# PLACEHOLDER:
		configPayload="$(reconstruct_configPayload)"
	else
		configPayload="$printvalue"
	fi
	if [[ -z "$configPayload" ]]; then
		# Final error and we stop trying here.
		msg="ERR: videoSourceConfig not found for $hostNameSys.  Exiting decoder run attempt!"
		KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="$msg"; write_etcd_global &
		echo "	$msg"
		exit 0
	fi
	# Parse the payload compound KV (Format: type:X|active:Y|subType:Z|cmd:W)
	videoSourceType="${configPayload##*type:}"
	videoSourceType="${videoSourceType%%|*}"
	activeFlag="${configPayload##*active:}"
	activeFlag="${activeFlag%%|*}"
	videoSourceSubType="${configPayload##*subType:}"
	videoSourceSubType="${videoSourceSubType%%|*}"
	videoSourceCmd="${configPayload##*cmd:}"
	if [[ -n "$videoSourceCmd" && "$videoSourceCmd" != "cmd:" ]]; then
		videoSourceCmd="$(base64 -d <<<"$videoSourceCmd")"
		# Strip trailing newline/CR that upstream echo/base64 encoding added
		while [[ "$videoSourceCmd" == *$'\n' ]] || [[ "$videoSourceCmd" == *$'\r' ]]; do
			videoSourceCmd="${videoSourceCmd%$'\n'}"
			videoSourceCmd="${videoSourceCmd%$'\r'}"
		done
		# TODO - implement guards to prevent systemd unit injection.
	fi
	echo "	Parsed videoSourceConfig - Type: $videoSourceType, SubType: $videoSourceSubType, Active: $activeFlag"
	echo "	Video Source Subtype: $videoSourceSubType"
   	if [[ "$etcdValue" =~ ^[0-3]$ ]]; then
   		# Static image - no subscription needed
   		streamMode="static"
   		channel="$etcdValue"
   	elif [[ "$videoSourceSubType" == "NDI" ]] || [[ "$videoSourceSubType" == "RTSP" ]]; then
   		echo "	Checking video source type: $videoSourceCmd (explicit type: $videoSourceType)"
  		# Architectural note:
  		# Since we cannot reliably use excl_init to ensure unused devices aren't in the event loop,
  		# we must assume all inputs defined here in addition to the statics are live at all times.
   		# This places a processing burden on the clients even if it is just dropping frames.
   		# Therefore: we cannot simply additively append every encoder/source device
   		# on the entire system as a potential input,
   		# which may seem more efficient from the regen gap perspective.
   		# It may be possible to implement an input shim however?
		case "$videoSourceCmd" in
  			*ndi*)
  				externalArg+=("-t ug_input:5004") # Always keep a UG input to avoid unnecessary unit regen
   				externalArg+=("$videoSourceCmd") # NDI command referencing the specific ndi name/IP here
   				streamMode="ndi"
   				channel="5"
   				;;
   			*rtsp*)
   				externalArg+=("-t ug_input:5004")
   				externalArg+=("$videoSourceCmd")
   				streamMode="rtsp"
   				channel="5"
   				;;
   			*)
   				# Unknown type, fall back to UG only.
   				streamMode="ug"
   				channel="4"
   				externalArg+=("-t ug_input:5004")
   				;;
   		esac
   	else
   		echo "		Defaulting to UltraGrid source"
   		streamMode="ug"
   		channel="4"
   		externalArg+=("-t ug_input:5004")
   	fi
	check_reflector_subscription
	# Note that unless we had a proper VIDEO_SOURCE_CMD value, NDI won't (currently) be functional.
	# -t switcher:excl_init would be great for performance reasons, however it tends to hardlock the client machines
	# this means its not usable until modifications can be made under the hood in UltraGrid
	display=""
	inputs=()
	inputs+=("-t switcher")
	inputs+=("-t testcard:pattern=blank")
	inputs+=("-t file:$staticImageFile:loop")
	inputs+=("-t testcard:pattern=smpte_bars")
	inputs+=("-t file:$blankImageFile:loop")
	inputs+=("${externalArg[@]}")
	display="-d vulkan:nodecorate:nocursor:tearing:fs"
	ugArgs=()
#	ugArgs+=("--tool uv") # required for AppImage
	ugArgs+=("${inputs[@]}")
	ugArgs+=("$display")
	ugArgs+=("${audio:-}")
	ugArgs+=("--control-port 6161")
	ugArgs+=("--param use-hw-accel")
	ugArgs+=("--param gl-disable-10b")
	# append -VV to enable verbose logging
	# check for our image files, both must be present or the switcher will fail to launch.
	if [[ ! -f "$staticImageFile" ]]; then
		regenerate_staticImage
	fi
	if [[ ! -f "$blankImageFile" ]]; then
		regenerate_blankImage
	fi
	if [[ "$blankStatus" == "1" ]] && [[ "$hostNameSys" == *"svr"* ]]; then
		# We don't want the server displaying anything unless it's specifically unblanked.
		exit 0
	fi
	# check for an already running UG systemd unit
	if systemctl --user is-active UltraGrid.Decoder.service >/dev/null 2>&1; then
		if [[ "$(cat "$ugPath/$ugName")" == *"${externalArg[*]}"* ]]; then
			echo "	UGArgs match existing service, no regeneration needed"
		else
			# echo "		UGArgs do not match existing service, regeneration needed"
			regenerate_decoder_ugUnit
		fi
		# Proceed to setting the channel index since we have a running UG service.
	else
		regenerate_decoder_ugUnit
	fi
	# blankStatus is set from the host conf file and populated whenever this module is called
	if [[ "$blankStatus" -eq 1 ]]; then
		# we will ALAWYS set channel = 3 if blankStatus = 1
		echo "	Blank is enabled, setting blank display and updating host channelData control key with: $channel-$etcdValue"
		KEYNAME="/HOSTS/$hostNameSys/control/channelData"; KEYVALUE="$channel-$etcdValue"; write_etcd_global &
		channel="3"
		controlPortCmd="capture.data $channel"; netCat "6161" "$controlPortCmd" &
	else
		set_channelIndex
	fi
}

set_channelIndex(){
	# We need to check to see if we need to send an unsubscribe request to a device
	# Note our context here is running as a decoder host, we can only read our own UI keys and group UI keys.
	controlPortCmd="capture.data $channel"; netCat "6161" "$controlPortCmd"
	echo "		Attempting to set UG decoder to channel: $channel" &
	# Finally, we discover and set our previousVideoSourceKey data now that we have successfully started our stream.
	# When the decoder next experiences a source state change, it will refer to the HOSTS previousVideoSourceKey data
	echo "		Writing host previous video source key: $etcdValue" &
	# This key tracks state so we know what to revert to if reveal/blank are enabled then turned off.
	KEYNAME="/HOSTS/$hostNameSys/control/channelData"; KEYVALUE="$channel-$etcdValue"; write_etcd_global &
	updatelocalConfig "channelData"
	KEYNAME="/HOSTS/$hostNameSys/control/previousVideoSourceKey"; KEYVALUE="$etcdValue"; write_etcd_global &
	updatelocalConfig "previousVideoSourceKey"
	KEYNAME="/HOSTS/$hostNameSys/control/previousVideoSourceType"; KEYVALUE="$streamMode"; write_etcd_global &
	updatelocalConfig "previousVideoSourceType"
	# Are we in UI mode?
	get_swaySocket
	if [[ -f "/var/home/wavelet/config/webui.enabled" ]]; then
		uiEnable_moveUGWindow
	else
		uiDisable_moveUGWindow
	fi
}

regenerate_decoder_ugUnit(){
	# Regenerates and starts the decoder display UG unit.
	# Check for existing input files
	if [[ ! -f $blankImageFile ]] || [[ ! -f $staticImageFile ]]; then
		regenerate_staticImage
		regenerate_blankImage
	fi
	# Invalidate sway cache since UG service is being restarted
	rm -f /var/home/wavelet/config/ug_con_id.cache
	# Generate the decoder process and start
	tries=0
	if ! start_ug; then
		echo "      Decoder failed to start, trying GL as fallback"
		display="-d gl:fs"
		ugArgs+=("$command")
		ugArgs+=("$display")
		ugArgs+=("$audio")
		ugArgs+=("--control-port 6161")
		ugArgs+=("--param-use-hw-accel")
		(( tries++ ))
		echo $tries > /var/home/wavelet/config/decoder_tries
		if ! start_ug; then
			echo "        Decoder failed in both Vulkan and GL modes!"
			KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE=5; write_etcd_global &
			return
		fi
	fi
	echo "        Decoder start successful!"
	KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE=0; write_etcd_global &
	rm -rf /var/home/wavelet/config/decoder_tries
	get_ipValue
}
regenerate_staticImage(){
	# Grab the staticImage from the server URL after regeneration
	if [[ "$etcdValue" == "0" ]]; then
		exit 0
	fi
	local attempt=1
	local max_attempts=3
	KEYNAME="/UI/GROUPS/$groupHash/control/staticImage"; read_etcd_global
	echo "        Downloading static image video loop for local playback from $printvalue.."

	# Validate etcd-supplied URL to prevent SSRF
	if [[ "$printvalue" != https://* && "$printvalue" != http://localhost* && "$printvalue" != http://127.0.0.1* && "$printvalue" != http://$hostNameSys* ]]; then
		echo "	ERR: Invalid static image URL, rejecting etcd-supplied URL!"
		errorStatus="ERR: Invalid static image URL"
		KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="$errorStatus"; write_etcd_global &
		return 1
	fi

	# We just grab the mp4 loop direct from the webserver URL, including the sha256 hash
	while [[ $attempt -le $max_attempts ]]; do
		wget -O "/var/home/wavelet/config/staticImage.mp4" "$printvalue"
		wget -O "/var/home/wavelet/config/staticImage.sha256" "${printvalue%.mp4}.sha256"
		serverCheckSum="$(cat "/var/home/wavelet/config/staticImage.sha256" | cut -d' ' -f1)"
		# Todo try to replace with bash param expansion
		localCheckSum=$(sha256sum "/var/home/wavelet/config/staticImage.mp4" | cut -d' ' -f1)
		if [[ "$localCheckSum" != "$serverCheckSum" ]]; then
			echo "	ERR: static image hash mismatch!"
			(( attempt++ ))
			if [[ $attempt -gt $max_attempts ]]; then
				errorStatus="ERR: Unable to update static image selection, hash mismatch!"
				KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="$errorStatus"; write_etcd_global &
				echo "	$errorStatus"
				return 1
			fi
			sleep 1
		else
			KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="OK: Static image updated"
			write_etcd_global &
			echo "	$KEYVALUE"
			return 0
		fi
	done
}
regenerate_blankImage(){
  # Grab the staticImage and generate it correctly.
  echo "        Generating blank display slide.."
  local imageLabel
  rm -rf /var/home/wavelet/config/blankImage.bmp
  rm -rf /var/home/wavelet/config/blankImage.mp4
  if [[ "$hostNameSys" != *"dec"* ]]; then
	imageLabel="Encoder task running.  Un-blank to show video output."
  else
	imageLabel="This screen is intentionally blank."
  fi
  color="rgb(.2, .2, .2, 0)"
  backgroundcolor="rgb(.2, .2, .2, 0)"
  magick -size 1920x1080 -pointsize 50 -background "$color" -bordercolor "$backgroundcolor" \
	-gravity Center -fill white label:"$imageLabel" \
	-colorspace RGB /var/home/wavelet/config/blankImage.bmp
  ffmpeg \
	-fflags +genpts -loop 1 -i /var/home/wavelet/config/blankImage.bmp \
	-t 10 -c:v mjpeg -q:v 0 /var/home/wavelet/config/blankImage.mp4 2>/dev/null
  KEYNAME="/HOSTS/$hostNameSys/control/updateImage"; delete_etcd_key_global &
}

start_ug(){
	# Populates the UltraGrid.service
	# ug_args comes from run_decoder
	# The service requires systemd WATCHDOG=1 signals to continue running
	# These are generated by the wrapper script based off the UG executable's log output.
	# The unit is tuned to be very "impatient" so as to minimize video output disruption.
	local targetFile
	if [[ -f "/var/wavelet_ramfs/wavelet_ug_wrapper.sh" ]]; then
		targetFile="/var/wavelet_ramfs/wavelet_ug_wrapper.sh"
	else
		targetFile="/usr/local/bin/wavelet_ug_wrapper.sh"
	fi
	cat > "/home/wavelet/.config/systemd/user/$ugName" <<-EOF
		[Unit]
		Description=UltraGrid AppImage Wrapper
		After=network-online.target
		Wants=network-online.target

		[Service]
		Type=notify
		ExecStart=${targetFile} ${ugArgs[@]}
		StandardOutput=append:/tmp/ug_output.log
		StandardError=append:/tmp/ug_error.log
		Restart=on-failure
		RestartSec=2
		TimeoutStopSec=2s
		TimeoutStartSec=5s
		KillMode=mixed
		KillSignal=SIGTERM
		SendSIGKILL=yes
		FinalKillSignal=SIGKILL
		WatchdogSec=8s
		NotifyAccess=all
		# Ceiling for the UG child only
		# the wrapper process itself stays unpinned at normal priority.
		LimitRTPRIO=55
		LimitMEMLOCK=512M

		[Install]
		WantedBy=default.target
		EOF
	systemctl --user --no-block daemon-reload
	systemctl --user --force stop "$ugName"
	echo "		Waiting for UltraGrid.Decoder.service to become active..."
	if ! systemctl --user --no-block start "$ugName"; then
		echo "		Error: Failed to restart $ugName. Aborting channel switch."
		exit 0
	fi
	# Poll until active or timeout
	local timeout=30
	local count=0
	until systemctl --user is-active "$ugName" || [[ $count -ge $timeout ]]; do
		sleep .1
		((count++))
	done
	# This continues the same count timer
    if [[ $count -ge $timeout ]]; then
		echo "		Error: $ugName failed to become active within expected .5 seconds. Attempting to remediate.."
		timeout=30
		until systemctl --user is-active "$ugName" || [[ $count -ge $timeout ]]; do
			sleep .1
			(( count++ ))
		done
	fi
	return 0
}

# NDI sources mapfile management functions
update_ndi_sources_mapfile(){
	# Updates the NDI sources mapfile with current NDI sources for the group
	# Format: channelIndex:ndiSourceName:sourceHash
	local groupHash="$1"
	local mapfileContent=""
	# Clear the mapfile
	echo "" > "$NDI_SOURCES_MAPFILE"
	# Get all NDI sources in the group from etcd
	local ndiSources=()
	local index=1
	# Iterate through all hosts in the group to find NDI sources
	for hostHash in "${hostsInGroup[@]}"; do
		local hostKey="${_hostNameMap[$hostHash]:-}"
		if [[ -n "$hostKey" ]]; then
			# Check if this host has NDI inputs
			KEYNAME="/HOSTS/$hostKey/NDI_SOURCES"; read_etcd_global
			if [[ -n "$printvalue" ]]; then
				# Parse NDI sources from the key value
				IFS=';' read -ra sourceArray <<< "$printvalue"
				for source in "${sourceArray[@]}"; do
					if [[ -n "$source" ]]; then
						ndiSources+=("$index:$source:$hostHash")
						((index++))
					fi
				done
			fi
		fi
	done
	# Sort NDI sources to ensure consistent ordering across all clients
	IFS=$'\n' sortedNdiSources=($(sort <<<"${ndiSources[*]}")); unset IFS
	# Write sorted sources to mapfile
	for sourceEntry in "${sortedNdiSources[@]}"; do
		echo "$sourceEntry" >> "$NDI_SOURCES_MAPFILE"
	done
}

check_ndi_source_in_mapfile(){
	# Checks if a specific NDI source is already in the mapfile
	local ndiSource="$1"
	if [[ ! -f "$NDI_SOURCES_MAPFILE" ]]; then
		return 1
	fi
	# Search for the NDI source in the mapfile
	if grep -q ":$ndiSource:" "$NDI_SOURCES_MAPFILE"; then
		return 0
	else
		return 1
	fi
}

get_ndi_source_channel_index(){
	# Gets the channel index for a specific NDI source from the mapfile
	local ndiSource="$1"
	local channelIndex=""
	if [[ ! -f "$NDI_SOURCES_MAPFILE" ]]; then
		echo ""
		return 1
	fi
	# Extract the channel index for the given NDI source
	channelIndex=$(grep ":$ndiSource:" "$NDI_SOURCES_MAPFILE" | cut -d':' -f1)
	echo "$channelIndex"
}

get_hosts_in_group(){
	# Common function to return all the hosts in this group
	declare -A host_group_map
	# We may need to change this so we can structure an object, mapfile and parse it back
	hostsInGroup=()
	fullPrefixList=()
	KEYNAME="/UI/HOSTS/"; read_etcd_prefix_list
	while IFS= read -r line; do
		fullPrefixList+=("$line")
		if [[ "$line" == */control/GROUP ]]; then
			# Store this key, and get the value on the next iteration, then return both.
			local host_hash="${line#/UI/HOSTS/}"
			host_hash="${host_hash%/control/GROUP}"
			if [[ -z "$host_hash" ]]; then
				continue
			fi
			IFS= read -r next_line
			if [[ -n "$next_line" ]]; then
				# Process the key-value pair
				host_group_map["$host_hash"]="$next_line"
			fi
		elif [[ "$line" =~ ^/UI/HOSTS/[^/]+$ ]]; then
			# This is the hostname value line (the one right after /UI/HOSTS/{hash})
			local host_hash="${line#/UI/HOSTS/}"
			IFS= read -r next_line
			if [[ -n "$next_line" ]]; then
				_hostNameMap["$host_hash"]="$next_line"
			fi
		elif [[ "$line" == */inputs/* ]] && [[ ! "$line" =~ /inputs/.*devpath_lookup ]]; then
			# Store input device keys indexed by the last path component (the input hash)
			local inputKey="${line##*/}"
			IFS= read -r next_line
			if [[ -n "$next_line" ]]; then
				_inputDeviceMap["$inputKey"]="$line"
			fi
		fi
	done <<<"$printvalue"
	for host_hash in "${!host_group_map[@]}"; do
		if [[ "${host_group_map[$host_hash]}" == "$groupHash" ]]; then
			hostsInGroup+=("$host_hash")
			# echo "        Host hash ID: $host_hash is in the affected group!"
		fi
	done
	if [[ -z "${hostsInGroup[*]}" ]]; then
		echo "	No hosts located in group!  This could indicate an issue, or just the creation of a new group"
	fi
}

netCat(){
    # Simple function to submit data to netcat
    local port="${1:-6161}"
    local controlPortCmd="${2:-$controlPortCmd}"
#    echo "Port: $port, Command: $controlPortCmd"
    response=$(nc 127.0.0.1 "$port" <<<"$controlPortCmd");
    # "202 Accepted" = UltraGrid change upstream after a bugfix, we will accept both
    if [[ "$response" != *"202 Accepted"* && "$response" != *"200 OK"* ]]; then
    	echo "	Control Port exception: $response"
    fi
}

get_swaySocket(){
	swaySocket=""
	for sock in "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/sway-ipc.*.sock; do
		if [[ -S "$sock" ]] && swaymsg -s "$sock" -t get_tree >/dev/null 2>&1; then
			swaySocket="$sock"
			break
		fi
	done
	if [[ -z "$swaySocket" ]]; then
		echo "	ERROR: No valid sway socket found, aborting UI toggle." >&2
		KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="ERR: UI Toggle failed"; write_etcd_global &
		return 1
	fi
	export swaySocket
}

# Find UltraGrid container ID by matching app_id, class, OR instance == "uv".
find_ug_con_id(){
	# Find UltraGrid container ID by matching app_id, class, OR instance == "uv".
    local cacheFile="/var/home/wavelet/config/ug_con_id.cache"
    if [[ -f "$cacheFile" ]]; then
        local cachedId
        cachedId="$(cat "$cacheFile")"
        if [[ -n "$cachedId" ]]; then
            # Use cached ID directly. If UG was restarted, the sway commands below will handle it gracefully.
            echo "$cachedId"
            return 0
        fi
    fi
    # Fetch and cache
    local ugId; local sortCommand
    sortCommand='recurse(.nodes[]?, .floating[]?) | select((.app_id == "uv") or (.window_properties.class == "uv")) | .id // empty'
    ugId="$(swaymsg -t get_tree -s "$swaySocket" | jq -r "$sortCommand")"
    if [[ -n "$ugId" ]]; then
        echo "$ugId" > "$cacheFile"
        echo "$ugId"
    else
        echo "	WARNING: UltraGrid container not found in sway tree." >&2
        return 1
    fi
}

uiEnable_moveUGWindow(){
    # Moves UltraGrid window when UI gets enabled.
    if [[ "$hostNameSys" == *"svr"* ]]; then
        echo "	Server does not have a UG window, skipping UI window move."
        return 0
    fi
    local workspace; local width; local height;local targetWidth; local targetHeight; local ugId
    local displayResolution
    local resCacheFile="/var/home/wavelet/config/display_resolution.cache"
    # Determines resolution, workspace and moves the UG window appropriately
    if [[ "$hostNameSys" == *"svr"* ]]; then
        elapsedBootTime="$(uptime | awk '{print $3}')"
        if [[ $elapsedBootTime -lt 3 ]]; then
            sleep 4
            workspace=1
        fi
    else
        workspace=2
    fi
    # Use cached display resolution if available
    if [[ -f "$resCacheFile" ]]; then
        displayResolution="$(cat "$resCacheFile")"
    else
        displayResolution="$(swaymsg -t get_outputs -s "$swaySocket" \
                | jq -r '.[] | select(.active == true) | "\(.rect.width)x\(.rect.height)"' | head -n1)"
        if [[ -n "$displayResolution" ]]; then
            echo "$displayResolution" > "$resCacheFile"
        fi
    fi
    if [[ -z "$displayResolution" ]]; then
        echo "	ERROR: Unable to determine display resolution!"
        KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="ERR: No display resolution"; write_etcd_global &
        return 1
    fi
    width="${displayResolution%x*}"
    height="${displayResolution#*x}"
    targetWidth=$(( width / 2 ))
    targetHeight=$(( height * 9 / 16 ))
    echo "	Disabling fullscreen and setting window float at $targetWidth x $targetHeight for UltraGrid container.."
    ugId="$(find_ug_con_id)" || return 0
    if [[ -z "$ugId" ]]; then
        echo "	ERROR: Unable to determine window ID for UltraGrid!!"
        KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="ERR: No UltraGrid sway window ID"; write_etcd_global &
        return 0
    fi
    # Verify UltraGrid window exists before issuing move commands
    if ! swaymsg -t get_tree -s "$swaySocket" | jq -r 'recurse(.nodes[]?, .floating[]?) | select((.app_id == "uv") or (.window_properties.class == "uv")) | .id // empty' | grep -qx "$ugId"; then
        echo "	Warning: UltraGrid window no longer exists, skipping move commands."
        return 0
    fi
    swaymsg -s "$swaySocket" "[con_id=$ugId] floating enable"
    swaymsg -s "$swaySocket" "[con_id=$ugId] fullscreen disable"
    swaymsg -s "$swaySocket" "[con_id=$ugId] resize set $targetWidth $targetHeight"
    echo "	Moving UltraGrid container to workspace $workspace.."
    swaymsg -s "$swaySocket" "[con_id=$ugId] move container to workspace $workspace"
    swaymsg -s "$swaySocket" "[con_id=$ugId] move position 1400 0"
}

uiDisable_moveUGWindow(){
    local workspace; local width; local height; local ugId; local displayResolution; local noDecoderWindow
    local resCacheFile="/var/home/wavelet/config/display_resolution.cache"
    # Determines resolution, workspace and moves the UG window appropriately
    if [[ "$hostNameSys" == *"svr"* ]]; then
        echo "	This is the server, setting workspace to 1."
        workspace=1
        noDecoderWindow=1
    else
        echo "	This is a client, setting workspace to 2."
        workspace=2
    fi
    if [[ "$workspace" != 1 ]] && [[ $noDecoderWindow != 1 ]]; then
        # Use cached display resolution if available
        if [[ -f "$resCacheFile" ]]; then
            displayResolution="$(cat "$resCacheFile")"
        else
            displayResolution="$(swaymsg -t get_outputs -s "$swaySocket" \
                    | jq -r '.[] | select(.active == true) | "\(.rect.width)x\(.rect.height)"' | head -n1)"
            if [[ -n "$displayResolution" ]]; then
                echo "$displayResolution" > "$resCacheFile"
            fi
        fi
        if [[ -z "$displayResolution" ]]; then
            echo "	ERROR: Unable to determine display resolution!"
            KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="ERR: No display resolution"; write_etcd_global &
            return 1
        fi
        width="${displayResolution%x*}"
        height="${displayResolution#*x}"
        echo "	Got display resolution width: $width and height: $height"
        ugId="$(find_ug_con_id)" || return 0
        if [[ -z "$ugId" ]]; then
            echo "	ERROR: Unable to determine window ID for UltraGrid!!"
            KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="ERR: No UltraGrid sway window ID"; write_etcd_global &
            return 0
        fi
        # Verify UltraGrid window exists before issuing move commands
        if ! swaymsg -t get_tree -s "$swaySocket" | jq -r 'recurse(.nodes[]?, .floating[]?) | select((.app_id == "uv") or (.window_properties.class == "uv")) | .id // empty' | grep -qx "$ugId"; then
            echo "	Warning: UltraGrid window no longer exists, skipping move commands."
            return 0
        fi
        echo "	Moving UltraGrid output container to workspace $workspace.."
        swaymsg -s "$swaySocket" "[con_id=$ugId] move container to workspace $workspace"
        echo "	Resizing UltraGrid output container to fullscreen.."
        swaymsg -s "$swaySocket" "[con_id=$ugId] floating disable"
        swaymsg -s "$swaySocket" "[con_id=$ugId] resize set $width $height"
        swaymsg -s "$swaySocket" "[con_id=$ugId] fullscreen enable"
        # Switch sway back to workspace
        swaymsg -s "$swaySocket" "workspace $workspace"
    fi
}


event_get_config(){
	# Load this host's env vars from the conf file using flat key-value parsing
	configFile="/var/home/wavelet/config/$hostNameSys.conf"
	declare -A host_config
	if [[ ! -f "$configFile" ]]; then
		echo "	Warning: Config file $configFile not found, using defaults."
		return 1
	fi
	while IFS= read -r line; do
		line="${line//$'\r'/}"
		[[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
		[[ "$line" != *=* ]] && continue
        key="${line%%=*}"
        key="${key#export *}"
        value="${line#*=}"
        value="${value#\"}"
        value="${value%\"}"
		host_config["$key"]="$value"
	done <"$configFile"
	# Populate host configuration variables from the parsed host_config array
#	echo "	Host config data:"
#	for key in "${!host_config[@]}"; do
#		echo "		$key:	${host_config[$key]}"
#	done
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
	blankStatus="${host_config[blankStatus]:-}"
	channelData="${host_config[channelData]:-}"
}

update_config() {
	# Update the host config and then clean flag
	if [[ "$etcdValue" == 0 ]]; then
		exit 0
	fi
	configTemp="$(mktemp)"
	KEYNAME="/HOSTS/$hostNameSys/confHash"; read_etcd_global; confHash="$printvalue"
	KEYNAME="/HOSTS/$hostNameSys/conf"; read_etcd_global; configData="$printvalue"
	# Decode base64 config data to temp file
	echo "$configData" | base64 -d > "$configTemp"
	# test config for data integrity
	checksum="$(sha256sum <"$configTemp" | tr -d ' \t\n-')"
	if [[ "$confHash" != "$checksum" ]]; then
		echo "	ERR:  Config file data integrity issue!"
		exit 0
	else
		# overwrite our configFile
		cat "$configTemp" > "$configFile"
	fi
	rm -f "$configTemp"
}


###
#
# Main
#
###


exec >>/var/home/wavelet/logs/client.log 2>&1

start_timer
trap 'stop_timer "$timer_id_out"; echo "Total: ${timer_duration}s" >&2' EXIT

hostNameSys="$(hostname)"
etcdValue="$ETCD_WATCH_VALUE"
if [[ "$etcdValue" == \"*\" && "$etcdValue" == *\" ]]; then
	etcdValue="${etcdValue#\"}"
	etcdValue="${etcdValue%\"}"
fi
etcdKey="$ETCD_WATCH_KEY"
if [[ "$etcdKey" == \"*\" && "$etcdKey" == *\" ]]; then
	etcdKey="${etcdKey#\"}"
	etcdKey="${etcdKey%\"}"
fi

declare -A processing_group
declare -A _hostNameMap          # hostHash → hostname (populated by get_hosts_in_group)
declare -A _inputDeviceMap       # inputHash → /UI/HOSTS/{hash}/inputs/ key (populated by get_hosts_in_group)
sleepTimer=60

# NDI sources mapfile for lazy regeneration
NDI_SOURCES_MAPFILE="/var/home/wavelet/config/ndi_sources.map"

# Host configuration associative array (flat key-value format)
declare -A host_config
configFileExists=false

event_get_config

case "$@" in
	*SVR*)
		detect_operation_server;;
	*HOST*)
		detect_operation;;
	*RUN*)
		firstRunState="true"
		touch "/var/home/wavelet/config/firstrun_token"
		wavelet_run;; # This is the initial encoder setup so we must ensure videoSource is set
esac