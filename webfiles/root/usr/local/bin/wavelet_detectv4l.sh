#!/bin/bash


# Upon the connection of a new USB device, this script is called by systemd template service from Udev rules.  
# It will attempt to make sense of available v4l devices and update etcd
# The WebUI updates, and is updated from, many of these keys.
# Note that detectv4l handles only local USB devices.
# Network devices are handled through network_sense (called from DHCP hook) and network_device.


# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
ETCDINTERACTIONHOOKS=""
if [[ -f "/var/wavelet_ramfs/etcd_interaction_hooks.sh" ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source "/usr/local/bin/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/usr/local/bin/etcd_interaction_hooks.sh"
fi


find_siblings(){
	# Find siblings from a parent USB device's path
	echo "	Called with $1" >> "$logName"
	local parentDevPath; parentDevPath="$(udevadm info -q path -n "$1")"
	echo "	Detecting devices under USB path: ${parentDevPath}" >> "${logName}"
	local childDevices=()
	for childDev in /dev/video*; do
		if [[ "$(readlink -f /sys/class/video4linux/"${childDev#*/dev/}")" == *"$parentDevPath"* ]]; then
			childDevices+=("$childDev")
		fi
	done
	# If nothing then return
	if [ ${#childDevices[@]} -eq 0 ]; then
		echo "	No child video devices found for USB path ${parentDevPath}" >> "$logName"
		return
	fi
	local result; result="$(processChildDevices 'childDevices' "$parentDevPath")"
	echo "$result"
}

processChildDevices(){
	# here we process all the child devices we discovered from find_siblings
	local parentDevice; local best_score; local best_device; local v4l_device_path
	# local -n childData; childData="$1"
	parentDevice="$2"
	echo -e "\n	Interrogating child devices of ${parentDevice} for compatibility.." >> "$logName"
	goodDevs=()
	for i in "${childDevices[@]}"; do
		# Iterate through our sibling device array
		v4l_device_path="$i"
		output="$(get_formatBlock "$v4l_device_path")"
		if [[ -n "$output" ]]; then
			echo "		Device $v4l_device_path passed test, adding to array.." >> "$logName"
			goodDevs+=("$output")
		else
			echo "		Device $v4l_device_path failed test, discarding.." >> "$logName"
		fi
	done

	if [[ -z "${goodDevs[*]}" ]]; then
		echo "		No video devices found under $parentDevice or none meet requirements." >> "$logName"
		return 1
	fi

	best_score=0

	# Score our returned devices and proceed to generate info for the "best" v4l devNode available
	for i in "${goodDevs[@]}"; do
		IFS=',' read -r path format resolution fps <<< "$i"
		echo "		Scoring ${path} on ${format}, ${resolution} and ${fps}"
		# This arithmetic is VERY fragile.
		score="$(echo "scale=2; (${resolution%x*} * ${resolution#*x}) / 1000 * ${fps}" | bc)"
		score=$(printf "%.0f" "${score}")
		echo "		Device ${i} scored at: ${score}"
		if (( score > best_score )); then
			best_score="$score"
			best_device="$path"
		fi
	done
	# Here we would want to compare the returns from each compatible sibling device, and pick the best.
	# stuff.
	echo -e "\n		Best v4l node for parent device ${parentDevice} is: $best_device, ${resolution}, ${fps}, ${format}\n" >> "${logName}" 
	generate_device_info "${best_device}"
	unset best_score best_device goodDevs
}

check_etcdDuplicates(){
	KEYNAME="/HOSTS/${hostNameSys}/inputs/devpath_lookup"; read_etcd_prefix_global
	if [[ "${printvalue}" == *"${dev}"* ]]; then
		echo "	Device already populated in etcd, (finish, or perform further check to make sure it's still the same device?)" >> "${logName}"
		return 1
	fi
}

function process_device(){
	# helper function to track devices we've already tagged
	# works for both /dev/videoX and the parent dev
	local dev=$1
	if [[ ${seenDevices["$dev"]} ]]; then
		return 0
	fi
	seenDevices["$dev"]=1
	find_siblings "$dev"
}

detect_method(){
	# Finds other devices associated with this device
	if [[ "$function" == "redetect" ]]; then
		echo "Redetecting all potential video devices on the system!"
		# We need to get the parent device ID, then provide it to find_siblings in the appropriate format
		declare -A seenDevices=()
		for dev in /dev/video*; do
			# Get the parent device in the format /dev/bus/usb/003/023
			parentDev="$(dirname "$(readlink -f /sys/class/video4linux/"$(basename "$dev")")" | xargs dirname)"
			# Now get the UDEV DEVNAME of this device
			parentDevName="$(udevadm info -p -a "${parentDev%/*}" 2>/dev/null | grep -Po '(?<=DEVNAME=).*')"
			parentDevs+=("$parentDevName")
		done
		for parentDev in "${parentDevs[@]}"; do
			# Find siblings for each parent device
			process_device "$parentDev"
		done
	else
		# We were populated with a root USB device path, and need to find the child devnodes
		echo "	called to detect single device, proceeding to find siblings.."
		find_siblings "$usbPath"
	fi
}

get_formatBlock() {
	# Find the best pixel format, process the block into something properly formatted and parse forward
	# unset lastLineFormat block_output current_format blockIndex lineIndex
	local output; local current_format; local previous_format; local prevPriority
	local block_output; local lastLineFormat; local formatBlockData
	output="$(v4l2-ctl -d "$1" --list-formats-ext)"
	prevPriority=0
	firstFormat=true
	# test the device for a valid input pixel format (we want MJPG, YUYV or RGB, anything else will probably not work!)
	while IFS=$'\n' read -r line; do
		# Generate the block output ID
		if [[ $line =~  \'([A-Z]{3,4})\' ]]; then
			# If we match 'ABCD', we set current_format and start block_output
			current_format="${BASH_REMATCH[1]//\'/}"
			case "$current_format" in
				*MJPG*)			priority=1000	;;
				*YUYV*)			priority=100	;;
				*RGB*)			priority=10		;;
				*NV12*)			priority=2		;;
				*UYVY*)			priority=1		;;
				*)				priority=0		;;
			esac
			if [[ "$firstFormat" == false ]] && (( prevPriority > priority )); then
				current_format="$previous_format"
				break    # This will skip the rest of this loop iteration completely
			fi
			prevPriority="$priority"
			previous_format="$current_format"
			firstFormat=false

			# Initialize block for this format
			block_output=""
			lastLineFormat="$current_format"
		fi

		# Handle size lines
		if [[ "$line" =~ Size:\ Discrete\ ([0-9]+x[0-9]+) ]]; then
			current_size="${BASH_REMATCH[1]}"
			expecting_interval=true
		elif [[ "$line" =~ Interval:\ Discrete\ ([0-9]+\.[0-9]+)s\ \(([0-9]+\.[0-9]+)\ fps\) ]]; then
			# This is the interval line that follows a size
			if [[ "$expecting_interval" == true ]]; then
#				local interval="${BASH_REMATCH[1]}"
				local fps="${BASH_REMATCH[2]}"
				# Only keep frames with 25fps or higher
				if (( $(echo "$fps >= 25.000" | bc -l) )); then
					block_output+=$'\n'"$current_size,$fps"
				fi
				# Reset for next size
				expecting_interval=false
				current_size=""
			fi
		fi
	done <<<"$output"

	# Output all the resolutions for this pixel format
	if [[ -n "$block_output" && -n "$lastLineFormat" ]]; then
		# If we have a bad pixel format, we should stop here and save ourselves work.
		case "$lastLineFormat" in
			MJPG|YUYV|RGB)			;;
			*) 			return 1;;
		esac
		local sorted_sizes=($(echo "$block_output" | tail -n +2 | sort -g))
		for size in "${sorted_sizes[@]}"; do
			formatBlockData+=$'\n'"$size"
		done
		local resultString
		resultString=$(processFormatBlock "$formatBlockData")
		echo "$resultString"
	fi
	# Clean up
	unset output block_output lastLineFormat formatBlockData
}

processFormatBlock(){
	# gets resolution and FPS from a pre-selected block under a pixel format
	local blockData; local deviceResolution; local devicePixelFormat; local deviceFPS;
	local formatSuccess; local width; local height; local fps; local pxlFormat
	blockData="$1"
	pxlFormat="$current_format"
	# Process sizes in this block
	formatSuccess=1
	while IFS=$'\n' read -r line; do
#		if [[ "$line" =~ ([0-9]{4})x([0-9]{3,}+),([0-9]+\.[0-9]{3}) ]]; then
#			width="${BASH_REMATCH[1]//\'/}"
#			height="${BASH_REMATCH[2]//\'/}"
		if [[ "${line}" =~ ([0-9]+)x([0-9]+),([0-9]+\.[0-9]+) ]]; then
			width="${BASH_REMATCH[1]}"
			height="${BASH_REMATCH[2]}"
			fps="${BASH_REMATCH[3]%.*}"
			if (( "${width}" > "${maxWidth:-0}" )) \
			&& (( "${height}" > "${maxHeight:-0}" )) \
			|| (( "${maxWidth}" == 0 )) \
			&& (( $(echo "$fps >= 30") )); then
				if (( width * 9 == height * 16 )); then
					maxHeight="$height"; maxWidth="$width"
					#bestFormat="$pxlFormat:$width:$height:$fps"
					deviceResolution="${width}x${height}"
					devicePixelFormat="$pxlFormat"
					deviceFPS="$fps"
					formatSuccess=0
					unset width height fps 
				else
					: #nonPrefFormat="$bestFormat"
			fi
			else
				#echo "* ${line%:*} discarded, does not meet resolution, aspect ratio or FPS criteria"
				continue
			fi
		fi
	done <<< "$blockData"
	unset maxHeight maxWidth bestFormat
	if [[ "${devicePixelFormat}" == "" ]]; then
		formatSuccess=1
	fi
	# If anything failed, we return 1 here and stop
		if [[ ${formatSuccess} != 0 ]]; then
			return 1
	else
		echo -e "${v4l_device_path},${devicePixelFormat},${deviceResolution},${deviceFPS}"
	fi
}

generate_device_info() {
	# Called only after the device is validated for sensible input resolutions and pixel formats
	local v4l_device_path; local info; local cardType; local busInfo; local serial
	v4l_device_path="$1"
	echo -e "\nGenerating device data for $v4l_device_path"
	info="$(v4l2-ctl -D -d "$v4l_device_path")"
	# here we parse this information
	cardType="$(echo "$info" | awk -F ':' '/Card type/{print $2 }')"; cardType="$(echo "${cardType/ /}" | sed -e 's/[[:space:]]/_/g')"
	# Bus info (first instance only, it's repeated oftentimes)
	busInfo="$(echo "$info" | awk -F ':' '/Bus info/{print $4;exit;}')"
	# Serial (if exists)
	serial="$(echo "$info" | awk -F ':' '/Serial/{print $2}')"
	# Check to see if this device shares bus_info with any other device
	# If this is the case, we want to ensure we are selecting the most useful output
	# 1) check bus info key, 2) check format string, 3) if betterThan, set priority bit, 4) set checked
	# 5) get priority bit for all items as an array
	# 6) test for highest res/preferred pixelformat
	# 7) delete rest
	# Device string long is the interface key /UI/interface, packed format of:  DEVICELABEL;DEVICE FULL PATH
	deviceLabel="$cardType:USB-$busInfo"
	deviceString="$v4l_device_path/$deviceLabel"
	deviceHash="$(sha256sum <<<"$hostNameSys, $deviceLabel, $serial" | tr -d \"[:space:]-\")"
	echo -e "	Device name is:	$deviceLabel\n	Card type is:	$cardType\n	Bus address:	$busInfo\n	Serial:		${serial:-'null'}"
	echo -e "\n	Device detected settings:\n\n		Resolution:	$resolution\n		Framerate:	$fps\n		Pixel Format:	$format\n"
	# Let's look for the device hash in the /interface prefix to make sure it doesn't already exist!
	# Note that HOSTS can still READ their keys in the UI, but writes are handled via the orchestrator now.
	KEYNAME="/HOSTS/$hostNameSys"; read_etcd_global; hostHash="$printvalue"
	KEYNAME="/UI/HOSTS/$hostHash/inputs/$deviceHash"; read_etcd_global; output_return="$printvalue"
	if [[ "$output_return" == "" ]]; then
		echo -e "	Device Hash: $deviceHash not located within etcd\n	Assuming we have a new device and continuing with process to set parameters.."
		set_device_input
	else
		echo -e "	Device Hash: $deviceHash located in etcd!\n	Returned data:	$output_return\n"
		if [[ "${output_return#*/dev/*}" == *"${v4l_device_path#/dev/*}"* ]]; then
			echo "	Duplicate path detected, device already populated, performing no update"
			exit 0
		else
			device_key_remove "${v4l_device_path}"
			set_device_input
		fi
	fi
	unset cardType bus_info serial info
}

isDevice_input_or_output() {
	# Are we outputting audio/video signals someplace or is this an input?  we determine this here
	case "$deviceString" in
		*BiAmp*)	echo -e "BiAmp HDMI-USB Capture device detected..\n"	&&	echo -e "an audio output selection event would be called here\n"
		;;
		*audio*)	echo -e "Audio out device detected..\n"					&&	echo -e "an audio output selection event would be called here\n"
		;;
		*)			echo -e "Video capture dev.\n"							&&	get_formatBlock
		;;
	esac
}

set_device_input() {
	# called from generate_device_info
	# This function requires data from all of the format query logic.  If something broke, it will try to guess.
	#
	# Because we cannot query etcd by keyvalue, we must create a reverse record in order to clean up
	# This forms a character delimited packed format that we utilize in the PHP module to extract data.
	# This can be modified from the UI, hence we need to track the device by a more immutable hash value elsewhere
	#
	# Packed format:
	#	$HASH -- PARENT_HOSTNAME;DEVICE LABEL;DEVICE_FULLPATH:DEVICE_TYPE
	#
	interfaceEntry="$hostNameSys;$deviceLabel;$deviceString;HOST;USB"
	# This is the master key where the interface looks to generate a new device root node
	# /HOSTS entry must already exist
	BASEKEYNAME="/HOSTS/$hostNameSys"
	KEYDATA="
put $BASEKEYNAME/inputs/$deviceHash \"$interfaceEntry\"
put $BASEKEYNAME/inputs/devpath_lookup/$deviceHash \"$v4l_device_path\"
put $BASEKEYNAME/inputs/hash_lookup$v4l_device_path \"$deviceHash\"
put $BASEKEYNAME/control/inputUpdate \"1\"
put $BASEKEYNAME/INPUT_DEVICE_PRESENT \"1\"

"
	# Ensure INPUT_DEVICE_PRESENT is also available in the conf file
	sed -i 's/export INPUT_DEVICE_PRESENT="0"/export INPUT_DEVICE_PRESENT="1"/' "$configFile"
	write_etcd_txn "$KEYDATA"
	set_device_cmdline
	echo "	Populated keys into Etcd.."
}

device_cleanup() {
	# Check for keys not associated with an active device, and remove them
	local output;
	local input_devices_present=0; # <-- Initialize flag
	KEYNAME="/HOSTS/$hostNameSys/inputs/"
	activeInterfaceDevices=$(read_etcd_prefix_keys | sed "s|/HOSTS/$hostNameSys/inputs/||g")
	IFS=' ' read -a interfaceLongArray <<< "$activeInterfaceDevices"
	unset IFS
	# Pulls a list of all devices registered on this host
	# If found, we run some tests to ensure the device path and/or device output is viable
	# If no, it is removed from the UI.
	for i in "${interfaceLongArray[@]}"; do
		stripHostName="${i#*"$hostNameSys"}"
		devNode="${stripHostName%/*}"
		if [[ -e "$devNode" ]]; then
			echo "	Device path still present, continue to check device details"
			output="$(udevadm info --query=env "$devNode")"
			if [[ -n "$output" ]]; then
				echo "	Device detected, checking strings against etcd data.."
				if echo "$output" | grep -q "SUBSYSTEM=video4linux"; then
					echo "	Device strings found in udev output, device is present."
					input_devices_present=1
				else
					echo "	Device strings are not present in udev output."
					echo "	This means the device has changed, and entries in etcd are no longer valid."
					echo "	Removing.."
					device_key_remove "$devNode"
					interfaceLongArray=("${interfaceLongArray[*]/$i}")
				fi
			else
				echo "	Device detection failed via udev, removing.."
				device_key_remove "$devNode"
				interfaceLongArray=("${interfaceLongArray[*]/$i}")
			fi
		else
			echo "	Device path not present! Removing.."
			device_key_remove "$devNode"
			interfaceLongArray=("${interfaceLongArray[*]/$i}")
		fi
	done
	if (( input_devices_present == 0 )); then
		echo "	No input devices available. Updating config..."
		sed -i 's/export INPUT_DEVICE_PRESENT="1"/export INPUT_DEVICE_PRESENT="0"/' "$configFile"
		KEYNAME="/HOSTS/$hostNameSys/INPUT_DEVICE_PRESENT"; KEYVALUE="0"; write_etcd_global &
	fi
}

set_device_cmdline() {
	# Try a generic, catch-all approach
	# Attempts some optimization for speed/quality
	# note local write, so base64 coded in etcd!
	optimize_device_for_ultragrid "$v4l_device_path"
	KEYNAME="inputs/cmd$v4l_device_path"
	KEYVALUE="-t v4l2:device=$v4l_device_path:codec=$format:size=$resolution:fps=$fps:convert=RGB"
	write_etcd
	# Setting INPUT_DEVICE_NEW notifies the local encoder task on this host to regenerate the systemd unit with new cmdline
	KEYNAME="/HOSTS/$hostNameSys/INPUT_DEVICE_NEW"; KEYVALUE="1"; write_etcd_global
}

optimize_device_for_ultragrid() {
	local device; local caps
    device="$1"
    # We might want to add something regarding exposure settings as i've seen issues on document cameras.
    # Query current device capabilities and optimize accordingly
    caps="$(v4l2-ctl -d "$device" --list-ctrls-menus 2>/dev/null)"
    if echo "$caps" | grep -q "compression_quality"; then
        v4l2-ctl -d "$device" --set-ctrl=compression_quality=100 2>/dev/null || true
    fi
    # Set buffer size if device supports it
    if echo "$caps" | grep -q "buffer"; then
        # Use smaller buffers for lower latency
        v4l2-ctl -d "$device" --set-parm=4 2>/dev/null || true
    fi
    # Set buffer size if device supports it
    if echo "$caps" | grep -q "power_line_frequency"; then
    	# 0 = disabled,1 = 50hz, 2= 60hz
        # IPEVO document camera specific setting - they keep setting to 0 and breaking.
        v4l2-ctl -d "$device" --set-ctrl=power_line_frequency=2 2>/dev/null || true
    fi
    # Log what we optimized
    echo "Applied UltraGrid optimizations to $device" >> "${logName}"
}

detect_self(){
	systemctl --user daemon-reload
	# Detect_self in this case relies on the etcd type key
	if [[ -z "$HOST_TYPE" ]]; then
		KEYNAME="/HOSTS/$hostNameSys/control/type"; read_etcd_global; HOST_TYPE="$printvalue"
	fi
	echo "Host type is: $HOST_TYPE\n"
	case "$HOST_TYPE" in
		"enc")
			echo -e "	I am an Encoder\n"
			encoder_checkNetwork 1
			;;
		"dec")
			echo -e "	I am a Decoder\n"
			exit 0
			;;
		"svr")
		    echo -e "	I am a Server, allowing device sense to proceed.."
		    detect_method "$usbPath"
			;;
		*)
			echo -e "	This device is other, ending process\n"
			exit 0
			;;
	esac
}

encoder_checkNetwork(){
	# Checks for a network connection, without this detection may proceed too quickly and devices may not populate
	if [[ "$1" -gt 3 ]]; then
		echo -e "\nThree repeat tries exceeded, there may be a network configuration issue.  Please troubleshoot\n"
		touch /home/wavelet/config/NETWORK_ERROR_FLAG
		exit 0
	fi
	if ping -c 3 "$SVR_IP"; then
		echo -e "Online and connected to Wavelet Server, continuing..\n"
		detect_method "$usbPath"
	else
		echo -e "No network connection, device registration will be unsuccessful, sleeping for 5 seconds and trying again..\n"
		sleep 5
		(( $1=$1++ ))
		encoder_checkNetwork 
	fi
}

device_key_remove(){
	# This removes a device from the host key range, then notifies the orchestrator.
	local i="$1"
	devPath="$i"
	BASEKEYNAME="/HOSTS/$hostNameSys"
	KEYNAME="$BASEKEYNAME/control/GROUP"; read_etcd_global; currentGroup="$printvalue"
	# find the device hash
	echo -e "	Cleanup device is: $devPath"
	KEYNAME="$BASEKEYNAME/inputs/hash_lookup$devPath"; read_etcd_global; cleanupHash="$printvalue"
	if [[ -n "$cleanupHash" ]]; then
		echo "	Device hash located as: $cleanupHash"
		# Make sure we aren't the current streaming device for our group
		KEYNAME="/UI/GROUPS/$currentGroup/sourceHash"; read_etcd_global; currentSource="$printvalue"
		if [[ "$currentSource" == "$cleanupHash" ]]; then
		    echo "  We are removing the currently streaming device!  Requesting input reset to safe input.."
	    	KEYNAME="/UI/GROUPS/$currentGroup/sourceHash"; KEYVALUE="1"; write_etcd_global &
		fi
		# With safeties done, we can continue to clean up our device keys in /HOSTS/$hostName
		# Note delete_etcd_key takes prefix relative to client, not a global full prefix.
		KEYDATA="
del $BASEKEYNAME/inputs/$cleanupHash --prefix
del $BASEKEYNAME/inputs/cmd$devPath --prefix
del $BASEKEYNAME/inputs/devpath_lookup/$cleanupHash --prefix
del $BASEKEYNAME/inputs/hash_lookup$devPath --prefix
put $BASEKEYNAME/control/inputUpdate \"1\"

"
		write_etcd_txn "$KEYDATA"
		echo "	Notified Orchestrator for input updates to UI.."
	else
		echo "		Requested device key was not found for this host, we do not have a device hash and must perform a partial removal.."
		exit 0
	fi
}

disable_usb_autosuspend(){
	# Disables USB power management, which may interfere and cause frame drops
	USB_DEVICE="$1"
	USB_PATH="/sys/bus/usb/devices/$USB_DEVICE"

	if [[ -d "$USB_PATH" ]]; then
		# Disable autosuspend for this specific device
		echo -1 > "$USB_PATH/power/autosuspend" 2>/dev/null || true
		echo on > "$USB_PATH/power/control" 2>/dev/null || true

		# Also disable for parent hub if it's a video device
		PARENT_PATH=$(dirname "$USB_PATH")
		if [[ -d "$PARENT_PATH" ]]; then
			echo on > "$PARENT_PATH/power/control" 2>/dev/null || true
		fi
	fi
}


#####
#
# Main
#
#####


# Note - this will generate an awfully large number of logs!
logName="/var/home/wavelet/logs/detectv4l.log" 2>&1
#if [[ -e $logName || -L $logName ]] ; then
#	i=0
#	while [[ -e $logName-$i || -L $logName-$i ]] ; do
		(( i++ ))
#	done
#	logName=$logName-$i
#fi

start_timer
trap 'stop_timer "$timer_id_out"; echo "Total: ${timer_duration}s" >&2' EXIT

exec >>"$logName" 2>&1

chown wavelet:wavelet /var/home/wavelet/logs/detectv4l.log
hostNameSys="$(hostname)"

# source conf file variables
configFile="/var/home/wavelet/config/$hostNameSys.conf"
source "$configFile"

# TODO Here get missing data if any, or proceed

for i in "$@"; do
	case "$i" in
		"add"*)
			function="add"; usbPath="$2"; echo -e "\n\nPerforming $function for $usbPath"; detect_self
			# Clean up the generated dropin
			device_path_escaped="${usbPath//\//_}"
			service_pattern="wavelet_v4l_delete@*_${device_path_escaped}.service"
			rm -f "/home/wavelet/.config/systemd/user/$service_pattern"
		;;
		"remove"*)
			function="remove"; v4l_device_path="$2"; echo -e "\n\nPerforming $function for $v4l_device_path"; timestamp="$(date +"%T")"
			machinectl shell wavelet@ "/usr/bin/bash" -c "systemctl --user enable wavelet_v4l_delete@${timestamp}-${2//\//_}.service --now"
			# Clean up the generated dropin
			device_path_escaped="${v4l_device_path//\//_}"
			service_pattern="wavelet_v4l_delete@*_${device_path_escaped}.service"
			rm -f "/home/wavelet/.config/systemd/user/$service_pattern"
		;;
		"delete"*)
			function="delete"; stripped="${2//\_//}"; v4l_device_path="${stripped#*[0-9]/}"
			echo -e "\n\nPerforming $function for $v4l_device_path"
			device_key_remove "$v4l_device_path"
			# Clean up the generated dropin
			device_path_escaped="${v4l_device_path//\//_}"
			service_pattern="wavelet_v4l_delete@*_${device_path_escaped}.service"
			rm -f "/home/wavelet/.config/systemd/user/$service_pattern"
		;;
		"redetect")
			function="redetect"; usbPath="$2"; echo -e "\n\nPerforming $function for all local devices"; detect_self
		;;
		*)
			exit 0
		;;
	esac
done