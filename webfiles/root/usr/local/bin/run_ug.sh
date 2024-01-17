#!/bin/bash
# Checks device hostname to define behavior and launches ultragrid from AppImage as appropriate
# Script runs as a user service, calls other user services.  Nothing here should be asking for root.

detect_self(){
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*) 					echo -e "I am an Encoder \n"; event_encoder
	;;
	decX.wavelet.local)			echo -e "I am a Decoder, but my hostname is generic.  An error has occurred at some point, and needs troubleshooting.\n Terminating process. \n"; exit 0
	;;
	dec*)					echo -e "I am a Decoder \n"; event_decoder
	;;
	livestream*)				echo -e "I am a Livestream ouput gateway \n"; event_livestream
	;;
	gateway*)				echo -e "I am an input Gateway for another video streaming system \n"; event_gateway
	;;
	svr*)					echo -e "I am a Server."; event_server
	;;
	*) 					echo -e "This device Hostname is not set approprately, exiting \n"; exit 0
	;;
	esac
}

#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
read_etcd(){
        ETCDCTL_API=3 printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get $(hostname)/${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_prefix(){
        ETCDCTL_API=3 printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix $(hostname)/${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_global(){
        ETCDCTL_API=3 printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for Global value"
}

write_etcd(){
        ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}

write_etcd_global(){
        ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
}

write_etcd_clientip(){
        ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put decoderip/$(hostname) "${KEYVALUE}"
        echo -e "$(hostname) set to ${KEYVALUE} for Global value"
}
read_etcd_clients_ip() {
        ETCDCTL_API=3 return_etcd_clients_ip=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix decoderip/ --print-value-only)
}


event_encoder_server(){
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
# Note that if we want to wind up orchestrating the existing MageWell NDI encoders, this is going to have to be expanded.
# Suggest some scanner service that enumerates and stores them in ETCD, then sets another "present" flag
	KEYNAME=INPUT_DEVICE_PRESENT
	read_etcd
	echo -e "Ensuring dnsmasq service is up.."
	systemctl restart dnsmasq.service
	if [[ "$printvalue" -eq 1 ]]; then
		echo -e "An input device is present on this host, assuming we want an encoder running on the server.. \n"
		event_encoder_server
	else 
		echo -e "No input devices are present on this server, assuming the encoder is running on a separate device.. \n"
		echo -e "\nNote this routine calls wavelet_init.service which sets default video settings and clears previous settings! \n"
		systemctl --user start wavelet_init.service
	fi
}


event_encoder(){
# MOVED - Encoder is now self-contained service/script
	echo -e "Calling wavelet_encoder systemd unit.."
	systemctl --user start wavelet_encoder.service
}


event_decoder(){
# Tries three possible GPU outputs before failing.
# If it crashes, you have hw/driver issues someplace or an improperly configured display env.
# Registers self as a decoder in etcd for the reflector to query & include in its client args

KEYVALUE=$(ip a | grep 192.168.1 | awk '/inet / {gsub(/\/.*/,"",$2); print $2}')
# Can be modified from webUI, populates with hostname by default
ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put decoderlabel/$(hostname) "$(hostname)"
write_etcd_clientip

# Install reset and reveal watcher services
echo "
[Unit]
Description=Decoder Reset Watcher
After=network-online.target
Wants=network-online.target
[Service]
ExecStart=etcdctl --endpoints=192.168.1.32:2379 watch $(hostname)/DECODER_RESET -w simple -- sh -c "/usr/local/bin/wavelet_decoder_reset.sh"
Restart=Always
[Install]
WantedBy=default.target" > /home/wavelet/.config/systemd/user/wavelet_monitor_decoder_reset.service

echo "
[Unit]
Description=Decoder Reveal Watcher
After=network-online.target
Wants=network-online.target
[Service]
ExecStart=etcdctl --endpoints=192.168.1.32:2379 watch $(hostname)/DECODER_REVEAL -w simple -- sh -c "/usr/local/bin/wavelet_decoder_reveal.sh"
Restart=Always
[Install]
WantedBy=default.target" > /home/wavelet/.config/systemd/user/wavelet_monitor_decoder_reveal.service

systemctl daemon-reload
systemctl --user enable wavelet_monitor_decoder_reset.service --now
systemctl --user enable wavelet_monitor_decoder_reveal.service --now

# Note - ExecStartPre=-swaymsg workspace 2 is a failable command 
# It will always send the UG output to a second display.  If not connected the primary display will be used
# This is an impoverished version of a multihead display management system.
KEYNAME=UG_ARGS
ug_args="--tool uv -d vulkan_sdl2:fs --param use-hw-accel"
KEYVALUE="${ug_args}"
write_etcd

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
sleep 5
return=$(systemctl --user is-active --quiet UltraGrid.AppImage.service)
if [[ ${return} -eq !0 ]]; then
	echo "SystemD unit failed with Vulkan_sdl2 driver for hwaccel, trying with GL driver.."
	KEYNAME=UG_ARGS
	ug_args="--tool uv -d gl:fs --param use-hw-accel"
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
	return=$(systemctl --user is-active --quiet UltraGrid.AppImage.service)
	if [[ ${return} -eq !0 ]]; then
		echo "Decoder failed to start, there may be something wrong with the system. \n Trying SDL as a fallback and then failing for good.."
		KEYNAME=UG_ARGS
		ug_args="--tool uv -d sdl:fs --param use-hw-accel"
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
else
	:
fi
# Perhaps add an etcd watch or some kind of server "isalive" function here
# The decoders should reboot on their own if the server is down
# assumption would be server was getting replaced, and they'd need to reregister on boot?
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

###
#
#
# Execute script
#
#
###
set -x
exec >/home/wavelet/run_ug.log 2>&1
echo -e "Pinging detectv4l.sh to ensure any USB devices are detected prior to start.. \n"
/usr/local/bin/detectv4l.sh
detect_self
