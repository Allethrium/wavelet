#!/bin/bash

# This module is responsible for orchestrating client activities based off key changes from /UI/HOSTS/$hostname/control
# It replaces the previous approach of having many different individual modules and watcher systemd services.
# The client controller runs on the client devices directly.

# /UI/HOSTS/$hostHash						-	the device prefix key and hostname
# /UI/HOSTS/$hostHash/IP 					-	IP4 Addr
# /UI/HOSTS/$hostHash/control/blankStatus	-	function decides on what to do based off type, blanks the input/output
# /UI/HOSTS/$hostHash/control/rebootStatus	-	reboot flag for this host
# /UI/HOSTS/$hostHash/control/resetStatus	-	process term/restart to avoid cold reset
# /UI/HOSTS/$hostHash/control/revealStatus	-	displays a testcard from host if encoder, displays testcard on only host if decoder
# /UI/HOSTS/$hostHash/control/label 		-	changes the device pretty hostname
# /UI/HOSTS/$hostHash/control/PROMOTE 		-	switches clients between encoders or decoders
# /UI/HOSTS/$hostHash/hash 					-	does not change, this is the device's unique ID used to populate the webUI and identify it
# /UI/HOSTS/$hostHash/type 					-	the device type
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

declare -A processing_group
declare -A _hostNameMap          # hostHash → hostname (populated by get_hosts_in_group)
declare -A _inputDeviceMap       # inputHash → /UI/HOSTS/{hash}/inputs/ key (populated by get_hosts_in_group)
sleepTimer=60

