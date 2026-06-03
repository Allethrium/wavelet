#!/bin/bash
# Encoder launcher
# generates a systemd --user unit file for the UG AppImage with the appropriate command lines
# Everything else is handled from wavelet_detectv4l.sh and other sources
# It concatenates any available local input devices into a switcher command line and intelligently launches them.

trap 'stop_timer' EXIT

# By the time this module is called, there should already be validation that an encoder task is supposed to be running!

# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
ETCDINTERACTIONHOOKS=""
if [[ -f "/var/wavelet_ramfs/etcd_interaction_hooks.sh" ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source "/usr/local/bin/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/usr/local/bin/etcd_interaction_hooks.sh"
fi

WAVELET_REFLECTOR_MOD=""
if [[ -f "/var/wavelet_ramfs/etcd_interaction_hooks.sh" ]]; then
	WAVELET_REFLECTOR_MOD="/var/wavelet_ramfs/wavelet_reflector.sh"
else
	WAVELET_REFLECTOR_MOD="/usr/local/bin/wavelet_reflector.sh"
fi


#load_cpu_affinity_settings() {
#	# Load pre-configured CPU affinity settings from installer
#	if [[ -f /etc/wavelet/ultragrid_cpu_affinity ]]; then
#		CPU_AFFINITY_SETTINGS=$(cat /etc/wavelet/ultragrid_cpu_affinity)
#	else
#		CPU_AFFINITY_SETTINGS="# No CPU affinity restrictions"
#	fi
#}

detect_input_present(){
	# Before we do anything, once again we check that we have an input device present.
	KEYNAME="/HOSTS/$hostNameSys/INPUT_DEVICE_PRESENT"; read_etcd_global
		if [[ "$printvalue" -eq 1 ]]; then
			echo -e "	$(date): An input device is present on this host, continuing.. \n"
		else
			if [[ "$hostNameSys" == *"svr"* ]]; then
				echo -e "	This is the wavelet server, continuing.."
			else
				echo -e "	No input devices, and not a server, encoder shouldn't be running on this host."
				echo "	Attempting device redetection anyway.."
				/usr/local/bin/wavelet_detectv4l.sh "redetect"
				exit 0
			fi
		fi
	read_uv_hash_select
}

read_uv_hash_select() {
	# The encoder should be looking for sourceHash in its assigned group.
	KEYNAME="/UI/GROUPS/$groupHash/control/sourceHash";	read_etcd_global; groupInputHash="$printvalue"
	case "$groupInputHash" in
	0)
		echo "	Blank Screen activated, clients will handle this locally."
		exit 0
		;;
	1)
		echo "	Static Image activated, clients will handle this locally."
		exit 0
		;;
	2)
		echo "	Testcard generation activated, clients will handle this locally."
		exit 0
		;;
	3)	echo "	Blank activated, clients will handle this locally."
		exit 0
		;;
	*)	echo "	Dynamic input device."
		test_newDevice
		;;
	esac
}

test_newDevice(){
	# Check to see if our host device update flag has been modified.
	if [[ -n "$networkDeviceInput" ]]; then
		generate_local_args
	fi
	KEYNAME="/HOSTS/$hostNameSys/INPUT_DEVICE_NEW"; read_etcd_global
	if [[ "$printvalue" == "1" ]]; then
		echo "	New input flag set, regenerating UltraGrid Encoder systemD unit.."
		generate_local_args
	else
		# verify everything is in the systemD unit as it should be, and set channel index
		device_cmdline="$(cat "$deviceMapFile")"
		if [[ "$(cat /var/home/wavelet/.config/systemd/user/UltraGrid.Encoder.service)" == *"$device_cmdline"* ]]; then
			set_channelIndex
		else
			generate_local_args
		fi
	fi
}

