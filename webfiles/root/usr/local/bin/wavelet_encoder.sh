#!/bin/bash
# Encoder launcher script
# generates a systemd --user unit file for the UG appimage with the appropriate command lines
# This module is invoked from run_ug.sh with two notifications:  encoder_restart and encoder_prime
# Everything else is handled from detectv4l and other sources
# It concatenates any available local input devices into a switcher command line and intelligently launches them.


# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
read_etcd(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd" ${KEYNAME})
	echo -e "Key Name: {$KEYNAME} read from etcd for value: $printvalue for host: ${hostNameSys}\n"
}
read_etcd_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}") 
	echo -e "Key Name: {$KEYNAME} read from etcd for Global Value: $printvalue\n"
}
read_etcd_prefix(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_prefix" "${KEYNAME}")
	echo -e "Key Name: {$KEYNAME} read from etcd for value $printvalue for host: ${hostNameSys}\n"
}
read_etcd_prefix_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_prefix_global" "${KEYNAME}")
	echo -e "Key Name: {$KEYNAME} read from etcd for value $printvalue for host: ${hostNameSys}\n"
}
read_etcd_clients_ip() {
	return_etcd_clients_ip=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_clients_ip")
}
read_etcd_clients_ip_sed() {
	# We need this to manage the \n that is returned from etcd.
	# the above is useful for generating the reference text file but this parses through sed to string everything into a string with no newlines.
	processed_clients_ip=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_clients_ip" | sed ':a;N;$!ba;s/\n/ /g')
}
write_etcd(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name: ${KEYNAME} set to ${KEYVALUE} under /${hostNameSys}/\n"
}
write_etcd_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name: ${KEYNAME} set to: ${KEYVALUE} for Global value\n"
}
write_etcd_client_ip(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_client_ip" "${KEYNAME}" "${KEYVALUE}"
}
delete_etcd_key(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key" "${KEYNAME}"
}
delete_etcd_key_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key_global" "${KEYNAME}"
}
delete_etcd_key_prefix(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key_prefix" "${KEYNAME}"
}
generate_service(){
	# Can be called with more args with "generate_servier" ${keyToWatch} 0 0 "${serviceName}"
	/usr/local/bin/wavelet_etcd_interaction.sh "generate_service" "${serviceName}"
}

detect_input_present(){
	# Before we do anything, once again we check that we have an input device present.
	KEYNAME="/${hostNameSys}/INPUT_DEVICE_PRESENT"; read_etcd_global
		if [[ "$printvalue" -eq 1 ]]; then
			echo -e "An input device is present on this host, continuing.. \n"
		else
			if [[ ${hostNameSys} == *"svr"* ]]; then
				echo -e "This is the wavelet server, continuing.."
			else
				echo -e "No input devices, and not a server, encoder shouldn't be running on this host."
				exit 0
			fi
		fi
	systemctl --user daemon-reload
	systemctl --user enable wavelet_encoder_query.service --now
	echo -e "Now monitoring for encoder changes.."
}

read_uv_hash_select() {
	# The encoder should now be responding to ENCODER_QUERY master key in etcd.  uv_hash_select is for the controller/UI.
	KEYNAME=ENCODER_QUERY;	read_etcd_global; encoderDeviceHash="${printvalue}"
	case ${encoderDeviceHash} in
	(1)	echo "Blank screen activated, the Server will stream this directly via controller module."				;	check_ugAppImage
	;;
	(2)	echo "Seal image activated, the Server will stream this directly via controller module."				;	check_ugAppImage
	;;
	(T)	echo "Testcard generation activated, the Server will stream this directly via controller module."		;	check_ugAppImage
	;;
	*)	echo "Dynamic input device."																			;	encoder_check_server
	esac
}

check_ugAppImage(){
	# Checks for UG process and attempts to start it if dead.
	echo "System hostname is: ${hostNameSys}"
	echo "Pretty hostname is: ${hostNamePretty}"
	if systemctl --user is-active --quiet UltraGrid.AppImage.service; then
		echo "UG AppImage Systemd unit is running, continuing."
		echo "Controller should be able to select basic static inputs from channel update cmd."
	else
		echo "UG AppImage Systemd unit is NOT running."
		#systemctl --user restart UltraGrid.AppImage.service
	fi	
}

