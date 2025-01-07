#!/bin/bash
# Encoder launcher script
# generates a systemd --user unit file for the UG appimage with the appropriate command lines
# This module is invoked from run_ug.sh with two notifications:  encoder_restart and encoder_prime
# Everything else is handled from detectv4l and other sources
# It concatenates any available local input devices into a switcher command line and intelligently launches them.

# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
read_etcd(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd" ${KEYNAME})
	echo -e "Key Name {$KEYNAME} read from etcd for value: $printvalue for host: $(hostname)\n"
}
read_etcd_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}") 
	echo -e "Key Name {$KEYNAME} read from etcd for global value: $printvalue\n"
}
read_etcd_prefix(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_prefix" "${KEYNAME}")
	echo -e "Key Name {$KEYNAME} read from etcd for value(s): $printvalue for host: $(hostname)\n"
}
read_etcd_prefix_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_prefix_global" "${KEYNAME}")
	echo -e "Key Name {$KEYNAME} read from etcd for global value(s): $printvalue\n"
}
read_etcd_prefix_list(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_prefix_list" "${KEYNAME}")
	echo -e "Key Name(s) {$KEYNAME} read from etcd for global value(s): $printvalue\n"
}
read_etcd_keysonly(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_keysonly" "${KEYNAME}")
	echo -e "Key Name {$KEYNAME} read from etcd for key values: $printvalue\n"
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
	echo -e "Key Name ${KEYNAME} set to ${KEYVALUE} under /$(hostname)/\n"
}
write_etcd_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name ${KEYNAME} set to ${KEYVALUE} for Global value\n"
}
write_etcd_client_ip(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_client_ip" "${KEYNAME}" "${KEYVALUE}"
}

read_uv_hash_select() {
	# The encoder should now be responding to ENCODER_QUERY master key in etcd.  uv_hash_select is for the controller/UI.
	KEYNAME=ENCODER_QUERY;	read_etcd_global; encoderDeviceHash="${printvalue}"
	case ${encoderDeviceHash} in
	(1)	echo "Blank screen activated, the Server will stream this directly via controller module."				;	exit 0
	;;
	(2)	echo "Seal image activated, the Server will stream this directly via controller module."				;	exit 0
	;;
	(T)	echo "Testcard generation activated, the Server will stream this directly via controller module."		;	exit 0
	;;
	(W)	echo "Four Panel split activated, attempting multidisplay swmix"										;	encoder_event_setfourway 
	;;
	*)	echo "Dynamic input device."																			;	encoder_check_server
	esac
}

encoder_check_server(){
	if [[ "$(hostname)" == *"svr"* ]]; then 
		echo -e "Server enabled, generating advanced switcher.."
		generate_server
	else
		echo -e "not a server, generating switcher for client devices.."
		generate_client
	fi
}

