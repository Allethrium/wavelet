#!/bin/bash
# Checks device hostname to define behavior and launches ultragrid from AppImage as appropriate
# Script runs as a user service, calls other user services.  Nothing here should be asking for root.

detect_self(){
	UG_HOSTNAME=$(hostname)
	# Create a hostname.local file in tmp so that nonprivileged users such as dnsmasq can tell who we are
	# we aren't allowed to write to /var/tmp..
	#hostname=$(hostname)
	#echo ${hostname} > /var/tmp/hostname.local
	#chmod 664 /var/tmp/hostname.local
	#chown root:root /var/tmp/hostname.local
	#sed -i "s|!!hostnamegoeshere!!|${hostname}|g" /usr/local/bin/wavelet_network_sense.sh
	
	# Check to see if hostname has changed since last reboot
	if [[ -f /home/wavelet/oldhostname.txt ]]; then
		check_hostname
	fi
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*) 					echo -e "I am an Encoder \n"; event_encoder
	;;
	decX.wavelet.local)		echo -e "I am a Decoder, but my hostname is generic.\nAn error has occurred at some point, and needs troubleshooting.\n Terminating process. \n"; exit 0
	;;
	dec*)					echo -e "I am a Decoder \n"; event_decoder
	;;
	livestream*)			echo -e "I am a Livestream ouput gateway \n"; event_livestream
	;;
	gateway*)				echo -e "I am an input Gateway for another video streaming system \n"; event_gateway
	;;
	svr*)					echo -e "I am a Server."; event_server
	;;
	*) 						echo -e "This device Hostname is not set approprately, exiting \n"; exit 0
	;;
	esac
}

check_hostname(){
	# Get the old hostname from the file, then remove it because it's not necessary until the hostname is changed again.
	oldHostName=$(echo /home/wavelet/oldhostname.txt)
	rm -rf /home/wavelet/oldhostname.txt
	if [[ "${oldHostName}" == "$(hostname)" ]]; then
		echo -e "\nOld hostname is the same as the current hostname!  Doing nothing.\n"
		detect_self
	fi
	case $oldHostName in
	enc*) 					echo -e "\nI was an Encoder\n"					; clean_oldHostSettings ${oldHostname}
	;;
	decX.wavelet.local)		echo -e "\nI was an unconfigured Decoder\n"		; exit 0
	;;
	dec*)					echo -e "I was a Decoder \n"					; clean_oldHostSettings ${oldHostname}
	;;
	livestream*)			echo -e "I was a Livestreamer \n"				; clean_oldHostSettings ${oldHostname}
	;;
	gateway*)				echo -e "I was an input Gateway\n"  			; clean_oldHostSettings ${oldHostname}
	;;
	svr*)					echo -e "I was a Server. Proceeding..."			; clean_oldHostSettings ${oldHostname}
	;;
	*) 						echo -e "This device Hostname was not set appropriately, exiting \n" && exit 0
	;;
	esac
}

#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
read_etcd(){
		ETCDCTL_API=3 printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get /$(hostname)/${KEYNAME} --print-value-only)
		echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_prefix(){
		ETCDCTL_API=3 printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix /$(hostname)/${KEYNAME} --print-value-only)
		echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_global(){
		ETCDCTL_API=3 printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
		echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for Global value"
}

write_etcd(){
		ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
		echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}

write_etcd_global(){
		ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
		echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
}

write_etcd_clientip(){
		# Variable changed to IPVALUE because the module was picking up incorrect variables and applying them to /decoderip !
		ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put /decoderip/$(hostname) "${IPVALUE}"
		echo -e "decoderip/$(hostname) set to ${IPVALUE} for Global value"
}
read_etcd_clients_ip() {
		ETCDCTL_API=3 return_etcd_clients_ip=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix /decoderip/ --print-value-only)
}

event_encoder_server() {
# Runs the server, then calls the encoder event.
	if systemctl --user is-active --quiet wavelet_controller; then
		echo -e "wavelet_controller service is running and watching for input events, continuing..."
		event_encoder
	else
		echo -e "\n bringing up Wavelet controller service, and sleeping for five seconds to allow config to settle..."
		systemctl --user start wavelet_init.service
		sleep 5
		echo -e "\n Running encoder..."
		systemctl --user start wavelet_encoder.service
	fi
}

event_server(){
	# Generate a catch-all audio sink for simultaneous output to transient devices
	/usr/local/bin/pipewire_create_output_sink.sh
	KEYNAME=INPUT_DEVICE_PRESENT
	read_etcd
	echo -e "Ensuring dnsmasq service is up.."
	systemctl enable dnsmasq.service --now
	if [[ "$printvalue" -eq 1 ]]; then
		echo -e "An input device is present on this host,
		 assuming we want an encoder running on the server.. \n"
		event_encoder_server
	else 
		echo -e "No input devices are present on this server,
		 assuming the encoder is running on a separate device.. \n"
		echo -e "\nNote this routine calls wavelet_init.service which
		 sets default video settings and clears previous settings! \n"
		systemctl --user start wavelet_init.service
	fi
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "/hostHash/$(hostname)/ipaddr" -- "${IPVALUE}"
}