# Process inputs
detect_operation(){
	# Inputs are specified from the etcdctl process which spawns this module
	# Therefore they will be populated along with their revision numbers in ENV
	# TODO - consider a global dispatch table and a local valkey cache to avoid GRPc call
	thisHostHash="${etcdKey#/UI/HOSTS/}"
	thisHostHash="${thisHostHash%%/*}"
	KEYNAME="/HOSTS/$hostNameSys/control/GROUP"; read_etcd_global; groupHash="$printvalue"
	echo -e "	Host Matching:\n		Key: $etcdKey\n		Value: $etcdValue"
	case $etcdKey in
		"/UI/HOSTS/$thisHostHash/IP")						exit 0 ;; # nooop
		"/UI/HOSTS/$thisHostHash/control/label")			event_relabel;;
		"/UI/HOSTS/$thisHostHash/control/authScreencast")	authorize_screencast;;
		"/UI/HOSTS/$thisHostHash/control/blankStatus")		event_blank;;
		"/UI/HOSTS/$thisHostHash/control/deprovision")		event_deprovision;;
		"/UI/HOSTS/$thisHostHash/directMode")				event_set_directMode;;
		"/UI/HOSTS/$thisHostHash/control/enableScreencast")	toggle_screencast;;
		"/UI/HOSTS/$thisHostHash/control/GROUP")			event_change_group;;
		"/UI/HOSTS/$thisHostHash/control/promote")			event_promote;;
		"/UI/HOSTS/$thisHostHash/control/rebootStatus")	    event_reboot;;
		"/UI/HOSTS/$thisHostHash/control/resetStatus")	    event_reset;;
		"/UI/HOSTS/$thisHostHash/control/revealStatus")	    event_reveal;;
		"/UI/HOSTS/$thisHostHash/control/updateImage")		regenerate_staticImage;;
		"/UI/HOSTS/$thisHostHash/control/UIEnable")			toggle_userInterface;;
		"/UI/HOSTS/$thisHostHash/control/videoSource")		wavelet_run;;
		*) echo "	No match for this host hash: $thisHostHash"; exit 0;; #noop
	esac
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
	if [[ "$etcdKey" == "/UI/HOSTS/"* ]]; then
		detect_operation
	elif [[ "$etcdKey" == "/UI/GROUPS/"* ]]; then
		groupHash="${etcdKey#*/UI/GROUPS/}"
		groupHash="${groupHash%%/*}"
		case "$etcdKey" in
			*/control/audioStatus)			event_group_enable_audio;;
			*/control/bannerStatus)			event_group_enable_banner;;
			*/control/blankStatus)			event_group_host_blank;;
			*/control/liveStreamStatus)		event_group_liveStream;;
			*/control/persistStatus)		event_group_input_persist;;
			*/control/rebootStatus)			event_group_host_reboot;;
			*/control/resetStatus)			event_group_host_reset;;
			*/control/revealStatus*)		event_group_host_reveal;;
			*/control/bannercontent*)		event_group_set_bannerContent;;
			*/control/liveStreamData)		event_group_set_liveStreamConfig;;
			*/control/blueToothMAC)			event_group_set_blueToothMAC;;
			*/control/sourceHash)			event_group_set_video_source;;
			*/control/staticImage)			event_group_set_staticImage;;
			*/control/activeCodec)			event_group_set_codec;;
			*) exit 0;;
		esac
	elif [[ "$etcdKey" == "/UI/GLOBALS/control"* ]]; then
		case "$etcdKey" in
			/UI/GLOBALS/control/GROUP-CREATE*)		event_create_group;;
			/UI/GLOBALS/control/GROUP-DELETE*)		event_delete_group;;
	esac
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
	echo "      Banner enabled"
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
	echo "	Getting hosts in group: $groupHash"
	get_hosts_in_group
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
    local batch_size=10
    for ((i=0; i<${#write_cmds[@]}; i+=batch_size)); do
        local batch=("${write_cmds[@]:i:batch_size}")
        for cmd in "${batch[@]}"; do
            KEYNAME="${cmd%=*}"; KEYVALUE="${cmd#*=}"; write_etcd_global &
        done
        wait
    done
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
	if [[ "$etcdValue" -eq 1 ]]; then
		echo "	Deprovision flag is set.  System will deprovision itself.."
		echo "	Setting hard deprovision flag to start teardown timer.."
		KEYNAME="/HOSTS/$hostNameSys/DEPROVISION"; KEYVALUE="1"; write_etcd_global
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
	if [[ "$etcdValue" -eq 1 ]]; then
		# This starts a timer which will activate wavelet_deprovision_watcher to perform cleanup
		echo "	Deprovision flag is set.  System will deprovision itself.."
		echo "	Setting hard deprovision flag to start teardown timer.."
		# Get the hostname here from our activation key
		KEYNAME="${etcdKey%/control/deprovision*}"; read_etcd_global
		targetHostName="${printvalue#/UI/HOSTS/*}"
		targetHostName="${targetHostName%%/*}"
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
		KEYNAME="/HOSTS/$hostNameSys/control/blankStatus"; KEYVALUE="0"; write_etcd_global &
	else
		echo -e "	Blank flag change detected (blank), switching host to blank input channel (3)..\n"
		# mute audio for this output as privacy is implied
		pactl set-sink-mute "$(pactl get-default-sink)" 1
		# Now, we switch channel to option 3 which is always the blank screen
		controlPortCmd="capture.data 3"; netCat "6161" "$controlPortCmd"
		KEYNAME="/HOSTS/$hostNameSys/control/blankStatus"; KEYVALUE="1"; write_etcd_global &
	fi
}
event_unblank(){
	if [[ "$hostNameSys" == *"svr"* ]]; then
		exit 0
	fi
	local channelData; local channelIndex; local channelSourceHash; local videoSourceType
	echo -e "	Blank flag change detected (unblank), switching host to selected input channel..\n"
    pactl set-sink-mute "$(pactl get-default-sink)" 0
    # Check our explicit state keys first
    KEYNAME="/HOSTS/$hostNameSys/control/videoSourceType"; read_etcd_global
    videoSourceType="$printvalue"
    if [[ -z "$videoSourceType" ]]; then
    	# Fallback to channel-Source if state not set
    	videoSourceType="static"
    fi
    # Get channel data from persistent key
    KEYNAME="/HOSTS/$hostNameSys/control/channel-Source"; read_etcd_global
    channelData="$printvalue"
    if [[ -z "$channelData" ]]; then
    	echo "	Warning: No channel-Source data found, defaulting to channel 1"
    	channelData="1-1"
    fi
    channelIndex="${channelData%%-*}"
    channelSourceHash="${channelData##*-}"
    echo "	Previous video source is on channel: $channelIndex with source hash: $channelSourceHash (type: $videoSourceType)"
	controlPortCmd="capture.data $channelIndex"; netCat "6161" "$controlPortCmd"
}
event_relabel(){
	# Relabel Functionality
	if [[ "$hostNameSys" != *"svr"* ]]; then
		echo "      Relabeling this host.."
		hostnamectl --pretty hostname "$etcdValue"
	else
		echo "		Server cannot be relabeled."
		KEYNAME="/UI/HOSTS/$thisHostHash/control/label"; KEYVALUE="$hostNameSys"; write_etcd_global &
	fi
}
event_reveal(){
	if [[ "$hostNameSys" == *"svr"* ]]; then
		exit 0
	fi
	if [[ "$etcdValue" == "0" ]] || [[ -z "$etcdValue" ]]; then
		exit 0
	fi
   	local channelData; local channelIndex; local channelSourceHash; local videoSourceType
   	echo "	Showing testcard on this client for 15 seconds.."
   	# Check our explicit state keys first
   	KEYNAME="/HOSTS/$hostNameSys/control/videoSourceType"; read_etcd_global
   	videoSourceType="$printvalue"
   	if [[ -z "$videoSourceType" ]]; then
   		videoSourceType="static"
   	fi
   	# Get channel data from persistent key
   	KEYNAME="/HOSTS/$hostNameSys/control/channel-Source"; read_etcd_global
   	channelData="$printvalue"
   	if [[ -z "$channelData" ]]; then
   		echo "	Warning: No channel-Source data found, defaulting to channel 0"
   		channelData="0-1"
   	fi
   	channelIndex="${channelData%%-*}"
   	channelSourceHash="${channelData##*-}"
   	echo "		Previous video source is on channel: $channelIndex with source hash: $channelSourceHash (type: $videoSourceType)"
   	controlPortCmd="capture.data 2"; netCat "6161" "$controlPortCmd"
   	sleep 15
	controlPortCmd="capture.data $channelIndex"; netCat "6161" "$controlPortCmd"
}
event_prefix_set(){
	# Switches the type designator under /hostLabel/$(hostname)/type
	# This is now checking and modifying the local host's /type key from what was set in the UI.
		if [[ "$hostType" = "dec" ]]; then
			echo "      I am currently a decoder, switching to an encoder"
			KEYNAME="/HOSTS/$hostNameSys/type"; KEYVALUE="enc"; write_etcd_global
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
			# launch encoder process and ensure we have the proper blank image available
			notifyID="$(notify-send -h string:x-mako-align:center "Currently Running Encoder Process")"
			echo "$notifyID" > /var/home/wavelet/config/notifyID
			event_encoder
		else
			echo "      I am not a decoder, switching to become a decoder.."
			KEYNAME="/HOSTS/$hostNameSys/type"; KEYVALUE="dec"; write_etcd_global
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
		exit 1
	fi
}
# Promotion functionality
event_promote(){
	KEYNAME="/HOSTS/$hostNameSys/type"; read_etcd_global
	hostType="$printvalue"
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
	local swaySocket; local width; local height; local displayResolution; local noDecoderWindow
	swaySocket="$(ls "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/sway-ipc.*.sock 2>/dev/null | xargs -I{} sh -c 'swaymsg -s {} -t get_tree >/dev/null 2>&1 && echo {}')"
    [[ -z "$swaySocket" ]] && swaySocket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
	if [[ "$etcdValue" == 0 ]] || [[ -z "$etcdValue" ]]; then
		echo "	Disabling UI functionality on this device.."
		notify-send -e "UI Disabled"
		rm -rf "/var/home/wavelet/config/webui.enabled"
        workspace=""
		systemctl --user disable wavelet_ui.service --now --no-block
        if [[ "$hostNameSys" == *"svr" ]]; then
        	echo "	This is the server, setting workspace to 1."
        	workspace=1
        	noDecoderWindow=true
        else
        	echo "	This is a client, setting workspace to 2."
        	workspace=2
        fi
		local timeout=30
		swaymsg -s "$swaySocket" workspace "$workspace"
        while ! swaymsg -t get_tree -s "$swaySocket" | jq -e '.nodes[] | select(.name? == "2")' >/dev/null 2>&1; do
            sleep 0.1
            timeout=$((timeout - 1))
            [[ $timeout -le 0 ]] && break
        done
        if [[ "$workspace" != 1 ]] && [[ $noDecoderWindow == false ]]; then
        	swaymsg -s "$swaySocket" "[app_id=\"uv\"] move container to workspace $workspace"
        	displayResolution="$(swaymsg -t get_outputs -s "$swaySocket" | jq -r '.[] | select(.active == true) | "\(.rect.width)x\(.rect.height)"' | head -n1)"
			width="${displayResolution%x*}"
			height="${displayResolution#*x}"
			echo "	Got display resolution width: $width and height: $height"
        	swaymsg -s "$swaySocket" "[app_id=\"uv\"] resize set $width $height, fullscreen enable"
        fi
	else
		echo "	Enabling Web interface on this host.  Recommend kb/mouse as Human Interface Device!"
		workspace=""
		if [[ "$hostNameSys" == *"svr"* ]]; then
			elapsedBootTime="$(uptime | awk '{print $3}')"
			if [[ $elapsedBootTime -lt 3 ]]; then
			# Sleep until everything has a chance to settle
			sleep 4
			workspace=2
			fi
		else
			workspace=3
		fi
        systemctl --user enable wavelet_ui.service --now --no-block
		notify-send -e "UI Enabled"
		echo "$workspace" > "/var/home/wavelet/config/webui.enabled"
        swaymsg -s "$swaySocket" workspace "$workspace"
        while ! swaymsg -t get_tree -s "$swaySocket" | jq -e '.nodes[] | select(.name? == "3")' >/dev/null 2>&1; do
            sleep 0.1
            timeout=$((timeout - 1))
            [[ $timeout -le 0 ]] && break
        done
        # Ensure the UltraGrid window (if exists) and the firefox window are moved to our workspace
        swaymsg -s "$swaySocket" "[app_id=\"uv\"] floating enable, fullscreen disable"
        swaymsg -s "$swaySocket" "[app_id=\"uv\"] resize set 495 270, move container to workspace $workspace, move container to position 1400 0"
		swaymsg -s "$swaySocket" "[app_id=\"firefox\"] move container to workspace $workspace"
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
		peerInfo="$(< /var/home/wavelet/config/screencast/device.connected)"
		KEYNAME="/HOSTS/$hostNameSys/control/screencastRequest"; KEYVALUE="$peerInfo"; write_etcd_global &
		rm -f /var/home/wavelet/config/screencast/device.connected
		# authorize_screencast() is invoked later by the /control/authScreencast key path.
		# Listen for connections, when connection detected a local flag is written
		until [[ -f "/var/home/wavelet/config/screencast/device.connected" ]]; do
			sleep .1
		done
		KEYNAME="/HOSTS/$hostNameSys/controls/screencastRequest"; KEYVALUE="screenCastDevice"; write_etcd_global &
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
	echo "	Hosts in group:"
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
   	local KEYNAME; local KEYVALUE; local printvalue
	if [[ -n "${_inputDeviceMap[$etcdValue]:-}" ]]; then
		hostSourceKey="${_inputDeviceMap[$etcdValue]}"
	else
		return 1
	fi
	KEYNAME="$hostSourceKey"; read_etcd_global; hostSourceData="$printvalue"
	hostUIKey="${hostSourceKey%/inputs/*}"
	if [[ "$hostSourceData" == *"NDI"* ]] || [[ "$hostSourceData" == *"RTSP"* ]]; then
		if [[ -z "$printvalue" ]]; then
			KEYNAME="$hostUIKey/IP"; read_etcd_global
			deviceHostName="$printvalue.$(dnsdomainname)"
		fi
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
            local deviceHostName="${_hostNameMap[$hostHash]:-}"
#            local versionKey; versionKey="/HOSTS/$deviceHostName/control/sourceCheckVersion"
#            KEYNAME="$versionKey"; read_etcd_global
            local currentVersion; currentVersion="0"
            if [[ "$directMode" -eq 1 ]]; then
                # Direct NDI mode: keep VIDEO_SOURCE_CMD, set streamMode to subType
				cat >> "$tempTxn" <<-EOF
					put "/HOSTS/$deviceHostName/control/videoSourceType" "network"
					put "/HOSTS/$deviceHostName/control/videoSourceActive" "1"
					put "/HOSTS/$deviceHostName/control/videoSourceSubType" "$decoderSubType"
					put "/HOSTS/$deviceHostName/VIDEO_SOURCE_CMD" "$decoderSubscribecmd"
				EOF
            elif [[ -z "$decoderSubscribecmd" ]]; then
                # No direct subscription: set explicit inactive state
                # Note the video source subtype being "static" doesn't mean a the static image option.
                cat >> "$tempTxn" <<-EOF
					put "/HOSTS/$deviceHostName/control/videoSourceSubType" "static"
					put "/HOSTS/$deviceHostName/control/videoSourceDirect" "0"
					del "/HOSTS/$deviceHostName/VIDEO_SOURCE_CMD"
				EOF
            else
                # We are feeding a network video source through UltraGrid
            	cat >> "$tempTxn" <<-EOF
					put "/HOSTS/$deviceHostName/control/videoSourceType" "ug"
					put "/HOSTS/$deviceHostName/control/videoSourceActive" "1"
					put "/HOSTS/$deviceHostName/control/videoSourceSubType" "ug"
					del "/HOSTS/$deviceHostName/VIDEO_SOURCE_CMD"
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
    KEYDATA="mod(\"/UI/HOSTS/\") = \"0\"

$txnArray

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
		-t 30 -c:v mjpeg -q:v 0 "/var/home/wavelet/http-php/html/images/${staticImageFile}_$groupHash.mp4"
	cat > "${staticImageFile}_$groupHash.sha256" <<- EOF
$(sha256sum < "${staticImageFile}_$groupHash.mp4")
EOF
	KEYVALUE="https://$hostNameSys/images/${staticImageFile}_$groupHash.mp4"
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
	codecCmd="${etcdKey#;*}"
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
	# Generate a new group hash
	# Check that this hash doesn't already exist (REALLY small chance of a collision but.. why not)
	local newGroupHash; newGroupHash="$(sha256sum < /proc/sys/kernel/random/uuid | cut -d ' ' -f1)"
	# Declare vars locally
	local KEYNAME
	local KEYVALUE
	local KEYDATA
	local BASEKEYNAME
	BASEKEYNAME="/UI/GROUPS/$newGroupHash"
	# Create a txn which will complete only if the generated hash doesn't exist
	# the blocks are repeated 2x because this forms an IF;THEN pattern based off the mod("key") = "val" case.
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
put \"$BASEKEYNAME/control/swatchValue\" \"#0f2b39\"

"
	write_etcd_txn "$KEYDATA"
	# Delete the group create request key
	KEYNAME="/UI/control/GROUP-CREATE"; delete_etcd_key_global &
}

event_change_group(){
	# Runs on host
   	KEYNAME="/HOSTS/$hostNameSys/control/GROUP"; read_etcd_global; groupHash="$printvalue"
   	if [[ -z "$groupHash" ]]; then
   		KEYNAME="/HOSTS/$hostNameSys/control/GROUP"; KEYNAME="$etcdValue"; write_etcd_global &
   		exit 0
   	elif [[ "$etcdValue" == "$groupHash" ]]; then
   		echo "      Group value was updated to the same value as current group membership, doing nothing."
   		exit 0
   	fi
   	echo "	Changing client group to hash: $etcdValue"
#   	KEYNAME="/HOSTS/$hostNameSys/control/sourceCheckVersion"; KEYVALUE="$(date +%s)"; write_etcd_global &
   	KEYNAME="/HOSTS/$hostNameSys/control/GROUP"; KEYVALUE="$etcdValue"; write_etcd_global &
}

#delete a group
event_delete_group(){
	# Server only
	echo "      Finding components in specified group.."
	# We also need the hash of the primary group
	# As this is always run on the server, and the server is always in the primary group:
	KEYNAME="/HOSTS/$hostNameSys/control/GROUP"; read_etcd_global; primaryGroupHash="$printvalue"
	if [[ "$etcdValue" == "$primaryGroupHash" ]]; then
		echo "      Cannot delete the primary group!!"
		exit 0
	fi
	KEYNAME="/UI/GROUPS/$primaryGroupHash"; read_etcd_prefix_list; primaryGroupKeys="$printvalue"
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
	echo "		Group deleted!"
	# SSE should pick up the changes
}

get_ipValue(){
	# Gets the current IPv4 address for this host from active ethernet/wifi connections
	# Prioritizes wired connections, falls back to wifi if no wired connection active
	local ipValue; local connectionName; local connType
	# First try to get IP from active wired (ethernet) connection
	while read -r uuid; do
		connType=$(nmcli -g connection.type con show "$uuid")
		if [[ "$connType" == "802-3-ethernet" ]]; then
			connectionName=$(nmcli -g connection.id con show "$uuid")
			ipValue=$(nmcli -g IP4.ADDRESS con show "$uuid" | head -n1 | cut -d'/' -f1)
			if [[ -n "$ipValue" && "$ipValue" != "--" ]]; then
				echo -e "			Found active wired connection \"$connectionName\" with IP: $ipValue"
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
				ipValue=$(nmcli -g IP4.ADDRESS con show "$uuid" | head -n1 | cut -d'/' -f1)
				if [[ -n "$ipValue" && "$ipValue" != "--" ]]; then
					echo -e "			Found active wireless connection \"$connectionName\" with IP: $ipValue"
					break
				fi
			fi
		done < <(nmcli -g UUID con show --active)
	fi
	# Validate the IP address
	if [[ -z "$ipValue" || "$ipValue" == "--" ]]; then
		echo -e "			No valid IP address found, sleeping and retrying...\n"
		sleep .25
		get_ipValue
		return
	fi
	if valid_ipv4 "$ipValue"; then
		echo -e "			IP Address is valid: $ipValue, continuing.."
		KEYNAME="/HOSTS/$hostNameSys/IP"; KEYVALUE="$ipValue"; write_etcd_global &
	else
		echo -e "			IP Address '$ipValue' is not valid, retrying...\n"
		sleep .25
		get_ipValue
	fi
}

get_ipValue_quick(){
	ipValue="$(hostname -I | xargs)"
	KEYNAME="/HOSTS/$hostNameSys/IP"; KEYVALUE="$ipValue"; write_etcd_global &
}

# Replaces wavelet_run.sh
wavelet_run(){
	# Detect_self in this case relies on the etcd type key
    # firstRunState="$1"
	local printvalue
	echo "	etcd Value is: $etcdValue"
	KEYNAME="/HOSTS/$hostNameSys/type"; read_etcd_global
	case "$printvalue" in
		enc*) 					event_encoder
		;;
		decX.*)					echo -e  "	    I am a Decoder, but my hostname is generic.\n	An error has occurred at some point, and needs troubleshooting.\nTerminating process.\n"; exit 0
		;;
		dec*)					run_decoder
		;;
		svr*)					run_server
		;;
		*) 						echo -e "	    This device Hostname is not set appropriately, exiting\n"; exit 0
		;;
	esac
}

