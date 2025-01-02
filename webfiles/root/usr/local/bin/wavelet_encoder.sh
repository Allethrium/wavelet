#!/bin/bash
# Encoder launcher script
# generates a systemd --user unit file for the UG appimage with the appropriate command lines
# Launches it as its own systemd --user service.
# The encoder performs no host detection.  It simply runs whatever encoder tasks are set under the specific host

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

encoder_event_checkDevMode(){
	echo -e "Checking for DevMode.."
	if [[ -f /var/developerMode.enabled ]]; then
		if [[ "$(hostname)" == *"svr"* ]]; then 
			echo -e "Server and DevMode enabled, generating advanced switcher.."
			encoder_event_server
		else
			echo -e "not a server, falling back on single device.."
			encoder_event_singleDevice
		fi
	else
		echo -e "devmode off, falling back on single device method.."
		encoder_event_singleDevice
	fi
}

read_uv_hash_select() {
	# Now, we pull uv_hash_select, which is a value passed from the webUI back into this etcd key
	# compare the hash against available keys in /hash/$keyname, keyvalue will be the device string
	# then search for device string in $hostname/inputs and if found, we run with that and set another key to notify that it is active
	# if key does not exist, we do nothing and let another encoder (hopefully with the connected device) go to town.  Maybe post a "vOv" notice in log.
	# Blank Screen and the Seal static image do not run on any encoder, they are generated on the server.
	KEYNAME=uv_hash_select
	read_etcd_global
	encoderDeviceHash="${printvalue}"
	case ${encoderDeviceHash} in
	(1)	echo "Blank screen activated, the Server will stream this directly via controller module."				;	exit 0
	;;
	(2)	echo "Seal image activated, the Server will stream this directly via controller module."				;	exit 0
	;;
	(T)	echo "Testcard generation activated, the Server will stream this directly via controller module."		;	exit 0
	;;
	(W)	echo "Four Panel split activated, attempting multidisplay swmix"										;	encoder_event_setfourway 
	;;
	*)	echo -e "single dynamic input device, run code below:\n"												;	encoder_event_checkDevMode
	esac
}

encoder_event_server(){
	# Check to see if we have a device update global flag set.  If this is not the case, we don't want to regenerate anything
	KEYNAME="INPUT_DEVICE_NEW"; read_etcd
	if [[ ${printvalue} -eq "0" ]];then
		# Do nothing
		echo -e "\nThe input device update flag is not active, no new devices are available and we do not need to perform these steps to regenerate the AppImage service unit."
		echo -e "No further action is required, the Controller module should be able to select the appropriate channel on its own.\n"
		exit 0
	fi
	# Consume the device flag by resetting it
	KEYNAME="$INPUT_DEVICE_NEW"; KEYVALUE="0"; write_etcd

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
	echo -e "${localInputsOffset} device(s) in array..\n"
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
		echo "$i,${serverInputDevices[$i]}" >> /var/home/wavelet/device_map_entries_verity
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
	KEYNAME="/$(hostname)/serverInputs"; KEYVALUE="${encodedCommandLine}"; write_etcd_global
	read_banner_status
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

encoder_event_singleDevice(){
	KEYNAME="/hash/${encoderDeviceHash}"
	read_etcd_global
	currentHostName=($hostname)
	if [ -n "${printvalue}" ]; then
		echo -e "found ${printvalue} in /hash/ - we have a local device"
		case ${printvalue} in
			${currentHostName}*)		echo -e "This device is attached to this encoder, proceeding"	; 
			;;
			*)							echo -e "This device is attached to a different encoder"		;	exit 0
			;;
		esac
		encoderDeviceStringFull="${printvalue}"
		echo -e "Device string ${encoderDeviceStringFull} located for uv_hash_select hash ${encoderDeviceHash}\n"
		unset ${printvalue}
		KEYNAME="${encoderDeviceStringFull}"; read_etcd_global
		localInputvar=$(echo ${printvalue} | base64 -d)
		echo -e "Device input key $localInputvar located for this device string, proceeding to set encoder parameters \n"
		# For Audio we will select pipewire here
		audiovar="-s pipewire"
	else
		echo -e "null string found in /hash/ - this is a network device\n"
		KEYNAME="/network_shorthash/${encoderDeviceHash}"; read_etcd_global
		if [ -n "${printvalue}" ]; then
			echo -e "found in /network_shorthash/, proceeding..\n"
			encoderDeviceStringFull="${printvalue}"
			echo -e "\nDevice String ${encoderDeviceStringFull} located for uv_hash_select hash ${encoderDeviceHash}\n"
			printvalue=""
			# Locate device hash in network_ip folder and return the device IP address
			KEYNAME="/network_ip/${encoderDeviceHash}"; read_etcd_global; ipAddr=${printvalue}
			# Locate input command from the IP value retreived above
			KEYNAME="/network_uv_stream_command/${printvalue}"; read_etcd_global
			if [[ "${printvalue}" == *"ndi"* ]]; then
				# We have to check the NDI device for port changes because they do not seem stable..
				echo -e "NDI Device in play, rescanning ports on IP Address ${ipAddr}..\n"
				ndiIPAddr=$(/usr/local/bin/UltraGrid.AppImage --tool uv -t ndi:help | grep ${ipAddr} | awk '{print $5}')
				netInputvar="-t ndi:url=${ndiIPAddr}"
				audiovar="-s embedded"
			else
				netInputvar="-t ${printvalue}"
				# Audio is not implemented in UltraGrid's RTSP yet, so we will just utilize pipewire here or have NO audio.
				audiovar="-s pipewire"
			fi
			# clear printvalue
			printvalue=""
		else
			echo -e "not found in network_shorthash, we have an invalid selection, ending process..\n"
			exit 0
		fi
	fi
}