event_encoder(){
	# MOVED - Encoder is now self-contained service/script
	# Registers self as a decoder in etcd for the reflector to query & include in its client args
	echo -e "Calling wavelet_encoder systemd unit.."
	systemctl --user daemon-reload
	systemctl --user start wavelet_encoder.service
}

event_decoder(){
	# Sleep for 5 seconds so we have a chance for the decoder to connect to the network
	sleep 2
	# Registers self as a decoder in etcd for the reflector to query & include in its client args
	sleep 1
	write_etcd_clientip
	# Ensure all reset, reveal and reboot flags are set to 0 so they are
	# 1) populated
	# 2) not active so the new device goes into a reboot/reset/reveal loop
	KEYVALUE="0"
	KEYNAME="/$(hostname)/DECODER_RESET"
	write_etcd_global
	KEYNAME="/$(hostname)/DECODER_REVEAL"
	write_etcd_global
	KEYNAME="/$(hostname)/DECODER_REBOOT"
	write_etcd_global
	KEYNAME="/$(hostname)/DECODER_BLANK"
	write_etcd_global
	sleep 2
	# The below will be used to generate error messages on screen, once I've written those components
	# For now useful to track hostlabel generation properly and keep the UI synced.
	KEYNAME="/$(hostname)/hostLabel"
	read_etcd_global
	echo -e "My device label is ${printvalue}\n"
	deviceLabel=${printvalue}
	KEYNAME="/hostHash/$(hostname)/label"
	read_etcd_global
	deviceHostHashlabel=${printvalue}
	echo -e "The reverse lookup label is ${printvalue}\n"
	if [[ "${deviceLabel}" == "${deviceHostHashlabel}" ]]; then
			echo -e "\nDevice label and reverse lookup label match, continuing\n"
			echo "${deviceLabel}" > /home/wavelet/hostLabel.txt
		else
			echo -e "\nDevice label and reverse lookup label DO NOT MATCH,
		 	reverting UI label in keystore and locally..\n"
			KEYNAME="/$(hostname)/hostLabel"
			KEYVALUE="${deviceHostHashLabel}"
			write_etcd_global
			echo "${deviceHostHashLabel}" > /home/wavelet/hostLabel.txt
	fi
	# Enable watcher services now all task activation keys are set to 0
	systemctl --user enable wavelet_monitor_decoder_reset.service --now
	systemctl --user enable wavelet_monitor_decoder_reveal.service --now
	systemctl --user enable wavelet_monitor_decoder_reboot.service --now
	sleep 1
	# Note - ExecStartPre=-swaymsg workspace 2 is a failable command 
	# It will always send the UG output to a second display.  
	# If not connected the primary display will be used.
	# Tries three possible GPU devices for acceleration in order of efficiency, before failing.
	# If it crashes, you have hw/driver issues someplace or an improperly configured display env.
		KEYNAME=UG_ARGS
		ug_args="--tool uv -d vulkan_sdl2:fs:keep-aspect:nocursor:nodecorate -r pipewire"
		KEYVALUE="${ug_args}"
		write_etcd
		rm -rf /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
		echo "
		[Unit]
		Description=UltraGrid AppImage executable
		After=network-online.target
		Wants=network-online.target
		[Service]
		ExecStartPre=-swaymsg workspace 2
		ExecStart=/usr/local/bin/UltraGrid.AppImage ${ug_args}
		Restart=always
		[Install]
		WantedBy=default.target" > /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
		systemctl --user daemon-reload
		systemctl --user start UltraGrid.AppImage.service
		echo -e "Decoder systemd units instructed to start..\n"
		sleep 3
		return=$(systemctl --user is-active --quiet UltraGrid.AppImage.service)
		if [[ ${return} -eq !0 ]]; then
			echo "Decoder failed to start, there may be something wrong with the system.
			\nTrying GL as a fallback, and then failing for good.."
			KEYNAME=UG_ARGS
			ug_args="--tool uv -d gl:fs -r pipewire"
			KEYVALUE="${ug_args}"
			write_etcd
			rm -rf /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
			echo "
			[Unit]
			Description=UltraGrid AppImage executable
			After=network-online.target
			Wants=network-online.target
			[Service]
			ExecStartPre=-swaymsg workspace 2
			ExecStart=/usr/local/bin/UltraGrid.AppImage ${ug_args}
			Restart=always
			[Install]
			WantedBy=default.target" > /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
		else
			:
		fi
	# Perhaps add an etcd watch or some kind of server "isalive" function here
	# Decoder should display:
	# - No incoming video
	#	if POC REF = 0 bytes received for > 1m; then
	#	wavelet_errorgen.sh build imagemagick / "Host isn't receiving video data from server, check the reflector process on the server."
	# - Consistent POC errors, codec issue
	#		if POC errors or FEC errors > 1m; then
	#		test ping
	#		if ping fine
			#	wavelet_errorgen.sh build imagemagick / "Host is experiencing high levels of corrupted frames.  Check network integrity, MTU Value and encoder settings."
	# 		if ping bad
			# - consistent packet loss, network issue
			# wavelet_errorgen.sh build imagemagick / "Host is experiencing	network connectivity issues, please check network settings.
	#		if ping DEAD
			# wavelet_errorgen.sh build imagemagick / "Host has no network connectivity
	# - other possible failure modes
	#	???
	}