run_server(){
	# Check for input devices
	KEYNAME="/HOSTS/$hostNameSys/INPUT_DEVICE_PRESENT"; read_etcd_global
	if [[ "$printvalue" -eq 1 ]]; then
		echo "	An input device is present on this server, proceeding"
		# Is this input on this host?
		KEYNAME="/UI/HOSTS/$thisHostHash/inputs/"; read_etcd_prefix_keys
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
		echo "      No detectable input devices are present on this server."
		echo "      The server will handle only primary group streaming and system coordination tasks."
	fi
}

check_ndiDirectMode() {
	# Interrogate the selected device hash to see if its parent host is in directMode.  If so, we start a UG encoder stream.
	if [[ -z "${_inputDeviceMap[$etcdValue]:-}" ]]; then
		echo "	Input device $etcdValue not found in cache."
		exit 0
	fi
	local hostKey="${_inputDeviceMap[$etcdValue]}"
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
		# The NDI device is in direct mode and we shouldn't do anything more.
		exit 0
	else
		# We regenerate our encoder process and handle this as an UltraGrid input
		if [[ -n "$targetHostName" ]]; then
			KEYNAME="/HOSTS/$targetHostName/uv_encode_cmd/inputStream"; read_etcd_global
			echo "		NDI Device set to indirect mode!  Adding UltraGrid encoder argument (base64): $printvalue"
			event_encoder "$printvalue"
		fi
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
	if [[ -z "$groupHash" ]]; then
		KEYNAME="/HOSTS/$hostNameSys/control/GROUP"; read_etcd_global; groupHash="$printvalue"
	fi
	"$WAVELET_ENCODER_MOD" "inputHash=$etcdValue" "groupHash=$groupHash" "netDevIngest=$1" &
}