event_encoder(){
	# This is for an additional encoder, however it will probably eventually be migrated to the server routine above once I'm satisfied it's solid.
	# Before we do anything, check that we have an input device present.
		KEYNAME=INPUT_DEVICE_PRESENT; read_etcd
				if [[ "$printvalue" -eq 1 ]]; then
						echo -e "An input device is present on this host, continuing.. \n"
						:
				else
						echo -e "No input devices are present on this system, Encoder cannot run! \n"
						if [[ $(hostname) == *"svr"* ]]; then
							echo -e "This is the wavelet server, continuing.."
							:
						else
							echo -e "No input devices, and not a server, ending task.."
							exit 0
						fi
				fi
	# Register yourself with etcd as an encoder and your IP address
	activeConnection=$(nmcli -t -f NAME,DEVICE c s -a | head -n 1)
	# Gets both IPV6 and IPV4 addresses.. since we might want to futureproof..
	# nmcli dev show ${activeConnection#*:} | grep ADDRESS | awk '{print $2}'
	activeConnectionIP=$(nmcli dev show ${activeConnection#*:} | grep ADDRESS | awk '{print $2}' | head -n 1)
	KEYNAME=encoder_ip_address; KEYVALUE=${activeConnectionIP%/*}; write_etcd
	systemctl --user daemon-reload
	systemctl --user enable watch_encoderflag.service --now
	echo -e "now monitoring for encoder reset flag changes.. \n"
	
	# Encoder SubLoop
	# call uv_hash_select to process the provided device hash and select the input from these data
	read_uv_hash_select
	read_banner_status
	# Reads Encoder codec settings, should be populated from the Controller
	KEYNAME=uv_encoder; read_etcd_global; encodervar=${printvalue}
	# Videoport is always 5004 unless we are doing some strange future project requiring bidirectionality or conference modes
	KEYNAME=uv_videoport; read_etcd_global; video_port=${printvalue}
	# Audio Port is always 5006, and this is the default so we won't specify it in our command line.
	KEYNAME=uv_audioport; read_etcd_global; audio_port=${printvalue}
	# Destination IP is the IP address of the UG Reflector, usually the server IP or it could also be an overflow reflector for externalization.
	KEYNAME=REFLECTOR_IP; read_etcd_global; destinationipv4=${printvalue}
	UGMTU="9000"
	# Grab our inputVars
	KEYNAME="/svr.wavelet.local/serverInputs"; read_etcd_global; serverInputvar=$(echo "${printvalue}" | base64 -d)
	commandLine=(\
		[1]="--tool uv" \
		[2]="${filterVar}" \
		[3]="--control-port 6160" \
		[4]="-f V:rs:200:250" \
		[11]="-t switcher:excl_init" [12]="-t testcard:pattern=blank" [13]="-t file:/var/home/wavelet/seal.mkv:loop" [14]="-t testcard:pattern=smpte_bars" \
		[21]="${serverInputvar}" [22]="${localInputvar}" [23]="${netInputvar}" [24]=${multiInputvar} [29]="${audiovar}" \
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
	systemctl --user daemon-reload
	systemctl --user start UltraGrid.AppImage.service
	echo -e "Encoder systemd units instructed to start..\n"
	until systemctl --user is-active UltraGrid.AppImage.service; do
		echo "waiting 0.1 seconds for Systemd service to activate.."
		sleep .1
	done
	# Always do first live input, this would be set again by the controller for a different selection.
	echo 'capture.data 3' | busybox nc -v 127.0.0.1 6160
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


#####
#
# Main
#
#####

#set -x
exec >/home/wavelet/encoder.log 2>&1

event_encoder