generate_local_args(){
	# Generates correct arguments for the encoder systemd unit
	KEYNAME=""
	echo "	A device change was registered on this system, running UG service assembly for local, or indirect net devices.."
	# Consume the device flag by resetting it
	KEYNAME="/HOSTS/$hostNameSys/INPUT_DEVICE_NEW"; KEYVALUE="0"; write_etcd_global &
	KEYNAME="inputs/cmd/"; read_etcd_prefix
	local indexInt
	indexInt=0
	sortedLocalDevices=()
	if [[ -n "$printvalue" ]]; then
		# First we need to know what device path matches what command line, so we need a matching array to check against:
		# remove -t, remove preceding space,
		readarray -t localInputsArray <<< "$(echo "$printvalue" | sed 's|-t|\n|g' | cut -d ' ' -f 2 | sed '/^[[:space:]]*$/d')"
		echo "	Local Inputs Array:"
		echo "		${localInputsArray[*]}"
		# Declare the master local inputs array
		declare -A localInputDevices=(); declare -A localInputs=()
		if [[ -z "$indexInt" ]]; then
			# Clear device map file so we start with a blank slate
			echo "" > "$deviceMapFile"
		fi
			for element in "${localInputsArray[@]}"; do
			# Append "-t " to make it a valid UltraGrid command
			if [[ "$element" != *"-t"* ]];then
				# Note the spaces before & after $element!
				element=" -t $element "
			fi
			localInputs[$indexInt]="$element"
			localInputDevices[$indexInt]="$element"
			(( indexInt++ ))
		done
		# Increment index by N devices present in the local inputs array
		localInputsOffset="${#localInputs[@]}"
		echo -e "		$localInputsOffset device(s) in array..\n"
		(( indexInt += localInputsOffset ))
		# Note that here we are appending entries to deviceMapFile!
		mapfile -d '' sortedLocalDevices < <(printf '%s\0' "${!localInputDevices[@]}" | sort -z)
		local newEntries=()
		for i in "${sortedLocalDevices[@]}"; do
			if [[ "${i}" == "-t" ]]; then
				newEntries+=("DEL:$i")
				continue
			fi
			mapEntry="$i,${localInputDevices[$i]},${hostNameSys}"
			# Use awk for faster lookup
			if ! awk -v entry="$mapEntry" '$0==entry{found=1} END{exit !found}' "$deviceMapFile" 2>/dev/null; then
				newEntries+=("ADD:$mapEntry")
			fi
		done
			# Batch all adds and deletes in one go
			if [[ ${#newEntries[@]} -gt 0 ]]; then
				sed -i '/^$i,/d' "$deviceMapFile" 2>/dev/null
				printf '%s\n' "${newEntries[@]#ADD:}" >> "$deviceMapFile"
			fi
	fi
	# Generate the command line proper
	commandLine="$(while IFS= read -r line; do
		echo "$line"
		done <<< "$(for i in "${sortedLocalDevices[@]}"; do
			echo "${localInputDevices[$i]}"
		done)"
	)"
	commandLine="$(echo "$commandLine" | tr -d '\n')"

	if [[ $indexInt -eq 0 ]]; then
		# Clear device map file so we start with a blank slate
		echo "	Clear device map file"
		echo "" > "$deviceMapFile"
	fi
	networkDeviceCmdLine=""
	# If network device was added, map its hash to channel index
	if [[ -n "$networkDeviceInput" ]]; then
		# Network device is at index where we started adding it (after local devices)
		local networkDeviceIndex="${#localInputsArray[@]}"
		# Map: channelIndex, inputHash, hostNameSys
		echo "	Adding network device: $networkDeviceIndex, $networkDeviceCmdLine"
		echo "$indexInt, $networkDeviceCmdLine, netDevIndirect" >> "$deviceMapFile"
		(( indexInt++ ))
		# Append to cmdline
		commandLine="${commandLine} ${networkDeviceCmdLine}"
	fi
#    sed -i -e '/^[[:space:]]*$/d' -e '/^[^,]*,[^,]*,$/{n;d}' "$deviceMapFile" 2>/dev/null
	echo -e "	Generated switcher device list for all local input devices is:\n${sortedLocalDevices[*]}"
	echo -e "	Generated command line input into etcd is:\n		$commandLine\n		Converting to base64 and injecting to etcd.."
	encodedCommandLine="$(base64 -w 0 <<<"$commandLine")"
	KEYNAME="/HOSTS/$hostNameSys/local_encoder_command"; KEYVALUE="$encodedCommandLine"; write_etcd_global &
	# Read the encoder selection, then pull the correct encoder cmdline
	KEYNAME="/UI/GROUPS/$groupHash/control/activeCodec"; read_etcd_global
	KEYNAME="/UI/GLOBALS/CODECS/$printvalue"; read_etcd_global
	encoderVar="${printvalue%%;*}"
	if [[ -n $encoderVar ]]; then
		echo "	Found codec commandline: $encoderVar"
	else
		err="	ERR: No encoder parameters defined!"
		KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="$err"; write_etcd_global
		echo "$err"
		exit 1
	fi
	# We should now have all local input variables populated correctly
	generate_systemd_unit
}

generate_systemd_unit(){
	# Checks for requested device and regenerates the systemD unit if it is not available
	read_banner_status
	# For Audio we will select pipewire here as it seems to do a decent job of finding the current device or providing a null if none.
	audiovar="-s pipewire"
	# If we are running an encoder, we are now (by default) running a reflector also.
	KEYNAME="/HOSTS/$hostNameSys/IP"; read_etcd_global
	destinationipv4="$printvalue"
	# N.B This isn't the same as ethernet MTU.
	UGMTU="9000"
	# Grab our inputVars.
	if [[ "$hostNameSys" = *"svr"* ]]; then
		KEYNAME="/HOSTS/$hostNameSys/server_commands"; read_etcd_global; serverInputvar="$(base64 -d <<<"$printvalue")"
	else
		# Zero that out so nothing will be populated
		unset serverInputvar
	fi
	KEYNAME="/HOSTS/$hostNameSys/local_encoder_command"; read_etcd_global; localInputvar="$(base64 -d <<<"$printvalue")"

	# Check if blankstatus != 1
	KEYNAME="/HOSTS/$hostNameSys/control/blankStatus"; read_etcd_global
#	multiplier=""
#	if [[ "$printvalue" == "0" ]]; then
#		multiplier="-d multiplier:vulkan"
#        echo "		Blank status is 0, adding a video output via multiplier!"
#    fi
	# This is a sparse array, not all values need to be set.
	# Note excl_init so we don't open all the input devices at once.
	commandLine=(\
		[1]="--tool uv" \
		[2]="$filterVar" \
		[3]="--control-port 6162" \
		[4]="-f V:rs:200:250" \
		[11]="-t switcher:excl_init" [21]="$serverInputvar" [22]="$localInputvar" [29]="$audiovar" \
#		[15]="$multiplier"
		[31]="-c $encoderVar" \
		[91]="-P 5004" [92]="-m $UGMTU" [93]="$destinationipv4")
	ugargs="${commandLine[*]}"
	KEYNAME="UG_ARGS"; KEYVALUE="$ugargs"; write_etcd
	local binaryFile
	if [[ -f "/var/wavelet_ramfs/ultragrid/squashfs-root/AppRun" ]]; then
		binaryFile="/var/wavelet_ramfs/ultragrid/squashfs-root/AppRun"
	else
		binaryFile="/usr/local/bin/ultragrid/squashfs-root/AppRun"
	fi
	cat > "/var/home/wavelet/.config/systemd/user/UltraGrid.Encoder.service" <<-EOF
		[Unit]
		Description=UltraGrid AppImage Encoder executable
		After=network-online.target
		Wants=network-online.target

		[Service]
		ExecStart=$binaryFile $ugargs
		KillMode=control-group
		TimeoutStopSec=0.33
		# Performance optimizations (applied from installer config)
		# We drop these for the moment because of permissions issues.
		# CPU_AFFINITY_SETTINGS

		[Install]
		WantedBy=default.target
		EOF
	# Tell Wavelet I am the active encoder
	KEYNAME="/HOSTS/$hostNameSys/ENCODER_ACTIVE"; KEYVALUE="1"; write_etcd_global &
	# Tell wavelet my encoder IP address, which is always my active network connection
	activeConnection="$(nmcli -t -f NAME,DEVICE c s -a | head -n 1)"
	activeConnectionIP="$(nmcli dev show "${activeConnection#*:}" | grep 'ADDRESS' | awk '{print $2}' | head -n 1)"
	KEYNAME="ENCODER_IP_ADDRESS"; KEYVALUE="${activeConnectionIP%/*}"; write_etcd_global &
	systemctl --user daemon-reload
	systemctl --user enable UltraGrid.Encoder.service --now
	echo "	Encoder systemd unit instructed to start.."
	# sequence for streaming:
	# first: vidcap_v4l2_init
	# second: [transmit] FEC symbol size: 41, symbols per packet: 218, payload size: 8938
	# final: [V4L2 capture] 140 frames in 5.00074 seconds = 27.9959 FPS
	# once this sequence has gone through we can be reasonably confident we are streaming video from a v4l2 device
	# note we will need to make additions/mods if we aren't using v4l2 in future, say decklink etc.
	MATCHES=0
	local primedSet
	if timeout 10 journalctl --user -u UltraGrid.Encoder -f 2>/dev/null | \
	   while IFS= read -r line; do
		   case "$line" in
			   *vidcap_v4l2_init) ((new_matches++)) ;;
			   *transmit*FEC*symbol*size*symbols*per*packet*payload*size*) ((new_matches++)) ;;
			   *V4L2*capture]*frames*in*seconds*=*FPS) ((new_matches++)) ;;
		   esac
		   if (( new_matches >= 1 )) && [[ -z $primedSet ]]; then
			   primedSet=1
			   echo "		Encoder primed, setting key.."
			   KEYNAME="/HOSTS/$hostNameSys/control/encoder_primed"; KEYVALUE="1"; write_etcd_global &
		   fi
		   if (( new_matches >= 3 )) && (( primedSet = 1 )); then
			   KEYNAME="/HOSTS/$hostNameSys/control/encoder_ready"; KEYVALUE="1"; write_etcd_global &
			   break
		   fi
	   done; then
		echo "	Multiple UltraGrid log patterns detected, encoder is encoding!"
	else
		# timeout exited non-zero (124 = timed out)
		echo "	Timeout waiting for encoder startup signatures."
		KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="ERR: ENC STARTUP FAILURE"; write_etcd_global &
		exit 1
	fi
	KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="OK: ENC STARTUP SUCCESS"; write_etcd_global &
	echo "	UG Process generated and task started, moving on to setting channel index.."
	set_channelIndex
}

