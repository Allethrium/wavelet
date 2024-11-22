#!/bin/bash
# Encoder launcher script
# generates a systemd --user unit file for the UG appimage with the appropriate command lines
# Launches it as its own systemd --user service.
# 11/2023:
# Relies on detectv4l to be told when and where everything is
# Relies on hash values parsed from webUI/PHP to activate the valid device.
# If hash value = invalid device, nothing will happen.

# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
read_etcd(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd" ${KEYNAME})
	echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)\n"
}
read_etcd_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}") 
	echo -e "Key Name {$KEYNAME} read from etcd for Global Value $printvalue\n"
}
read_etcd_prefix(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_prefix" "${KEYNAME}")
	echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)\n"
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

event_encoder(){
	# Before we do anything, check that we have an input device present.
		KEYNAME=INPUT_DEVICE_PRESENT
		read_etcd
				if [[ "$printvalue" -eq 1 ]]; then
						echo -e "An input device is present on this host, continuing.. \n"
						:
				else
						echo -e "No input devices are present on this system, Encoder cannot run! \n"
						exit 0
				fi
	# Register yourself with etcd as an encoder and your IP address
	KEYNAME=encoder_ip_address
	KEYVALUE=$(ip a | grep 192.168.1 | awk '/inet / {gsub(/\/.*/,"",$2); print $2}')
	write_etcd_global
	systemctl --user daemon-reload
	systemctl --user enable watch_encoderflag.service --now
	echo -e "now monitoring for encoder reset flag changes.. \n"
	
	encoder_event_setfourway(){
		# This block will attempt various four-way panel configurations depending on available devices
		# lists entries out of etcd, concats them to a single swmig command and stores as uv_input_cmd.
		# This won't work on multiencoder setups, all devices used here must be local to the active encoder.
		generatedLine=""
		KEYNAME="$(hostname)/inputs/"; swmixVar=$(read_etcd_global | xargs -d'\n' $(echo "${generatedLine}"))
		#swmixVar=$(etcdctl --endpoints=${ETCDENDPOINT} get "$(hostname)/inputs/" --prefix --print-value-only | xargs -d'\n' $(echo "${generatedLine}"))
		KEYNAME=uv_input_cmd
		KEYVALUE="-t swmix:1920:1080:30 ${swmixVar}"
		write_etcd_global
		echo -e "Generated command line is:\n${KEYVALUE}\n"
		inputvar=${KEYVALUE}
		/usr/local/bin/wavelet_textgen.sh
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
		(1)	echo "Blank screen activated, as set from controller."				;	exit 0
		;;
		(2)	echo "Seal image activated, as set from controller"					;	exit 0
		;;
		(T)	echo "Testcard generation activated, as set from controller"		;	exit 0
		;;
		(W)	echo "Four Panel split activated, attempting multidisplay swmix"	;	encoder_event_setfourway 
		;;
		*)	echo -e "single dynamic input device, run code below:\n"			;	encoder_event_singleDevice
		esac
	}

	encoder_event_singleDevice(){
		KEYNAME="/hash/${encoderDeviceHash}"
		read_etcd_global
		currentHostName=($hostname)
		if [ -n "${printvalue}" ]; then
			echo -e "found ${printvalue} in /hash/ - we have a local device\n"
			case ${printvalue} in
				${currentHostName}*)    echo -e "\nThis device is attached to this encoder, proceeding\n"; 
				;;
				*)              echo -e "\nThis device is attached to a different encoder\n"    ;       exit 0
				;;
			esac
			encoderDeviceStringFull="${printvalue}"
			echo -e "\nDevice string ${encoderDeviceStringFull} located for uv_hash_select hash ${encoderDeviceHash}\n"
			printvalue=""
			KEYNAME="${encoderDeviceStringFull}"
			read_etcd_global
			inputvar=${printvalue}
			echo -e "\n Device input key $inputvar located for this device string, proceeding to set encoder parameters \n"
			# For Audio we will select pipewire here
			audiovar="-s pipewire"
		else
			echo -e "null string found in /hash/ - this is a network device\n"
			KEYNAME="/network_shorthash/${encoderDeviceHash}"
			read_etcd_global
			if [ -n "${printvalue}" ]; then
				echo -e "found in /network_shorthash/, proceeding..\n"
				encoderDeviceStringFull="${printvalue}"
				echo -e "\nDevice String ${encoderDeviceStringFull} located for uv_hash_select hash ${encoderDeviceHash}\n"
				printvalue=""
				# Locate device hash in network_ip folder and return the device IP address
				KEYNAME="/network_ip/${encoderDeviceHash}"
				read_etcd_global
				ipAddr=${printvalue}
				# Locate input command from the IP value retreived above
				KEYNAME="/network_uv_stream_command/${printvalue}"
				read_etcd_global
				# We have to check the NDI device for port changes because they do not seem stable..
				if [[ "${printvalue}" == *"ndi"* ]]; then
					echo -e "\nNDI Device in play, rescanning ports on IP Address ${ipAddr}..\n"
					ndiIPAddr=$(/usr/local/bin/UltraGrid.AppImage --tool uv -t ndi:help | grep ${ipAddr} | awk '{print $5}')
					inputvar="-t ndi:url=${ndiIPAddr}"
					audiovar="-s embedded"
				else
					inputvar="-t ${printvalue}"
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
	# Run common options here
	/usr/local/bin/wavelet_textgen.sh
	}
	# Encoder SubLoop
	# call uv_hash_select to process the provided device hash and select the input from these data
	read_uv_hash_select
	# Reads Filter settings, should be banner.pam most of the time
	# If banner isn't enabled filtervar will be null, as the logo.c file can result in crashes with RTSP streams and some other pixel formats.
	KEYNAME="/banner/enabled"
	if [[ "${printvalue}" == "0" ]]; then
		echo -e "\nBanner is enabled, so filtervar will be set appropriately.  Note currently the logo.c file in UltraGrid can generate errors on particular kinds of streams!..\n"
		KEYNAME=uv_filter_cmd
		read_etcd_global
		filtervar=${printvalue}
	else 
		echo -e "\nBanner is not enabled, so filtervar will be set to NULL..\n"
		filtervar=""
	fi
	# Reads Encoder codec settings, should be populated from the Controller
	KEYNAME=uv_encoder
	read_etcd_global
	encodervar=${printvalue}
	# Videoport is always 5004 unless we are doing some strange future project requiring bidirectionality or conference modes
	KEYNAME=uv_videoport
	read_etcd_global
	video_port=${printvalue}
	# Audio Port is always 5006, unless UltraGrid has gotten far better at handling audio we likely won't use this.
	KEYNAME=uv_audioport
	read_etcd_global
	audio_port=${printvalue}
	# Destination IP is the IP address of the UG Reflector
	destinationipv4="192.168.1.32"

	# Currently -f V:rs:200:240 on the end specifies reed-solomon forward error correction 
	# For higher btirate streams, we can use "-f LDGM:40%" - must be >2mb frame size!
	# Audio runs as a multiplied stream, there are issues ensuring Pipewire autoselects the appropriate device however.
	# This command would use the switcher;
	# --tool uv $filtervar -f V:rs:200:250 -t switcher -t testcard:pattern=blank -t file:/home/wavelet/seal.mp4:loop -t testcard:pattern=smpte_bars ${inputvar} -s pipewire -c ${encodervar} -P ${video_port} -m ${UGMTU} ${destinationipv4}
	# can be used remote with this kind of tool (netcat) : echo 'capture.data 0' | busybox nc localhost <control_port>
	# not using right now as different inputs have different formats.. may be problematic.
	UGMTU="9000"
	echo -e "Assembled command is:\n--tool uv $filtervar -f V:rs:200:250 --control-port 6160 -t switcher -t testcard:pattern=blank -t file:/home/wavelet/seal.mp4:loop -t testcard:pattern=smpte_bars ${audiovar} ${inputvar} -c ${encodervar} -P ${video_port} -m ${UGMTU} ${destinationipv4} \n"
	ugargs="--tool uv $filtervar--control-port 6160 -f V:rs:200:250 -t switcher -t testcard:pattern=blank -t file:/home/wavelet/seal.mp4:loop -t testcard:pattern=smpte_bars ${audiovar} ${inputvar} -c ${encodervar} -P ${video_port} -m ${UGMTU} ${destinationipv4} --param control-accept-global"
	KEYNAME=UG_ARGS
	KEYVALUE=${ugargs}
	write_etcd
	echo -e "Verifying stored command line"
	read_etcd
	echo "
	[Unit]
	Description=UltraGrid AppImage executable
	After=network-online.target
	Wants=network-online.target
	[Service]
	ExecStart=/usr/local/bin/UltraGrid.AppImage ${ugargs}
	KillMode=mixed
	TimeoutStopSec=0.25
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
	systemctl --user daemon-reload
	systemctl --user restart UltraGrid.AppImage.service
	echo -e "Encoder systemd units instructed to start..\n"
	sleep 3
	echo 'capture.data 3' | busybox nc -v 127.0.0.1 6160
}

# Main
exec >/home/wavelet/encoder.log 2>&1
event_encoder