encoder_check_server(){
	if [[ "${hostNameSys}" == *"svr"* ]]; then 
		echo -e "This is the server, generating expanded switcher."
		generate_server_args
	else
		echo -e "not a server, generating switcher for local client devices only."
		generate_local_args "0"
	fi
}

generate_server_args(){
	# The server component generates array data for both the static and network devices.
	# It then moves on to the encoder client portion, which handles local devices.
	# Effectively we've added an additional step for the server.

	# Check to see if we have a device update global flag set.  If this is not the case, we don't want to regenerate anything
	echo "Running UG service assembly for the server."
	KEYNAME="GLOBAL_INPUT_DEVICE_NEW"; read_etcd_global
	if [[ ${printvalue} -eq "0" ]];then
		# Do not regenerate the device maps, parse to UG commandLine generator to verify device is there
		echo -e "The input device update flag is not active, no new devices have been added since last input change."
		echo "We should not need to perform steps to regenerate the AppImage service unit."
		if systemctl --user is-active --quiet UltraGrid.AppImage.service; then
			echo "UG AppImage Systemd unit is running, continuing."
			set_channelIndex
		else
			echo "UG AppImage Systemd unit is NOT running, starting it and continuing."
			systemctl --user start UltraGrid.AppImage.service
			generate_systemd_unit
		fi
	fi
	# Consume the global device flag by resetting it
	KEYNAME="GLOBAL_INPUT_DEVICE_NEW"; KEYVALUE="0"; write_etcd_global
	echo "" > /var/home/wavelet/device_map_entries_verity

	# Declare the master server inputs array
	declare -A serverInputDevices=()
	# Declare our static inputs
	declare serverStaticInputs=(\
		[0]="-t testcard:pattern=blank" \
		[1]="-t file:/var/home/wavelet/seal.mkv:loop" \
		[2]="-t testcard:pattern=smpte_bars")
	# Ensure index starts at 0
	index=0
	for element in "${serverStaticInputs[@]}"; do
		# Append "-t " to make it a valid UltraGrid input argument
		if [[ "${element}" != *"-t"* ]];then
			element="-t $element"
		fi
		serverInputDevices[$index]=${element}
		((index++))
	done
	# Set network devices
	# Index starts at 3 for netDevs
	declare -A networkInputs=()
	KEYNAME="/network_uv_stream_command/"; read_etcd_prefix_global;
	if [[ ${printvalue} == "" ]]; then
		echo "Array is empty, no network devices."
		:
	else
		readarray -t networkInputsArray <<< $(echo ${printvalue} | tr ' ' '\n')
		echo -e "Network array contents:\n${networkInputsArray[@]}\n"
		# We inject these into our networkInputs array
		for element in "${networkInputsArray[@]}"; do
			# Append "-t " to make it a valid UltraGrid input argument
			if [[ "${element}" != *"-t"* ]];then
				element="-t $element"
			fi
			networkInputs[$index]=${element}
			serverInputDevices[$index]=${element}
			((index++))
		done
		networkInputsOffset=$(echo ${#networkInputs[@]})
		echo -e "${networkInputsOffset} device(s) in array..\n"
		index=( ${index} + ${networkInputsOffset} )
	fi

	# At this point we should have an array {serverInputDevices[@]} with Static and Network devices populated.

	# Sort by index value
	mapfile -d '' sortedServerInputDevices < <(printf '%s\0' "${!serverInputDevices[@]}" | sort -z)
	serverDevs=$(while IFS= read -r line; do
		echo "$line"
	done <<< $(for i in ${sortedServerInputDevices[@]};do
		# Filter out dummy entries
		if [[ "${i}" == "-t" ]]; then
			:
		fi
		echo "$i)${serverInputDevices[$i]}"
		echo "$i,${serverInputDevices[$i]}" >> /var/home/wavelet/device_map_entries_verity
	done))
	# Generate the command line proper
	commandLine=$(while IFS= read -r line; do
		echo "$line"
	done <<< $(for i in ${sortedServerInputDevices[@]};do
		echo "${serverInputDevices[$i]}"
	done))
	commandLine=$(echo ${commandLine} | tr -d '\n')
	echo -e "\nGenerated switcher device list for all server and network inputs devices is:\n ${serverDevs}"
	echo -e "\nGenerated command line input into etcd is:\n${commandLine}\n\nConverting to base64 and injecting to etcd.."
	encodedCommandLine=$(echo "${commandLine}" | base64 -w 0)
	# Store generated server input var as base64 and assign to variable within this shell
	KEYNAME="/${hostNameSys}/server_commands"; KEYVALUE="${encodedCommandLine}"; write_etcd_global
	generate_local_args "${index}"
}

generate_local_args(){
	# This is called after the server portion has completed, or it will be called directly if running on a client device
	echo "Running UG service assembly for local devices."
	KEYNAME="/${hostNameSys}/INPUT_DEVICE_NEW"; read_etcd_global
	if [[ ${printvalue} -eq "0" ]];then
		# Do nothing
		echo -e "\nThe input device update flag is not active, no new devices are available."
		generate_systemd_unit
	fi
	# Consume the device flag by resetting it
	KEYNAME="/${hostNameSys}/INPUT_DEVICE_NEW"; KEYVALUE="0"; write_etcd_global
	KEYNAME="ENCODER_ACTIVE"; read_etcd_global
	if [[ "${printvalue}" != "${hostNamePretty}" ]];then
		echo "I am not set as the prime encoder by the controller, terminating active encoding processes and exiting."
		terminateProcess
		exit 0
	fi
	echo "Parsed index from server block (if run) is: $1"
	# First we need to know what device path matches what command line, so we need a matching array to check against:
	KEYNAME="inputs"; read_etcd_prefix;
	readarray -t matchingArray <<< $(echo ${printvalue} | sed 's|-t|\n|g' | xargs | sed 's|[[:space:]]|\n|g')
	echo -e "Matching Array contents:\n${matchingArray[@]}"
	# Because we have spaces in the return value, and this value is returned as a string, we have to process everything
	# remove -t, remove preceding space, 
	readarray -t localInputsArray <<< $(echo ${printvalue} | sed 's|-t|\n|g' | cut -d ' ' -f 2 | sed '/^[[:space:]]*$/d')
	echo -e "Local Array contents:\n${localInputsArray[@]}"

	# Declare the master local inputs array
	declare -A localInputDevices=(); declare -A localInputs=()
	# Index is parsed from the server block depending on how many netdevices or is 0 for local stuff.
	index=${1}
	if [[ -z index ]]; then
		# Clear device map file so we start with a blank slate
		echo "" > /var/home/wavelet/device_map_entries_verity
	fi

	for element in "${localInputsArray[@]}"; do
		# Append "-t " to make it a valid UltraGrid command
		if [[ "${element}" != *"-t"* ]];then
			element="-t ${element}"
		fi
		localInputs[$index]=${element}
		localInputDevices[$index]=${element}
		((index++))
	done
	# Increment index by N devices present in the local inputs array
	localInputsOffset=$(echo ${#localInputs[@]})
	echo -e "${localInputsOffset} device(s) in array..\n"
	index=( ${index} + ${localInputsOffset} )

	# Note that here we are appending entries to device_map_entries_verity!
	mapfile -d '' sortedLocalInputDevices < <(printf '%s\0' "${!localInputDevices[@]}" | sort -z)
	localDevs=$(while IFS= read -r line; do
		echo "$line"
	done <<< $(for i in ${sortedLocalInputDevices[@]};do
		# Filter out dummy entries
		if [[ "${i}" == "-t" ]]; then
			:
		else
			echo "$i)${localInputDevices[$i]}"
			echo "$i,${localInputDevices[$i]},${hostNameSys}" >> /var/home/wavelet/device_map_entries_verity
		fi
	done))
	# Generate the command line proper
	commandLine=$(while IFS= read -r line; do
		echo "$line"
	done <<< $(for i in ${sortedLocalInputDevices[@]};do
		echo "${localInputDevices[$i]}"
	done))
	commandLine=$(echo ${commandLine} | tr -d '\n')
	echo -e "Generated switcher device list for all local input devices is:\n${localDevs}"
	echo -e "Generated command line input into etcd is:\n${commandLine}\nConverting to base64 and injecting to etcd.."
	encodedCommandLine=$(echo "${commandLine}" | base64 -w 0)
	KEYNAME="/${hostNameSys}/local_encoder_command"; KEYVALUE="${encodedCommandLine}"; write_etcd_global
	clientInputvar=${commandLine}
	# We should now have all local input variables populated correctly
	generate_systemd_unit
	retry=0
}

generate_systemd_unit(){
	# Checks for requested device and regenerates the systemD unit if it is not available
	read_banner_status
	# For Audio we will select pipewire here as it seems to do a decent job of finding the current device or providing a null if none.
	audiovar="-s pipewire"
	# Read Encoder codec settings, should be populated from the Controller
	KEYNAME=uv_encoder; read_etcd_global; encodervar=${printvalue}
	# Videoport is always 5004 unless we are doing some strange future project requiring bidirectionality or conference modes
	KEYNAME=uv_videoport; read_etcd_global; video_port=${printvalue}
	# Audio Port is always 5006, and this is the default so we won't specify it in our command line.
	KEYNAME=uv_audioport; read_etcd_global; audio_port=${printvalue}
	# Destination IP is the IP address of the UG Reflector, usually the server IP or it could also be an overflow reflector.
	KEYNAME=REFLECTOR_IP; read_etcd_global; destinationipv4=${printvalue}
	# N.B This isn't the same as ethernet MTU.
	UGMTU="9000"
	# Grab our inputVars.  
	if [[ ${hostNameSys} = *"svr"* ]]; then
		KEYNAME="/${hostNameSys}/server_commands"; read_etcd_global; serverInputvar=$(echo ${printvalue} | base64 -d)
	else
		# Zero that out so nothing will be populated
		unset serverInputvar
	fi
	KEYNAME="/${hostNameSys}/local_encoder_command"; read_etcd_global; localInputvar=$(echo ${printvalue} | base64 -d)
	# This is a sparse array, not all values need to be set.
	commandLine=(\
		[1]="--tool uv" \
		[2]="${filterVar}" \
		[3]="--control-port 6160" \
		[4]="-f V:rs:200:250" \
		[11]="-t switcher:excl_init" [21]="${serverInputvar}" [22]="${localInputvar}" [29]="${audiovar}" \
		[31]="-c ${encodervar}" \
		[91]="-P ${video_port}" [92]="-m ${UGMTU}" [93]="${destinationipv4}" [94]="--param control-accept-global")
	ugargs="${commandLine[@]}"
	KEYNAME=UG_ARGS; KEYVALUE=${ugargs}; write_etcd
	echo "[Unit]
Description=UltraGrid AppImage executable
After=network-online.target
Wants=network-online.target
[Service]
ExecStart=/usr/local/bin/UltraGrid.AppImage ${ugargs}
KillMode=control-group
TimeoutStopSec=0.33
[Install]
WantedBy=default.target" > /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
	# Tell Wavelet I am the active encoder
	KEYNAME="ENCODER_ACTIVE"; KEYVALUE="${hostNameSys}"; write_etcd_global
	# Tell wavelet my encoder IP address
	activeConnection=$(nmcli -t -f NAME,DEVICE c s -a | head -n 1)
	activeConnectionIP=$(nmcli dev show ${activeConnection#*:} | grep ADDRESS | awk '{print $2}' | head -n 1)
	KEYNAME=ENCODER_IP_ADDRESS; KEYVALUE=${activeConnectionIP%/*}; write_etcd_global
	systemctl --user daemon-reload
	systemctl --user restart UltraGrid.AppImage.service
	echo -e "Encoder systemd unit instructed to start.."
	WAIT_TIME=0
	until (( WAIT_TIME == 10 )) || systemctl --user is-active UltraGrid.AppImage.service; do
		echo "waiting for Systemd service to activate.."
		sleep "$(( WAIT_TIME++ ))"
	done
	(( WAIT_TIME < 10 ))
	echo "UG Process generated and task started, moving on to setting channel index.."
	sleep 1
	set_channelIndex
}

set_channelIndex(){
	# This previously resided in the controller, but makes more sense here.
	# Called after server or client encoder blocks have concatenated and generated their respective device maps and cmdlines
	KEYNAME=uv_input;		read_etcd_global; controllerInputLabel=${printvalue}
	KEYNAME=ENCODER_QUERY;	read_etcd_global; hashValue=${printvalue}
	# Ensure the encoder is even running...
	if ! systemctl --user is-active --quiet UltraGrid.AppImage.service; then
		echo "Something went wrong, we can't do anything until the SystemD unit is operating!"
		systemctl --user restart run_ug.service
		exit 0
	fi
	# Final step is to look for the uv_input label in device_map_entries_verity
	# Module should ONLY be called on a system which possesses the device in question
	# If we are the server, we should test for network device:
	echo "Test for network device"
	if [[ ${controllerInputLabel} == *"/network_interface/"* ]]; then
		KEYNAME="/network_ip/${hashValue}"; read_etcd_global
		KEYNAME="/network_uv_stream_command/${printvalue}"; read_etcd_global
		searchArg=${printvalue}
	else
		# We want the UI label to reflect the pretty hostnames as set on the UI here.  I think..
		KEYNAME="/${hostNamePretty}/devpath_lookup/${hashValue}"; read_etcd_global; searchArg="${printvalue}"
	fi

	# check for device_map presence
	echo "Looking for device path ${searchArg} in local device map file.."
	if grep -q ${searchArg} /var/home/wavelet/device_map_entries_verity; then
		echo "Entry found in device map.."
		channelIndex=$(grep "${searchArg}" /var/home/wavelet/device_map_entries_verity | cut -d ',' -f1)
	else
		# If not, we run the process again after having the encoder restart
		echo "Entry missing from device map file! Forcing re-enumeration of devices.."
		sleep 1
		KEYNAME="GLOBAL_INPUT_DEVICE_NEW"; KEYVALUE="1"; write_etcd_global
		KEYNAME="/${hostNameSys}/INPUT_DEVICE_NEW"; write_etcd_global
		rm -rf /var/home/wavelet/device_map_entries_verity
		exit 0
	fi
	# check for UG arg
	echo "Looking for device path ${searchArg} in UltraGrid appImage systemD unit.."
	if grep -q ${searchArg} /var/home/wavelet/.config/systemd/user/UltraGrid.AppImage.service; then
		echo "Entry found in AppImage systemD unit, continuing.."
	else
		if [[ ${retry} == 3 ]]; then
			echo "Retries exceeded, starting process from scratch."
			rm -rf /var/home/wavelet/device_map_entries_verity
			KEYNAME="GLOBAL_INPUT_DEVICE_NEW"; KEYVALUE="1"; write_etcd_global
			KEYNAME="/${hostNameSys}/INPUT_DEVICE_NEW"; write_etcd_global
		fi
		echo "Entry missing from systemD unit! Attempting to regenerate three times before re-enumerating entire device tree.."
		((retry++))
		generate_systemd_unit
		exit 0
	fi
	channelIndex=$(grep "${searchArg}" /var/home/wavelet/device_map_entries_verity | cut -d ',' -f1)
	echo -e "Attempting to set switcher channel to new device.."
	echo "Channel Index is: ${channelIndex%,*}"
	echo "capture.data ${channelIndex%,*}" | busybox nc -v 127.0.0.1 6160	
	echo "Task complete, exiting."
	exit 0
}

read_banner_status(){
	# Reads Filter settings, should be banner.pam most of the time
	# If banner isn't enabled filterVar will be null, as the logo.c file can result in crashes with RTSP streams and some other pixel formats.
	KEYNAME="/UI/banner"; read_etcd_global; bannerStatus=${printvalue}
	echo -e "Banner status is: ${bannerStatus}"
	if [[ "${bannerStatus}" -eq 1 ]]; then
		echo -e "Banner is enabled, so filterVar will be set appropriately.  Note currently the logo.c file in UltraGrid can generate errors on particular kinds of streams!..\n"
		/usr/local/bin/wavelet_textgen.sh
		KEYNAME=uv_filter_cmd; read_etcd_global; filterVar=$(echo ${printvalue} | base64 -d)
		echo "filterVar is: ${filterVar}"
		if [[ ${filterVar} == "--capture-filter" ]]; then
			echo "filterVar has an illegal or incomplete command, unsetting.."
			unset filterVar
		fi
	else 
		echo -e "Banner is not enabled, so filterVar will be set to NULL..\n"
		unset filterVar
	fi
}

terminateProcess(){
	# This will stop the encoder process on this machine if it's not the current encoder
	# The prime bit is set for the hostname by the controller
	# If this is not the currently active encoder hostname, it will set itself off for the prime bit here.
	# Therefore, everything generally behaves in a reticent manner and must be appointed by the controller.
	echo "Setting encoder_prime key to 0 for this device, and terminating the encoder service."
	KEYNAME="/${hostNameSys}/encoder_prime"; KEYVALUE="0"; write_etcd_global
	systemctl --user disable wavelet_encoder.service --now
	systemctl --user UltraGrid.AppImage.service --now
}


#####
#
# Main
#
#####


hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
#set -x
exec >/var/home/wavelet/logs/encoder.log 2>&1

read_uv_hash_select