set_channelIndex(){
	# This previously resided in the controller, but makes more sense here.
	# Called after server or client encoder blocks have concatenated and generated their respective device maps and cmdlines
	if [[ ! -f "$deviceMapFile" ]]; then
		echo "	DEBUG: Device map file doesn't exist!"
		echo "	Attempting to regenerate input device map.."
		generate_local_args
		exit 0
	fi

	if [[ "$(cat /var/home/wavelet/.config/systemd/user/UltraGrid.Encoder.service)" != *"$localInputvar"* ]]; then
		echo "	SystemD unit missing local inputs!  Regenerating"
		generate_systemd_unit
	fi

	if [[ "$requestedInputHash" =~ ^[0-2]$ ]]; then
		echo "	Skipping static input processing.."
	else
		local devicePath
		KEYNAME="/HOSTS/$hostNameSys/inputs/devpath_lookup/$requestedInputHash"; read_etcd_global
#	    echo "	Device path lookup result for $requestedInputHash is: $printvalue"
		if [[ -z "$printvalue" ]]; then
			echo "	Device path lookup failure! Continue to fallback for net device.."
			printvalue="netDevIndirect"
		else
			devicePath="$printvalue"
			echo "	Requested input Hash; $requestedInputHash, path; $devicePath"
			if grep -q "$devicePath" "$deviceMapFile" ; then
				channelIndex="$(grep -F "$printvalue" "$deviceMapFile" | cut -d ',' -f1)"
				echo "	Entry found in my device map, with channel index: $channelIndex"
			fi
		fi
	fi

	if [[ -z "$channelIndex" ]]; then
		if grep -q ",$requestedInputHash," "$deviceMapFile"; then
			channelIndex="$(grep -F ",$requestedInputHash," "$deviceMapFile" | cut -d ',' -f1)"
			echo "	Network device mapping found, channel index: $channelIndex"
		else
			echo "	devpath lookup failure! Proceeding to guess (may result in the wrong input being shown)"
			exit 1
		fi
	fi

	# Read the encoder selection, then pull the correct encoder cmdline
	KEYNAME="/UI/GROUPS/$groupHash/control/activeCodec"; read_etcd_global
	if [[ -z "$printvalue" ]]; then
		printvalue="libaom-av1"
	fi

	# Get the encoder settings string
	KEYNAME="/UI/GLOBALS/CODECS/$printvalue"; read_etcd_global
	encodervar="${printvalue%%;*}"
	echo "	Found codec commandline: $encodervar"
	if [[ "$(cat /var/home/wavelet/.config/systemd/user/UltraGrid.Encoder.service)" == *"$encodervar"* ]]; then
		echo "	Codec has not changed.."
	else
		generate_systemd_unit
	fi

	echo "	Switching encoder to channel ${channelIndex%,*}"
	response="$(nc -w 1 127.0.0.1 6162 <<<"capture.data ${channelIndex%,*}")" &
	echo "	Task complete with response code: $response"
	exit 0
}