event_livestream(){
	echo "In our use case, this is a decoder with an HDMI output to a Windows machine."
	rm -rf /home/wavelet/.config/systemd/user/wavelet-livestream.service
	echo "
	[Unit]
	Description=ETCD Livestream watcher
	After=network-online.target
	Wants=network-online.target
	[Service]
	ExecStart=ExecStart=etcdctl --endpoints=192.168.1.32:2379 watch uv_islivestreaming -w simple -- sh -c "/usr/local/bin/wavelet_livestream.sh"
	Restart=always
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/wavelet-livestream.service
	systemctl --user daemon-reload
	systemctl --user start wavelet-livestream.service
	echo -e "Livestream decoder systemd units instructed to start..\n"
	return=$(systemctl --user is-active --quiet wavelet-livestream.service)
	if [[ ${return} -eq !0 ]]; then
		echo "Livestream failed to start, there may be something wrong with the system."
	else
		:
	fi

# Alternatively, we can use ffmpeg to extract UV uncompressed and transcode it to YouTube or another CDN with appropriate settings.  
# Would require dual homing to an internet connection.

# API Key would be set by a simple read -p script or by the installation engineer.

# FFMPEG commands:
#				KEYNAME=wavelet_livestream_apikey
#				read_etcd
#				MYAPIKEY=${printvalue}
#				ffmpeg -protocol_whitelist tcp,udp,http,rtp,file -i http://127.0.0.1:8554/ug.sdp \
#				-re -f lavdi -i anullsrc -c:v libx264 -preset veryfast -b:v 1024k -maxrate 1024k -bufsize 4096k \
#				-vf 'format=yuv420p' -g 60 \
#				flv rtmp://a.rtmp.youtube.com/live2/${MYAPIKEY}
ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put ""
}

event_gateway_in(){
	# this will require the other systems to be setup appropriately.
	# This will probably wind up being an FFMPEG --> Ultragrid pipe 
	# or stream copy with minimal conversion so as to avoid latency.
	echo "This feature is not yet implemented"
}

event_reflector(){
	# This doesn't run UltraGrid at all, it runs only a reflector
	# It will need its own ETCD container in order to stream to its own client pool.  
	# Useful for overflow rooms or adding additional decoders with minimal latency considerations
	# Basically, some kind of impoverished multicast
	echo "This feature is not yet implemented"
}

get_ipValue(){
	# Gets the current IP address for this host to register into server etcd.
	IPVALUE=$(ip a | grep 192.168.1 | awk '/inet / {gsub(/\/.*/,"",$2); print $2}')
	# IP value MUST be populated or the decoder writes gibberish into the server
	if [[ "${IPVALUE}" == "" ]] then
			# sleep for five seconds, then call yourself again
			echo -e "\nIP Address is null, sleeping and calling function again\n"
			sleep 5
			get_ipValue
		else
			echo -e "\nIP Address is not null, testing for validity..\n"
			valid_ipv4() {
				local ip=$1 regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
				if [[ $ip =~ $regex ]]; then
					echo -e "\nIP Address is valid, continuing..\n"
					return 0
				else
					echo "\nIP Address is not valid, sleeping and calling function again\n"
					get_ipValue
				fi
			}
			valid_ipv4 "${IPVALUE}"
	fi
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "/hostHash/$(hostname)/ipaddr" -- "${IPVALUE}"
}

clean_oldHostSettings(){
	# Takes oldHostName as argument
	# deletes etcd entries for this device, then calls build_ug to regenerate everything
	# This is necessary because run_ug will not populate /hostLabel or /hostHash data for the webUI.  Only build_ug.sh will do this.
	previousHostName="${1}"
	echo -e "\nCleaning old hostname settings for ${previousHostName}\n"
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /hostLabel/$(previousHostName) --prefix
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /hostHash/$(previousHostName) --prefix
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /$(hostname) --prefix
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del $(hostname) --prefix
	/usr/local/bin/build_ug.sh
}

###
#
#
# Execute script
#
#
###
set -x
exec >/home/wavelet/run_ug.log 2>&1
echo -e "Pinging wavelet_detectv4l.sh to ensure any USB devices are detected prior to start.. \n"
/usr/local/bin/wavelet_detectv4l.sh
get_ipValue
detect_self