check_reflector_subscription(){
	# Reflector subscription logic
	KEYNAME="/HOSTS/$hostNameSys/control/previousVideoSourceKey"; read_etcd_global; previousVideoSourceValue="$printvalue"
	KEYNAME="/UI/GROUPS/$groupHash/control/currentVideoSourceKey"; read_etcd_global; currentVideoSourceHash="${printvalue%%-*}"
	if [[ "$streamMode" == "ug" ]]; then
		echo "		Moving to an UltraGrid source, sending reflector subscription request!"
		KEYNAME="/HOSTS/$hostNameSys/reflectorRequest"; KEYVALUE="$etcdValue"; write_etcd_global &
	else
		echo "		Moving to a non-UltraGrid source, sending a reflector unsubscribe request!"
		# TODO - Implement a "Switching Video Source" blank image
		KEYNAME="/HOSTS/$hostNameSys/control/unsubRequest"; KEYVALUE="$previousVideoSourceValue"; write_etcd_global &
		return 0
	fi
	get_ipValue_quick

	if [[ -z "$currentVideoSourceHash" ]]; then
		# This is technically an error state.
		# Assume everything is brand new, no reflector and static image by default.
		previousVideoSourceValue=1
	fi
	# We should have a source hash for our previous input
	if [[ "$previousVideoSourceValue" =~ ^[0-3]$ ]] || [[ "$etcdValue" == "$previousVideoSourceValue" ]]; then
		echo "		Moving from static video source or previous source is the same as current source."
	else
		# Is the previous source value an UltraGrid reflector?
		KEYNAME="/HOSTS/$hostNameSys/control/previousVideoSourceType"; read_etcd_global
		echo "		Previous video source type: $printvalue"
		if [[ "$printvalue" == "ug" ]]; then
			echo "		Previous video source is an UltraGrid source, checking reflector data"
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
				echo "		Reflector host set to null!"
				echo "" > /var/home/wavelet/config/previousReflectorHost
			fi

			if [[ "$previousReflectorHost" == "$printvalue" ]]; then
				echo "		Reflector host $previousReflectorHost the same as $printvalue, continuing.."
			else
				echo "		Reflector host has changed, issuing unsubscribe request.."
				KEYNAME="/HOSTS/$hostNameSys/control/unsubRequest"; KEYVALUE="$previousVideoSourceValue"; write_etcd_global &
				KEYNAME="/HOSTS/$hostNameSys/control/currentUGReflectorHost"; delete_etcd_key_global &
			fi
		else
			echo "		previous source was NOT an UltraGrid reflector.."
		fi
	fi
}

