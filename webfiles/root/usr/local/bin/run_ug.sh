
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
	*) 						echo -e "This device Hostname is not set appropriately, exiting \n"; exit 0
	;;
	esac
}

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
delete_etcd_key(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key" "${KEYNAME}"
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
		event_encoder
	fi
}

event_server(){
	# The server is a special case because it serves blanks screen, static image and test bars.
	# As a result, instead of run_ug it calls wavelet_init.service
	# Generate a catch-all audio sink for simultaneous output to transient devices
	# /usr/local/bin/pipewire_create_output_sink.sh
	# Ensure web interface is up
	KEYNAME=INPUT_DEVICE_PRESENT; read_etcd
	systemctl --user start http-php-pod.service
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
}

event_encoder(){
	# Registers self as a decoder in etcd for the reflector to query & include in its client args
	echo -e "Calling wavelet_encoder systemd unit.."
	# I've added a blank bit here too.. it might make more sense to call it "host blank" though..
	KEYNAME="DECODER_BLANK"; KEYVALUE="0"; write_etcd
	systemctl --user daemon-reload
	echo -e "Pinging wavelet_detectv4l.sh to ensure any USB devices are detected prior to start.. \n"
	/usr/local/bin/wavelet_detectv4l.sh
	systemctl --user start wavelet_encoder.service
}

event_decoder(){
	# Sleep for 5 seconds so we have a chance for the decoder to connect to the network
	sleep 3
	# Registers self as a decoder in etcd for the reflector to query & include in its client args
	sleep 1
	write_etcd_clientip
	# Ensure all reset, reveal and reboot flags are set to 0 so they are
	# 1) populated
	# 2) not active so the new device goes into a reboot/reset/reveal loop
	KEYNAME="DECODER_RESET"; KEYVALUE="0"; write_etcd
	KEYNAME="DECODER_REVEAL"; write_etcd
	KEYNAME="DECODER_REBOOT"; write_etcd
	KEYNAME="DECODER_BLANK"; write_etcd
	sleep 1
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
		KEYNAME=UG_ARGS; ug_args="--tool uv -d vulkan_sdl2:fs:keep-aspect:nocursor:nodecorate -r pipewire"; KEYVALUE="${ug_args}"; write_etcd
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
		systemctl --user restart UltraGrid.AppImage.service
		echo -e "Decoder systemd units instructed to start..\n"
		sleep 3
		return=$(systemctl --user is-active --quiet UltraGrid.AppImage.service)
		if [[ ${return} -eq !0 ]]; then
			echo "Decoder failed to start, there may be something wrong with the system.
			\nTrying GL as a fallback, and then failing for good.."
			KEYNAME=UG_ARGS; ug_args="--tool uv -d gl:fs -r pipewire"; KEYVALUE="${ug_args}"; write_etcd
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
			systemctl --user restart UltraGrid.AppImage.service
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
	get_ipValue
	# Resolved is necessary on decoders, encoders
	systemctl enable systemd-resolved.service --now
	}

event_livestream(){
	rm -rf /home/wavelet/.config/systemd/user/wavelet_livestream.service
	/usr/local/bin/wavelet_etcd_interaction.sh "generate_service" "wavelet_livestream"
	systemctl --user start wavelet_livestream.service
	echo -e "Livestream watcher systemd unit instructed to start..\n"
	return=$(systemctl --user is-active --quiet wavelet_livestream.service)
	if [[ ${return} -eq !0 ]]; then
		echo "Livestream watcher failed to start, there may be something wrong with the system."
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
	KEYNAME="livestreaming_cmd"; KEYVALUE="${generatedCommand}"; write_etcd_global
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
	# Identify Ethernet interfaces by checking for "eth" in their name
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
					KEYNAME="/hostHash/$(hostname)/ipaddr"; keyvalue="${ip}"; write_etcd_global
				else
					echo "\nIP Address is not valid, sleeping and calling function again\n"
					get_ipValue
				fi
			}
			valid_ipv4 "${IPVALUE}"
	fi
}

detect_disable_ethernet(){
	if [[ -f /var/no.wifi ]]; then
		echo -e "The /var/no.wifi flag is set.  Please remove this file if this host should utilize wireless connectivity."
	else
		# We disable ethernet preferentially if we have two active connections
		# This prevents some of the IP detection automation from having issues.
		# This should have been done already once the decoder provisioned and successfully connected to wifi.
		# Add another filter to exclude veth interfaces
		for interface in $(ip link show | awk '{print $2}' | grep ":$" | cut -d ':' -f1); do
			if [[ $(nmcli dev show "${interface}" | grep "connected") ]] && \
			[[ $(nmcli dev show "${interface}" | grep "ethernet") ]] && \
			[[ $(nmcli device status | grep -a 'wifi.*connect') ]] && \
			[[ $(nmcli dev show "${interface}") != *"veth"* ]]; then
				echo -e "${interface} is an ethernet connection, active WiFi connection also detected..."
				wifiFound="1"
				ethernetFound="1"
				ethernetInterface="${interface}"
			fi
		done
		nmcli device down "${ethernetInterface}"
		echo -e "Interface ${ethernetInterface} has been disabled.\n\nTo re-enable, you can use:\nnmcli device up ${ethernetInterface}\n\nor:\nnmtui\n"
	fi
}

set_ethernet_mtu(){
	# Attempting to set an MTU of 9000 will break all wireless clients.  Leaving this in encase we can work around it.
	for interface in $(ip link show | awk '{print $2}' | grep ":$" | cut -d ':' -f1); do
		if [[ $(ip link show dev "${interface}" | grep "link/ether") ]]; then 
			ip link set dev ${interface} mtu 1500
		fi
	done
}

wifi_connect_retry(){
	if [[ -f /var/no.wifi ]]; then
		echo "Device configured to ignore wifi!"
		exit 0
	fi
	
	if nmcli con show --active | grep -q 'wifi'; then
		echo -e "WiFi device detected, proceeding.."
		# Look for active wifi
		if [[ $(nmcli device status | grep -a 'wifi.*connect') ]]; then
			echo -e "Active WiFi connection available! return 0"
			exit 0
		else
			echo -e "Attempting to connect to WiFi.  If this device is NOT planned to be on WiFi, run the command:\n"
			echo -e "touch /var/no.wifi"
			while ! connectwifi; do
				sleep 2
			done
		fi
	else
		echo -e "This machine has no wifi connectivity, exiting..\n"
		exit 0
	fi
}

###
#
#
# Execute script
#
#
###
#set -x
exec >/home/wavelet/run_ug.log 2>&1
detect_disable_ethernet
#set_ethernet_mtu
get_ipValue
detect_self