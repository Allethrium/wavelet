#!/bin/bash
# Encoder launcher script
# generates a systemd --user unit file for the UG appimage with the appropriate command lines
# Launches it as its own systemd --user service.
# 11/2023:
# Relies on detectv4l to be told when and where everything is
# Relies on hash values parsed from webUI/PHP to activate the valid device.
# If hash value = invalid device, nothing will happen.

#Etcd Interaction
ETCDENDPOINT=192.168.1.32:2379
read_etcd(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get $(hostname)/${KEYNAME} --print-value-only)
        echo -e "Key Name $KEYNAME read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_prefix(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix $(hostname)/${KEYNAME} --print-value-only)
        echo -e "Key Name $KEYNAME read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_global(){
        printvalue="$(etcdctl --endpoints=${ETCDENDPOINT} get "${KEYNAME}" --print-value-only)"
        echo -e "Key Name $KEYNAME read from etcd for value $printvalue for Global value"
}

write_etcd(){
        etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}

write_etcd_global(){
        etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
}

write_etcd_clientip(){
        etcdctl --endpoints=${ETCDENDPOINT} put decoderip/$(hostname) "${KEYVALUE}"
        echo -e "$(hostname) set to ${KEYVALUE} for Global value"
}
read_etcd_clients_ip() {
        return_etcd_clients_ip=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix decoderip/ --print-value-only)
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
        swmixVar=$(etcdctl --endpoints=${ETCDENDPOINT} get "$(hostname)/inputs/" --prefix --print-value-only | xargs -d'\n' $(echo "${generatedLine}"))
        KEYNAME=uv_input_cmd
        KEYVALUE="-t swmix:1920:1080:30 ${swmixVar}"
	write_etcd_global
        echo -e "Generated command line is:\n${KEYVALUE}\n"
	inputvar=${KEYVALUE}
	/usr/local/bin/wavelet_textgen.sh
	}

	read_uv_hash_select() {
	# 11/15/2023
	# Totally new approach
	# Now, we pull uv_hash_select, which is a value passed from the webUI back into this etcd key
	# compare the hash against available keys in /hash/$keyname, keyvalue will be the device string
	# then search for device string in $hostname/inputs and if found, we run with that and set another key to notify that it is active
	# if key does not exist, we do nothing and let another encoder (hopefully with the connected device) go to town.  Maybe post a "vOv" notice in log.
	# Blank Screen and the Seal static image do not run on any encoder, they are generated on the server.
		KEYNAME=uv_hash_select
		read_etcd_global
		encoderDeviceHash="${printvalue}"
		case ${encoderDeviceHash} in
		(1)	echo "Blank screen activated, as set from controller."; exit 0
		;;
		(2)	echo "Seal image activated, as set from controller"; exit 0
		;;
		(T)	echo "Testcard generation activated, as set from controller"; exit 0
		;;
		(W) echo "Four Panel split activated, attempting multidisplay swmix";	encoder_event_setfourway 
		;;
		*) single dynamic input device, run code below:
		KEYNAME="/hash/${encoderDeviceHash}"
		read_etcd_global
		encoderDeviceStringFull="${printvalue}"
		echo -e "\n Device string ${encoderDeviceStringFull} located for uv_hash_select hash ${encoderDeviceHash} \n"
		printvalue=""
		KEYNAME="${encoderDeviceStringFull}"
		read_etcd_global
		inputvar=${printvalue}
		echo -e "\n Device input key $inputvar located for this device string, proceeding to set encoder parameters \n"
		/usr/local/bin/wavelet_textgen.sh
		esac
	}

	# Encoder SubLoop
	# call uv_hash_select to process the provided device hash and select the input from these data
	read_uv_hash_select
	# Reads Filter settings, should be banner.pam most of the time
	KEYNAME=uv_filter_cmd
	read_etcd_global
	filtervar=${printvalue}
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
	# For higher btirate streams, we can use "-f LDGM:40%"
	# Audio runs as a multiplied stream, if enabled at all.
	# traffic shaping can be disabled by adding '-l unlimited" before inputvar
	echo -e "Assembled command is: \n --tool uv $filtervar -f LDGM:40% ${inputvar} -c ${encodervar} -P ${uv_videoport} -m 9000 ${destinationipv4} \n"
	ugargs="--tool uv $filtervar -f V:rs:200:240 -l unlimited ${inputvar} -c ${encodervar} -P ${video_port} -m 9000 ${destinationipv4}"
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
}

# Main
exec >/home/wavelet/encoder.log 2>&1
event_encoder