run_decoder(){
	# Begins the decoder process
	# On run, the decoder should be able to lookup the primary video source for the group it resides within.
	# On UltraGrid sources, this means joining a reflector in order to get a video stream
	ugName="UltraGrid.Decoder.service"
	ugPath="/var/home/wavelet/.config/systemd/user"
	staticImageFile="/var/home/wavelet/config/staticImage.mp4"
	blankImageFile="/var/home/wavelet/config/blankImage.bmp"
	local printvalue; local display; local ugArgs; local tries; local inputs; local display; local audio; local command
	local keyValue; local blankStatus
	local streamMode; local externalArg; local videoSourceCmd; local videoSourceType; local videoSourceSubType
	blankStatus=0
	KEYNAME="/HOSTS/$hostNameSys"; read_etcd_prefix_list; thisHostKeys="$printvalue"
	exec 3<<<"$thisHostKeys"
	while read -u 3 -r line; do
		if [[ "$line" == "/HOSTS/$hostNameSys/control/blankStatus" ]]; then
			read -u 3 -r keyValue || keyValue=""
			if [[ "$keyValue" == "1" ]]; then
				echo "	Blank is ON"
				blankStatus=1
			fi
		fi
		if [[ "$line" == "/HOSTS/$hostNameSys/control/GROUP" ]]; then
			read -u 3 -r keyValue || keyValue=""
			if [[ -z "$keyValue" ]]; then
				echo "      This host has no group membership defined.  Something is broken.  Attempting to revert decoder to Primary group.."
				KEYNAME="/UI/PRIMARY"; read_etcd_global; groupHash="$printvalue"
				KEYNAME="/HOSTS/$hostNameSys/control/GROUP"; KEYVALUE="$printvalue"; write_etcd_global &
				run_decoder
				exit 0
			else
				groupHash="$keyValue"
			fi
		fi
		if [[ "$line" == "/HOSTS/$hostNameSys/control/videoSourceSubType" ]]; then
			read -u 3 -r videoSourceSubType
		fi
		if [[ "$line" == "/HOSTS/$hostNameSys/control/videoSourceType" ]]; then
			read -u 3 -r videoSourceType
		fi
	done <&3
	exec 3<&-

	if [[ -n "${firstRunState:-}" ]]; then
		echo "      Decoder first run, grabbing group $groupHash video source"
		KEYNAME="/UI/GROUPS/$groupHash/control/sourceHash"; read_etcd_global
		etcdValue="$printvalue"
		if [[ -z "$etcdValue" ]]; then
			# default to splash
			etcdValue=1
		fi
	fi
	echo "	Video Source Subtype: $videoSourceSubType"
   	if [[ "$etcdValue" =~ ^[0-3]$ ]]; then
   		# Static image - no subscription needed
   		streamMode="static"
   		channel="$etcdValue"
   	elif [[ "$videoSourceSubType" == "NDI" ]] || [[ "$videoSourceSubType" == "RTSP" ]]; then
   		# We should have a video source command
   		videoSourceCmd=$(grep -A1 "/HOSTS/$hostNameSys/VIDEO_SOURCE_CMD" <<<"$thisHostKeys" | tail -n1 | base64 -d)
   		if [[ -z "$videoSourceCmd" ]]; then
   			# Fallback to etcd read (slower)
   			KEYNAME="/HOSTS/$hostNameSys/VIDEO_SOURCE_CMD"; read_etcd_global
   			if [[ -z "$printvalue" ]]; then
   				KEYNAME="/HOSTS/$hostNameSys/OLD_VIDEO_SOURCE_CMD"; read_etcd_global
   			fi
   			videoSourceCmd="$(base64 -d <<<"$printvalue")"
   		fi
  		echo "	Checking video source type: $videoSourceCmd (explicit type: $videoSourceType)"
		case "$videoSourceCmd" in
  			*ndi*)
  				externalArg+=("-t ug_input:5004")
   				externalArg+=("$videoSourceCmd")
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
   				# Unknown type, fall back to UG
   				streamMode="ug"
   				channel="4"
   				externalArg+=("-t ug_input:5004")
   				externalArg+=("-t ndi")
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
	if [[ -f "/var/home/wavelet/config/webui.enabled" ]]; then
		display="-d vulkan:keep-aspect:driver=wayland:size=640x360:nodecorate:tearing:hint=SDL_HINT_VIDEO_WAYLAND_PREFER_LIBDECOR=1"
		export SDL_HINT_VIDEO_WAYLAND_MODE_EMULATION=0          # disable mode switching
		export SDL_HINT_VIDEO_WAYLAND_SCALE_TO_DISPLAY=0        # don't scale to full display
		export SDL_HINT_VIDEO_WAYLAND_WINDOW_MODE=windowed      # force windowed mode
	else
		display="-d vulkan:driver=wayland:nodecorate:nocursor:tearing:fs"
	fi
	ugArgs=()