generate_server(){
	# Check to see if we have a device update global flag set.  If this is not the case, we don't want to regenerate anything
	echo "Running UG service assembly for the server."
	KEYNAME="/$(hostname)/INPUT_DEVICE_NEW"; read_etcd_global
	if [[ ${printvalue} -eq "0" ]];then
		# Do not regenerate the device maps, and parse to UG Commandline generator
		echo -e "\nThe input device update flag is not active, no new devices are available."
		echo "We should not need to perform steps to regenerate the AppImage service unit."
		if systemctl --user is-active --quiet UltraGrid.AppImage.service; then
			echo "UG AppImage Systemd unit is running, continuing."
			event_encoder_server
		else
			echo "UG AppImage Systemd unit is NOT running, starting it and continuing."
			systemctl --user start UltraGrid.AppImage.service
			event_encoder_server
		fi
	fi
	# Consume the device flag by resetting it
	KEYNAME="/$(hostname)/INPUT_DEVICE_NEW"; KEYVALUE="0"; write_etcd

	# Because the server is a special case, we want to ensure it can quickly switch between static, net and whatever local devices are populated
	# We create a sub-array with all of these devices and parse them to the encoder as normal
	# We do not need to worry about static inputs because they are always there, and always 0,1,2
	# Get keyvalues only for everything under inputs, this basically gives us all the valid generated command lines for our local devices.
	
	# First we need to know what device path matches what command line, so we need a matching array to check against:
	KEYNAME="inputs"; read_etcd_prefix;
	readarray -t matchingArray <<< $(echo ${printvalue} | sed 's|-t|\n|g' | xargs | sed 's|[[:space:]]|\n|g')
	echo -e "Matching Array contents:\n${matchingArray[@]}"
	# Now we read the command line values only
	KEYNAME="inputs"; read_etcd_prefix;
	# Because we have spaces in the return value, and this value is returned as a string, we have to process everything
	# remove -t, remove preceding space, 
	readarray -t localInputsArray <<< $(echo ${printvalue} | sed 's|-t|\n|g' | cut -d ' ' -f 2 | sed '/^[[:space:]]*$/d')
	echo -e "Local Array contents:\n${localInputsArray[@]}\n"

	# Declare the master server inputs array
	declare -A serverInputDevices=(); declare -A serverInputDevicesOrders
	# We now generate an array of these into our localInputs array
	declare -A localInputs=()
	# Index is 2 because static inputs occupy 0-2, so the local inputs will always start at index 3
	index=2
	for element in "${localInputsArray[@]}"; do
		# Append "-t " to make it a valid UltraGrid command
		if [[ "${element}" != *"-t"* ]];then
			element="-t ${element}"
		fi
		((index++))
		localInputs[$index]=${element}
		serverInputDevices[$index]=${element}; serverInputDevicesOrders+=( $element )
	done
	# Increment index by N devices present in the local inputs array
	localInputsOffset=$(echo ${#localInputs[@]})
	echo -e "${localInputsOffset} device(s) in array"
	index=( ${index} + ${localInputsOffset} )
	# Now we do the same for net devices
	declare -A networkInputs=()
	KEYNAME="/network_uv_stream_command/"; read_etcd_prefix_global;
	if [[ ${printvalue} == "" ]]; then
		echo "Array is empty, no network devices."
		:
	else
		readarray -t networkInputsArray <<< $(echo ${printvalue} | tr ' ' '\n')
		echo -e "Network array contents:\n${networkInputsArray[@]}\n"
		# We note generate these into our networkInputs array
		for element in "${networkInputsArray[@]}"; do
			((index++))
			# Append "-t " to make it a valid UltraGrid command
			if [[ "${element}" != *"-t"* ]];then
				element="-t $element"
			fi
			networkInputs[$index]=${element}
			serverInputDevices[$index]=${element}
		done
		networkInputsOffset=$(echo ${#networkInputs[@]})
		echo -e "${networkInputsOffset} device(s) in array..\n"
		index=( ${index} + ${networkInputsOffset} )
	fi
	# Convert the completed array back to strings, generate mapfile for controller and echo for verification
	echo "" > /var/home/wavelet/device_map_entries_verity
	mapfile -d '' sortedserverInputDevices < <(printf '%s\0' "${!serverInputDevices[@]}" | sort -z)
	serverDevs=$(while IFS= read -r line; do
		echo "$line"
	done <<< $(for i in ${sortedserverInputDevices[@]};do
		# Filter out dummy entries
		if [[ "${i}" == "-t" ]]; then
			:
		fi
		echo "$i)${serverInputDevices[$i]}"
		echo "$i,${serverInputDevices[$i]},$(hostname)" >> /var/home/wavelet/device_map_entries_verity
	done))
	# Generate the command line proper
	commandLine=$(while IFS= read -r line; do
		echo "$line"
	done <<< $(for i in ${sortedserverInputDevices[@]};do
		echo "${serverInputDevices[$i]}"
	done))
	commandLine=$(echo ${commandLine} | tr -d '\n')
	echo -e "\nGenerated switcher device list for all server local and network inputs devices is:\n${serverDevs}"
	echo -e "\nGenerated command line input into etcd is:\n${commandLine}\nConverting to base64 and injecting to etcd.."
	encodedCommandLine=$(echo "${commandLine}" | base64 -w 0)
	# Store generated server input var as base64 and assign to variable within this shell
	KEYNAME="/$(hostname)/ug_encoder_command"; KEYVALUE="${encodedCommandLine}"; write_etcd_global
	event_encoder_server
}

generate_client(){
	# Runs if the device is attached to this machine's hostname
	echo "Running UG service assembly for encoder client host."
	KEYNAME="/$(hostname)/INPUT_DEVICE_NEW"; read_etcd_global
	if [[ ${printvalue} -eq "0" ]];then
		# Do nothing
		echo -e "\nThe input device update flag is not active, no new devices are available."
		echo "We do not need to perform these steps to regenerate the AppImage service unit."
		event_encoder_client
	fi
	# Consume the device flag by resetting it
	KEYNAME="/$(hostname)/INPUT_DEVICE_NEW"; KEYVALUE="0"; write_etcd
	KEYNAME="ENCODER_ACTIVE"; read_etcd_global; primeElection=${printvalue}
	if [[ "${printvalue}" != "$(hostname)" ]];then
		echo "I am not set as the prime encoder by the controller, terminating active encoding processes and exiting."
		terminateProcess
		exit 0
	fi
	# First we need to know what device path matches what command line, so we need a matching array to check against:
	KEYNAME="inputs"; read_etcd_prefix;
	readarray -t matchingArray <<< $(echo ${printvalue} | sed 's|-t|\n|g' | xargs | sed 's|[[:space:]]|\n|g')
	echo -e "Matching Array contents:\n${matchingArray[@]}"
	# Now we read the command line values only
	KEYNAME="inputs"; read_etcd_prefix;
	# Because we have spaces in the return value, and this value is returned as a string, we have to process everything
	# remove -t, remove preceding space, 
	readarray -t localInputsArray <<< $(echo ${printvalue} | sed 's|-t|\n|g' | cut -d ' ' -f 2 | sed '/^[[:space:]]*$/d')
	echo -e "Local Array contents:\n${localInputsArray[@]}\n"

	# Declare the master server inputs array
	declare -A clientInputDevices=(); declare -A clientInputDevicesOrders
	# We now generate an array of these into our localInputs array
	declare -A localInputs=()
	# Index is 0 because on the client devices, we don't want to provide the static image, blank or SMPTE bars.
	index=0
	for element in "${localInputsArray[@]}"; do
		# Append "-t " to make it a valid UltraGrid command
		if [[ "${element}" != *"-t"* ]];then
			element="-t ${element}"
		fi
		((index++))
		localInputs[$index]=${element}
		clientInputDevices[$index]=${element}; clientInputDevicesOrders+=( $element )
	done
	# Increment index by N devices present in the local inputs array
	localInputsOffset=$(echo ${#localInputs[@]})
	echo -e "${localInputsOffset} device(s) in array..\n"
	index=( ${index} + ${localInputsOffset} )
	# Unlike the server, we are now done with generating arrays and do not need to enumerate network inputs.
	echo "" > /var/home/wavelet/device_map_entries_verity
	mapfile -d '' sortedClientInputDevices < <(printf '%s\0' "${!clientInputDevices[@]}" | sort -z)
	serverDevs=$(while IFS= read -r line; do
		echo "$line"
	done <<< $(for i in ${sortedserverInputDevices[@]};do
		# Filter out dummy entries
		if [[ "${i}" == "-t" ]]; then
			:
		fi
		echo "$i)${clientInputDevices[$i]}"
		echo "$i,${clientInputDevices[$i]},$(hostname)" >> /var/home/wavelet/device_map_entries_verity
	done))
	# Generate the command line proper
	commandLine=$(while IFS= read -r line; do
		echo "$line"
	done <<< $(for i in ${sortedClientInputDevices[@]};do
		echo "${clientInputDevices[$i]}"
	done))
	commandLine=$(echo ${commandLine} | tr -d '\n')
	echo -e "Generated switcher device list for all server local and network inputs devices is:${serverDevs}"
	echo -e "Generated command line input into etcd is:${commandLine}\nConverting to base64 and injecting to etcd.."
	encodedCommandLine=$(echo "${commandLine}" | base64 -w 0)
	KEYNAME="/$(hostname)/ug_encoder_command"; KEYVALUE="${encodedCommandLine}"; write_etcd_global
	clientInputvar=${commandLine}
	encoderDeviceStringFull="${printvalue}"
	echo -e "Device string ${encoderDeviceStringFull} located for uv_hash_select hash ${encoderDeviceHash}\n"
	unset printvalue
	KEYNAME="${encoderDeviceStringFull}"; read_etcd_global
	localInputvar=$(echo ${printvalue} | base64 -d)
	echo -e "Device input key $localInputvar located for this device string, proceeding to set encoder parameters \n"
	# For Audio we will select pipewire here
	audiovar="-s pipewire"
	event_encoder_client
}

encoder_event_setfourway(){
	# This block will attempt various four-way panel configurations depending on available devices
	# lists entries out of etcd, concats them to a single swmig command and stores as uv_input_cmd.
	# This won't work on multiencoder setups, all devices used here must be local to the active encoder.
	generatedLine=""
	KEYNAME="$(hostname)/inputs/"; swmixVar=$(read_etcd_global | xargs -d'\n' $(echo "${generatedLine}"))
	#swmixVar=$(etcdctl --endpoints=${ETCDENDPOINT} get "$(hostname)/inputs/" --prefix --print-value-only | xargs -d'\n' $(echo "${generatedLine}"))
	KEYNAME=uv_input_cmd; KEYVALUE="-t swmix:1920:1080:30 ${swmixVar}"; write_etcd_global
	echo -e "Generated command line is:\n${KEYVALUE}\n"
	multiInputvar=${KEYVALUE}
	/usr/local/bin/wavelet_textgen.sh
}

detect_input_present(){
	# Before we do anything, once again we check that we have an input device present.
	KEYNAME="/$(hostname)/INPUT_DEVICE_PRESENT"; read_etcd_global
		if [[ "$printvalue" -eq 1 ]]; then
			echo -e "An input device is present on this host, continuing.. \n"
			:
		else
			if [[ $(hostname) == *"svr"* ]]; then
				echo -e "This is the wavelet server, continuing.."
				:
			else
				echo -e "No input devices, and not a server, encoder shouldn't be running on this host."
				exit 0
			fi
		fi
	systemctl --user daemon-reload
	systemctl --user enable wavelet_encoder_query.service --now
	echo -e "Now monitoring for encoder changes.."
	# Call uv_hash_select to process the provided device hash and select the input from these data
	read_uv_hash_select
}

event_encoder_server(){
	# Handles the server-specific encoder functions, including static images and network devices
	# Here we want to check to see if the device is already prepopulated on the switcher.
	KEYNAME=uv_input;		read_etcd_global; controllerInputLabel=${printvalue}
	KEYNAME=ENCODER_QUERY;	read_etcd_global; controllerInputHash=${printvalue}
	targetHost="${controllerInputLabel%/*}"
	if [[ ${targetHost} == *"network_interface"* ]]; then
		echo -e "Target Hostname is a network device."
		deviceType="N"; targetHost="$(hostname)"; KEYNAME="/network_ip/${controllerInputHash}"; read_etcd_global; deviceFullPath=${printvalue}
		KEYNAME="/network_uv_stream_command/${deviceFullPath}"; read_etcd_global; searchArg="${printvalue}"
	elif [[ "${targetHost}" == *"$(hostname)"* ]]; then
		echo -e "Target hostname references this server."
		deviceType="L"; targetHost="$(hostname)"; KEYNAME="/hash/${controllerInputHash}"; read_etcd_global; deviceFullPath=${printvalue}
		KEYNAME="${deviceFullPath}"; read_etcd_global; searchArg="$(echo ${printvalue} | base64 -d)"
	else                                                      
		echo -e "Device is hosted from a remote encoder.\n"
		#deviceType="R"; targetHost="${controllerInputLabel%/*}"; KEYNAME="/hash/${controllerInputHash}"; read_etcd_global; deviceFullPath=${printvalue}
		#KEYNAME="${deviceFullPath}"; read_etcd_global; searchArg="$(echo ${printvalue} | base64 -d)"
		# Let the remote encoder handle it's own stuff.
		exit 0
	fi

	echo -e "Target host name is ${targetHost}"
	targetIP=$(getent ahostsv4 "${targetHost}" | head -n 1 | awk '{print $1}')
	# Here we want to check to see if the device is already prepopulated on the switcher
	# Find the command line in the device_map_entries file
	if grep -q ${searchArg#*-t} /var/home/wavelet/device_map_entries_verity; then
		echo "Entry found in device map.."
		channelIndex=$(grep "${searchArg#*-t}" /var/home/wavelet/device_map_entries_verity | cut -d ',' -f1)
	else
		# If not, we run the process again after having the encoder restart
		# Then we restart the controller process after a 3s delay
		echo "Entry missing from device map file!"
		echo "Remove device map file and force encoder restart to regenerate.."
		rm -rf /var/home/wavelet/device_map_entries_verify
		#systemctl --user restart run_ug.service
		exit 0
	fi
	# We check for the appropriate device in the generated user SystemD unit
	if ! grep -q ${searchArg#*-t} /var/home/wavelet/.config/systemd/user/UltraGrid.AppImage.service; then
		echo "Entry missing from pregenerated UG Service file!"
		echo "Remove device map file and force encoder restart to regenerate.."
		rm -rf /var/home/wavelet/device_map_entries_verify
		#systemctl --user restart run_ug.service
		exit 0
	else
		echo "Device entry found in systemD unit, continuing.."
	fi
	read_banner_status
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
	# This is a sparse array and populates only with values from the previous blocks.
	commandLine=(\
		[1]="--tool uv" \
		[2]="${filterVar}" \
		[3]="--control-port 6160" \
		[4]="-f V:rs:200:250" \
		[11]="-t switcher:excl_init" [12]="-t testcard:pattern=blank" [13]="-t file:/var/home/wavelet/seal.mkv:loop" [14]="-t testcard:pattern=smpte_bars" \
		[21]="${serverInputvar}" [22]="${localInputvar}" [29]="${audiovar}" \
		[81]="-c ${encodervar}" \
		[91]="-P ${video_port}" [92]="-m ${UGMTU}" [93]="${destinationipv4}" [94]="--param control-accept-global")
	ugargs="${commandLine[@]}"
	KEYNAME=UG_ARGS; KEYVALUE=${ugargs}; write_etcd
	echo -e "Verifying stored command line"
	read_etcd; echo ${printvalue}
	echo "
	[Unit]
	Description=UltraGrid AppImage executable
	After=network-online.target
	Wants=network-online.target
	[Service]
	ExecStart=/usr/local/bin/UltraGrid.AppImage ${ugargs}
	KillMode=control-group
	TimeoutStopSec=0.25
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
	# Tell Wavelet I am the active encoder
	KEYNAME="ACTIVE_ENCODER"; KEYVALUE="$(hostname)"; write_etcd_global
	# Tell wavelet my encoder IP address
	activeConnection=$(nmcli -t -f NAME,DEVICE c s -a | head -n 1)
	activeConnectionIP=$(nmcli dev show ${activeConnection#*:} | grep ADDRESS | awk '{print $2}' | head -n 1)
	KEYNAME=encoder_ip_address; KEYVALUE=${activeConnectionIP%/*}; write_etcd
	systemctl --user daemon-reload
	systemctl --user start UltraGrid.AppImage.service
	echo -e "Encoder systemd units instructed to start..\n"
	until systemctl --user is-active UltraGrid.AppImage.service; do
		echo "waiting for Systemd service to activate.."
		sleep .5
	done
	echo "UG Process generated and task started, moving on to setting channel index.."
	set_channelIndex
}

event_encoder_client(){
	# Handles the client encoder functions, only local devices (IE USB)
	# Here we want to check to see if the device is already prepopulated on the switcher.
	KEYNAME=uv_input;		read_etcd_global; controllerInputLabel=${printvalue}
	KEYNAME=ENCODER_QUERY;	read_etcd_global; hashValue=${printvalue}
	targetHost="${controllerInputLabel%/*}"
	if [[ "${targetHost}" == *"$(hostname)"* ]]; then
		echo -e "Target hostname references this host!"
		deviceType="L"; targetHost="$(hostname)"; KEYNAME="/hash/${controllerInputHash}"; read_etcd_global; deviceFullPath=${printvalue}
		KEYNAME="${deviceFullPath}"; read_etcd_global; searchArg="$(echo ${printvalue} | base64 -d)"
	else                                                      
		echo -e "Device is a network device, or hosted from a remote encoder.\n"
		exit 0
	fi
	echo -e "Target host name is $(hostname)"
	targetIP=$(getent ahostsv4 "${targetHost}" | head -n 1 | awk '{print $1}')
	# Here we want to check to see if the device is already prepopulated on the switcher
	# Find the command line in the device_map_entries file
	if grep -q ${searchArg#*-t} /var/home/wavelet/device_map_entries_verity; then
		echo "Entry found in device map.."
		channelIndex=$(grep "${searchArg#*-t}" /var/home/wavelet/device_map_entries_verity | cut -d ',' -f1)
	else
		# If not, we run the process again after having the encoder restart
		# Then we restart the controller process after a 3s delay
		echo "Entry missing from device map file!"
		echo "Remove device map file and force encoder restart to regenerate.."
		rm -rf /var/home/wavelet/device_map_entries_verify
		systemctl --user restart run_ug.sh
		exit 0
	fi
	# We check for the appropriate device in the generated user SystemD unit
	if ! grep -q ${searchArg#*-t} /var/home/wavelet/.config/systemd/user/UltraGrid.AppImage.service; then
		echo "Entry missing from pregenerated UG Service file!"
		echo "Remove device map file and force encoder restart to regenerate.."
		rm -rf /var/home/wavelet/device_map_entries_verify
		systemctl --user restart run_ug.sh
		exit 0
	else
		echo "Device entry found in systemD unit, continuing.."
	fi
	# Get banner info
	read_banner_status
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
	# This is a sparse array and populates only with values from the previous blocks.
	commandLine=(\
		[1]="--tool uv" \
		[2]="${filterVar}" \
		[3]="--control-port 6160" \
		[4]="-f V:rs:200:250" \
		[11]="-t switcher:excl_init" [22]="${localInputvar}" [29]="${audiovar}" \
		[81]="-c ${encodervar}" \
		[91]="-P ${video_port}" [92]="-m ${UGMTU}" [93]="${destinationipv4}" [94]="--param control-accept-global")
	ugargs="${commandLine[@]}"
	KEYNAME=UG_ARGS; KEYVALUE=${ugargs}; write_etcd
	echo -e "Verifying stored command line"
	read_etcd; echo ${printvalue}
	echo "
	[Unit]
	Description=UltraGrid AppImage executable
	After=network-online.target
	Wants=network-online.target
	[Service]
	ExecStart=/usr/local/bin/UltraGrid.AppImage ${ugargs}
	KillMode=control-group
	TimeoutStopSec=0.25
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
	# Tell Wavelet I am the active encoder
	KEYNAME="ACTIVE_ENCODER"; KEYVALUE="$(hostname)"; write_etcd_global
	# Tell wavelet my encoder IP address
	activeConnection=$(nmcli -t -f NAME,DEVICE c s -a | head -n 1)
	activeConnectionIP=$(nmcli dev show ${activeConnection#*:} | grep ADDRESS | awk '{print $2}' | head -n 1)
	KEYNAME=encoder_ip_address; KEYVALUE=${activeConnectionIP%/*}; write_etcd
	systemctl --user daemon-reload
	systemctl --user start UltraGrid.AppImage.service
	echo -e "Encoder systemd units instructed to start..\n"
	until systemctl --user is-active UltraGrid.AppImage.service; do
		echo "waiting for Systemd service to activate.."
		sleep .5
	done
	echo "UG Process generated and task started, moving on to setting channel index.."
	set_channelIndex
}

set_channelIndex(){
	# This previously resided in the controller, but makes more sense here.
	# Called after server or client encoder blocks have concatenated and generated their respective device maps and cmdlines
	KEYNAME=uv_input;		read_etcd_global; controllerInputLabel=${printvalue}
	KEYNAME=ENCODER_QUERY;	read_etcd_global; hashValue=${printvalue}
	# Ensure the encoder is even running...
	if ! systemctl --user is-active --quiet UltraGrid.AppImage.service; then
		# Something went wrong, we can't do anything if UG isn't even running..
		systemctl --user restart run_ug.service
		exit 0
	fi
	# Everything should already be set, all we need to do is look at the local channel index file and parse that to localhost
	channelIndex=$(grep "${searchArg#*-t}" /var/home/wavelet/device_map_entries_verity | cut -d ',' -f1)
	echo -e "Attempting to set switcher channel to new device.."
	echo "Channel Index is: ${channelIndex%,*}"
	echo "capture.data ${channelIndex%,*}" | busybox nc -v 127.0.0.1 6160	
}

read_banner_status(){
	# Reads Filter settings, should be banner.pam most of the time
	# If banner isn't enabled filterVar will be null, as the logo.c file can result in crashes with RTSP streams and some other pixel formats.
	KEYNAME="/banner/enabled"; read_etcd_global; bannerStatus=${printvalue}
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
	KEYNAME="/$(hostname)/encoder_prime"; KEYVALUE="0"; write_etcd_global
	systemctl --user disable wavelet_encoder.service --now
	systemctl --user UltraGrid.AppImage.service --now
}


#####
#
# Main
#
#####

#set -x
exec >/home/wavelet/encoder.log 2>&1

detect_input_present