read_banner_status(){
	# Reads Filter settings, should be banner.pam most of the time
	# If banner isn't enabled filterVar will be null, as the logo.c file can result in crashes with RTSP streams and some other pixel formats.
	KEYNAME="/UI/GROUPS/$groupHash/control/bannerStatus"; read_etcd_global; bannerStatus="$printvalue"
	echo -e "		Banner status is: $bannerStatus"
	if [[ "$bannerStatus" -eq 1 ]]; then
		echo "		Banner is enabled, so filterVar will be set appropriately."
		echo "		Note currently the logo.c file in UltraGrid can generate errors on particular kinds of streams!"
		bannerTextGenerator
		KEYNAME="uv_filter_cmd"; read_etcd_global
		filterVar="$(base64 -d <<<"$printvalue")"
		echo "	filterVar is: $filterVar"
		if [[ "$filterVar" == "--capture-filter" ]]; then
			echo "filterVar has an illegal or incomplete command, unsetting.."
			unset filterVar
		fi
	else
		echo -e "	Banner is not enabled, so filterVar will be set to NULL..\n"
		unset filterVar
	fi
}

bannerTextGenerator(){
	# Replaces wavelet_textgen.sh
	KEYNAME="/UI/GROUPS/$groupHash/control/liveStreamStatus"; read_etcd_global
	if [[ "$printvalue" -eq 1 ]]; then
		lsflag=':  Livestreaming Enabled'
		color="rgba(255, 0, 0, 0.2)"
		backgroundcolor="rgba(255, 0, 0, 0.3)"
	else
		lsflag=''
	fi
	KEYNAME="/UI/GROUPS/$groupHash/control/bannerContent"; read_etcd_global
	filterselection="$printvalue"
	color="rgba(65, 105, 225, 0.2)"
	backgroundcolor="rgba(45, 85, 205, 0.3)"
	filter_is_livestreaming
	filter="○ $filterselection $lsflag"
	# We MUST generate a BMP - generating a PNG or other format does horrible things when converted to PAM.
	# working colorspace sRGB
	magick -size 600x50 \
		--pointsize 30 \
		-background "$color" \
		-bordercolor "$backgroundcolor" \
		-border 1 \
		-gravity West \
		-fill white label:"%-  $filter" \
		-colorspace sRGB /home/wavelet/banner.bmp
	mogrify -format pam /home/wavelet/banner.bmp
	echo "	Banner.pam generated for value $filter"
	KEYNAME="/HOSTS/$hostNameSys/bannerCmd"; KEYVALUE="$(base64 <<<'--capture-filter logo:/home/wavelet/banner.pam:25:25')"; write_etcd_global
}