#	ugArgs+=("--tool uv") # required for AppImage
	ugArgs+=("${inputs[@]}")
	ugArgs+=("$display")
	ugArgs+=("${audio:-}")
	ugArgs+=("--control-port 6161")
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
	# Update IP
	ipFile="/home/wavelet/config/systemIP"
	currentIP="$(hostname -I | xargs)"
	if [[ "$currentIP" != "$(cat $ipFile)" ]]; then
		echo "$currentIP" > "$ipFile"
		KEYNAME="/HOSTS/$hostNameSys/IP"; write_etcd_global &
	fi
	# check for an already running UG systemd unit
	if systemctl --user is-active UltraGrid.Decoder.service >/dev/null 2>&1; then
		if [[ "$(cat "$ugPath/$ugName")" == *"${externalArg[*]}"* ]]; then
			echo "		UGArgs match existing service, no regeneration needed"
		else
			# echo "		UGArgs do not match existing service, regeneration needed"
			regenerate_decoder_ugUnit
		fi
		# Proceed to setting the channel index since we have a running UG service.
	else
		regenerate_decoder_ugUnit
	fi
	# We need to set the channel index regardless
	if [[ "$blankStatus" -eq 1 ]]; then
		# we will always set channel = 3
		echo "	Blank is enabled, setting blank display and updating host channel-source control key with: $channel-$etcdValue"
		KEYNAME="/HOSTS/$hostNameSys/control/channel-Source"; KEYVALUE="$channel-$etcdValue"; write_etcd_global &
		channel=3
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
	echo -e "		Writing host previous video source key: $etcdValue"
	# This key tracks state so we know what to revert to if reveal/blank are enabled then turned off.
	KEYNAME="/HOSTS/$hostNameSys/control/channel-Source"; KEYVALUE="$channel-$etcdValue"; write_etcd_global &
	KEYNAME="/HOSTS/$hostNameSys/control/previousVideoSourceKey"; KEYVALUE="$etcdValue"; write_etcd_global &
	KEYNAME="/HOSTS/$hostNameSys/control/previousVideoSourceType"; KEYVALUE="$streamMode"; write_etcd_global &
}

regenerate_decoder_ugUnit(){
	# Regenerates and starts the decoder display UG unit.
	# Check for existing input files
	if [[ ! -f $blankImageFile ]] || [[ ! -f $staticImageFile ]]; then
		regenerate_staticImage
		regenerate_blankImage
	fi
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
	KEYNAME="/HOSTS/$hostNameSys/control/GROUP"; read_etcd_global; groupHash="$printvalue"
	KEYNAME="/UI/GROUPS/$groupHash/control/staticImage"; read_etcd_global
	echo "        Downloading static image video loop for local playback from $printvalue.."
	# We just grab the mp4 loop direct from the webserver URL, including the sha256 hash
	until [[ attempt -gt 3 ]]; do
		wget -O "/var/home/wavelet/config/staticImage.mp4" "$printvalue"
		wget -O "/var/home/wavelet/config/staticImage.sha256" "${printvalue%.mp4}.sha256"
  		serverCheckSum="$(cat "/var/home/wavelet/config/staticImage.sha256")"
		localCheckSum=$(sha256sum "/var/home/wavelet/config/staticImage.mp4" | cut -d' ' -f1)
		if [[ "$localCheckSum" != "$serverCheckSum" ]]; then
	  		echo "	ERR: static image hash mismatch!"
	  		(( attempt++ ))
	  		regenerate_staticImage
	  	else
	  		KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="OK: Static image updated"
	  		write_etcd_global &
	  		echo "	$KEYVALUE"
	  	fi
	done
	if [[ $attempt -eq 3 ]]; then
		errorStatus="ERR: Unable to update static image selection, hash mismatch!"
		KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="$errorStatus"; write_etcd_global &
		echo "	$errorStatus"
	fi
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
	-t 10 -c:v mjpeg -q:v 0 /var/home/wavelet/config/blankImage.mp4
  KEYNAME="/HOSTS/$hostNameSys/control/updateImage"; delete_etcd_key_global &
}