cleanUpStatusKeys(){
	# Cleans the encoder key signals on exit
    KEYNAME="/HOSTS/$hostNameSys/ENCODER_ACTIVE"; delete_etcd_key_global  &
    KEYNAME="/HOSTS/$hostNameSys/control/encoder_primed"; delete_etcd_key_global  &
    KEYNAME="/HOSTS/$hostNameSys/control/encoder_ready"; delete_etcd_key_global  &
    # We don't know if this is an "OK" situation.
    KEYNAME="/HOSTS/$hostNameSys/control/healthStatus"; KEYVALUE="OK: ENCODER STOP"; write_etcd_global &
}

#####
#
# Main
#
#####


start_timer
exec >/var/home/wavelet/logs/encoder.log 2>&1
trap 'cleanUpStatusKeys; stop_timer "$timer_id_out"; echo "Total: ${timer_duration}s" >&2' EXIT

deviceMapFile="/var/home/wavelet/device_map"
hostNameSys="$(hostname)"
requestedInputHash=""
groupHash=""
networkDeviceInput=""

for i in "$@"; do
	case "$i" in
		*inputHash=*)
			requestedInputHash="${i#*=}";
			;;
		*groupHash=*)
			groupHash="${i#*=}";
			;;
		*netDevIngest=*)
			networkDeviceInput="${i#*=}";
			;;
	esac
done

#hostNamePretty="$(hostnamectl --pretty)"
exec >/var/home/wavelet/logs/encoder.log 2>&1
# Get this hosts group hash

if [[ -n "$networkDeviceInput" ]]; then
	echo "	Network device input provided!"
	KEYNAME="/HOSTS/$hostNameSys/NETWORK_DEVICE_INPUT"; KEYVALUE="$networkDeviceInput"; write_etcd_global &
	networkDeviceCmdLine="$(base64 -d <<<"$networkDeviceInput")"
else
	unset networkDeviceInput
	KEYNAME="/HOSTS/$hostNameSys/NETWORK_DEVICE_INPUT"; delete_etcd_key_global &
fi

# All encoders imply a reflector
# Check to see if reflector service exists, init if no.
echo "	Checking for reflector process.."
if [[ ! -f "/var/home/wavelet/.config/systemd/user/UltraGrid.Reflector.service" ]]; then
	echo "	Running reflector initialization.."
	"$WAVELET_REFLECTOR_MOD" "INIT" &
fi

detect_input_present