start_ug(){
	# Populates the UltraGrid.service
	# ug_args comes from run_decoder
	# The service requires systemd WATCHDOG=1 signals to continue running
	# These are generated by the wrapper script based off the UG executable's log output.
	# The unit is tuned to be very "impatient" so as to minimize video output disruption.
	local targetFile
	if [[ -f /var/wavelet_ramfs/wavelet_ug_wrapper.sh ]]; then
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
		echo "		No hosts located in group!  This could indicate an issue, or just the creation of a new group"
	fi
}

netCat(){
    # Simple function to submit data to netcat
    local port="${1:-6161}"
    local controlPortCmd="${2:-$controlPortCmd}"
    echo "Port: $port, Command: $controlPortCmd"
    response=$(nc 127.0.0.1 "$port" <<<"$controlPortCmd");
    if [[ "$response" != *"200 OK"* ]]; then
    	echo "	Control Port exception: $response"
    fi
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
etcdValue="${ETCD_WATCH_VALUE//\":-}"
if [[ "$etcdValue" == \"*\" ]]; then
	etcdValue="${etcdValue#\"}"
	etcdValue="${etcdValue%\"}"
fi
etcdKey="${ETCD_WATCH_KEY//\":-}"
if [[ "$etcdKey" == \"*\" ]]; then
	etcdKey="${etcdKey#\"}"
	etcdKey="${etcdKey%\"}"
fi

case "$@" in
	*SVR*)	detect_operation_server;;
	*HOST*)	detect_operation;;
	*RUN*)	firstRunState="true"; touch /var/home/wavelet/config/firstrun_token; wavelet_run;; # This is the initial encoder setup so we must ensure videoSource is set
esac