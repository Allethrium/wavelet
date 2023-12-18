#!/bin/bash
#
# The controller is responsible for orchestrating the rest of the system


# Define event parameters
# 3-8 are all dynamic devices that are populated dependent on what an encoder has attached, and how it has informed the etcd cluster of its presence.
event_blank="1"
event_seal="2"
event_recordtoggle="9"
event_x264sw="A"
event_x264hw="B"
event_x265sw="C"
event_x265hw="D"
event_vp9sw="E"
event_vp9hw="F"
event_rav1esw="G"
event_av1hw="H"
event_foursplit="W"
event_twosplit="X"
event_pip1="Y"
event_pip2="Z"

# Define standard default variables for encoders
uv_videoport="5004"
uv_audioport="5006"
uv_reflector="192.168.1.32"
uv_obs="192.168.1.31"
uv_livestream="192.168.1.30"
uv_encoder="-c libavcodec:encoder=libx265:gop=16:bitrate=10M"
uv_gop="16"
uv_bitrate="10M"
uv_islivestreaming="0"



###
#
# Routine codeblocks that define things which this script handles.
#
###
detect_self(){
# Controller only runs on the server.
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*) 					echo -e "I am an Encoder \n" && echo -e "Cannot run the controller on an encoder, exiting.."; exit 0
	;;
	dec*)					echo -e "I am a Decoder \n" && echo -e "Cannot run the controller on a decoder, exiting.."; exit 0
	;;
	livestream*)			echo -e "I am a Livestreamer \n" && echo -e "Cannot run the controller on a livestreamer, exiting.."; exit 0
	;;
	gateway*)				echo -e "I am an input Gateway for another video streaming system \n"  && echo -e "Cannot run the controller on a gateway, exiting.."; exit 0
	;;
	svr*)					echo -e "I am a Server. Proceeding..."  && event_server
	;;
	*) 						echo -e "This device Hostname is not set approprately, exiting \n" && exit 0
	;;
	esac
}


event_server(){
echo -e "\n Controller Called, checking input key and acting accordingly..\n"
# Now called by etcd so inputting standard values to etcd would overwrite everything every time an event happened.  
# These are populated by wavelet_init.sh
main
}


main() {
# 11/2023 - now reads uv_hash_select key for inputdata
	KEYNAME=input_update
	read_etcd_global
	if [[ "${printvalue}" == 1 ]]; then
		echo -e "\ninput_update key is set to 1, continuing with task.. \n"
	else
		echo -e "\ninput_update key is set to 0, doing nothing.. \n"
		exit 0
	fi
	KEYNAME=uv_hash_select
	read_etcd_global
	event=${printvalue}
	# Check livestream toggle UI value
	KEYNAME=/livestream/enabled
	read_etcd_global
	livestream_state=${printvalue}
		if [[ "${livestream_state}" = 0 ]]; then
			echo "Livestreaming is off, setting LiveStreaming flag to disabled"
			KEYNAME=uv_islivestreaming
			KEYVALUE="0"
	   		write_etcd_global
		else
			echo "Livestreaming is on, setting LiveStreaming flag to enabled"
			KEYNAME=uv_islivestreaming
	    	KEYVALUE="1"
    		write_etcd_global
		fi
	waveletcontroller
}


waveletcontroller() {
# Tests event input and runs appropriate event
# 11/2023 - note that hardcoded inputs are no longer used here, the case $event in line just tests static buttons from the webUI.  The rest is handled between detectv4l and wavelet_encoder, for the most part.
case $event in
	# 1
	(1) 	echo -e "Option One, Blank activated\n"						;current_event="wavelet-blank"			;wavelet-blank							;;
	# Display a black screen on all devices
	# 2
	(2) 	echo -e "Option Two, Seal activated\n"						;current_event="wavelet-seal"			;wavelet-seal							;;
	# Display a static image of a court seal (find a better image!)
	# 3-8 are all dynamic inputs populated from v4l2 (or in the future, hopefully Decklink)
	# 9
	(9)		echo -e "Recording currently Not implemented"				;is_recording=false																;;
	(T)		echo "Test Card activated"									;current_event="wavelet-testcard"		;wavelet-testcard						;;
	# System control options
	(DR)	echo -e "Decoders instructed to reload\n"					;current_event="wavelet-decoder-reboot"	;wavelet-decoder-reset					;;
	(ER)	echo -e "Encoders instructed to reload\n"					;current_event="wavelet-encoder-reboot"	;wavelet-encoder-reboot					;;
	(SR)	echo -e "Whole system reboot\n"								;current_event="wavelet-system-reboot"	;wavelet-system-reboot					;;
	(CL)	echo -e "Clearing All Input Sources from keystore..\n"		;current_event="wavelet-clear-inputs"	;wavelet-clear-inputs					;;
	(RD)	echo -e "Running re-detection of source devices..\n"		;current_event="wavelet-detect-inputs"	;/usr/local/bin/wavelet_detectv4l.sh	;;
#	if [ $recording = true ]; then
#		echo "Recording to archive file" && recording=true && wavelet_record_start
#	if [ $recording = false ]; then
#		($false) echo "Recording to archive file" && recording=true && wavelet_record_start;; 
	# does not kill any streams, instead copies stream and appends to a labeled MKV file (not implemented unless we get a real server w/ STORAGE)
	# HW and SW modes selected for compatibility reasons - some decoders don't like HW encoded video.  SW encoding will need a *FAST* CPU unless you like latency, dropped frames and glitches.
	(A)		event_x264sw	&& echo "x264 Software video codec selected, updating encoder variables"													;;
	(B)		event_x264hw 	&& echo "x264 VA-API video codec selected, updating encoder variables"														;;
	(C)		event_x265sw 	&& echo "HEVC Software video codec selected, updating encoder variables"													;;
	(D)		event_x265hw	&& echo "HEVC VA-API video codec selected, updating encoder variables"														;;
	(E)		event_vp9sw	&& echo "VP-9 Software video codec selected, updating encoder variables"														;;
	(F)		event_vp9hw 	&& echo "VP-9 Hardware video codec selected, updating encoder variables"													;;
	(G)		event_rav1esw	&& echo "|*****||EXPERIMENTAL AV1 RAV1E codec selected, updating encoder vaiables||****|"									;;
	(H)		event_av1hw	&& echo "|*****||EXPERIMENTAL AV1 VA-API codec selected, updating encoder vaiables||****|"										;;
	#
	# Multiple input modes go here (I wonder if there's a better, matrix-based approach to this?)
	#
	(W) echo "Four-way panel split activated \n"						;current_event="event_foursplit";wavelet-foursplit								;;
	(X) echo "Two-way panel split activated \n"							;current_event="event_twosplit"	;wavelet-twosplit								;;
	(Y) echo "Picture-in-Picture 1 activated \n"						;current_event="event_pip1"		;wavelet-pip1									;;
	(Z) echo "Picture-in-Picture 2 activated \n"						;current_event="event_pip2"		;wavelet-pip2									;;
	(*) echo "Unknown predefined input, passing hash to encoders.. \n"	;current_event="dynamic"		;wavelet-dynamic								;;
esac
}

#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
ETCDCTL_API=3
read_etcd(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get $(hostname)/${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for host $(hostname)"
}

read_etcd_global(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for Global value"
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


###
#
# Event codeblocks that describe events which can happen in this script
#
###

wavelet_kill_all() {
# Sets global flags for encoders and reflectors to restart
KEYNAME=reload_reflector
KEYVALUE="1"
write_etcd_global
KEYNAME=encoder_restart
KEYVALUE="1"
write_etcd_global
KEYNAME=uv_islivestreaming
KEYVALUE="0"
write_etcd_global
echo -e "Processes kill flags set, services should restart within ~5 seconds \n"
}

wavelet-blank() {
# 1
# Displays a black jpg to blank the screen fully
	current_event="wavelet-blank"
	KEYNAME=uv_input
	KEYVALUE="BLANK"
	write_etcd_global
	KEYNAME=uv_input_cmd
	KEYVALUE="-t testcard:pattern=blank"
	/usr/local/bin/wavelet_textgen.sh
	write_etcd
	# Set encoder restart flag to 1
	KEYNAME=encoder_restart
	KEYVALUE="1"
	write_etcd_global
}

wavelet-seal() {
# 2
# Serves a static image in .jpg format in a loop to the encoder.
	current_event="wavelet-seal"
	KEYNAME=uv_input
	KEYVALUE="SEAL"
	write_etcd_global
	# Always set this to SW x265, everything else breaks due to pixel format issues w/ FFMPEG/lavc
	encodervar="libavcodec:encoder=libx265:gop=6:bitrate=15M:subsampling=444:bpp=10"
	inputvar="-t file:/home/wavelet/seal.mp4:loop"
	/usr/local/bin/wavelet_textgen.sh
	cd /home/wavelet/
	ffmpeg -y -s 900x900 -video_size cif -i ny-stateseal.jpg -c:v libx265 seal.mp4
	write_etcd
	# Kill existing streaming on the SERVER
        systemctl --user stop UltraGrid.AppImage.service
        # Set encoder restart flag to 1 - this will kill other videosources
        KEYNAME=encoder_restart
        KEYVALUE="1"
        write_etcd_global
	# Now we setup a systemd unit for the encoder on the SERVER which will handle the generation of the seal stream.  Simple systemd unit.
        KEYNAME=uv_videoport
        read_etcd_global
        video_port=${printvalue}
        # Destination IP is the IP address of the UG Reflector
        destinationipv4="192.168.1.32"
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
        KillSignal=SIGTERM
        [Install]
        WantedBy=default.target" > /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
        systemctl --user daemon-reload
        systemctl --user restart UltraGrid.AppImage.service
        echo -e "Encoder systemd units instructed to start..\n"
}

wavelet-testcard() {
# T
        current_event="wavelet-testcard"
        KEYNAME=uv_input
        KEYVALUE="BLANK"
        write_etcd_global
        KEYNAME=uv_input_cmd
        KEYVALUE="-t testcard:pattern=smpte_bars"
        /usr/local/bin/wavelet_textgen.sh
        write_etcd
        # Set encoder restart flag to 1
        KEYNAME=encoder_restart
        KEYVALUE="1"
        write_etcd_global
}

wavelet-dynamic() {
	# processes device hashes submitted from the WebUI through to the encoder
	# This is really all handled on the encoder side, the only thing the controller is doing here ought to be notifying the controller of a restart..
	current_event="wavelet-dynamic"
	KEYNAME=uv_input
	read_etcd_global
	controllerInputLabel=${printvalue}
	KEYNAME=uv_hash_select
	read_etcd_global
	controllerInputHash=${printvalue}
	echo -e "\n \n Controller notified that input hash ${controllerInputHash} has been selected from webUI with the input label ${controllerInputLabel}, encoder restart commencing.. \n \n"
	# Kill existing streaming on the SERVER
	systemctl --user stop UltraGrid.AppImage.service 
	# Set encoder restart flag to 1
	KEYNAME=encoder_restart
	KEYVALUE="1"
	write_etcd_global
	KEYNAME=input_update
	KEYVALUE="0"
	echo -e "\n Task completed, resetting input_update key to 0.. \n"
	write_etcd_global
}

wavelet_foursplit() {
	current_event="wavelet_foursplit"
	KEYNAME=uv_input
	KEYVALUE="Multi source mix"
	write_etcd_global
	controllerInputLabel=${printvalue}
	KEYNAME=uv_hash_select
	read_etcd_global
	controllerInputHash=${printvalue}
	echo -e "\n \n Controller notified that the Four-way split input hash has been selected from the WebUI.  Encoder will do its best to generate a software mix of up to four available input devices. \n \n "
	# Kill existing streaming on the SERVER
        systemctl --user stop UltraGrid.AppImage.service
        # Set encoder restart flag to 1
        KEYNAME=encoder_restart
        KEYVALUE="1"
        write_etcd_global
        KEYNAME=input_update
        KEYVALUE="0"
        echo -e "\n Task completed, resetting input_update key to 0.. \n"
        write_etcd_global
}
# These events contain additional codec-specific settings that have been found to work acceptably well on the system.
# Since they are tuned by hand, you probably won't want to modify them unless you know exactly what you're doing.
# Proper operation depends on bandwidth, latency, network quality, encoder speed.  It's highly hardware dependent.
# These operate in conjunction with the standard defined variables set above.  


event_x264hw() {
	KEYNAME=uv_encoder
	KEYVALUE="libavcodec:encoder=h264_qsv:gop=12:bitrate=25M"
	write_etcd_global
	echo -e "x264 Hardware acceleration activated, Bitrate 25M \n"
}

event_x264sw() {
	KEYNAME=uv_encoder
	KEYVALUE="libavcodec:encoder=libx264:gop=12:bitrate=25M"
	write_etcd_global
	echo -e "x264 Software acceleration activated, Bitrate 25M \n"
}

event_x265sw() {
	KEYNAME=uv_encoder
	KEYVALUE="libavcodec:encoder=libx265:gop=12:bitrate=15M:subsampling=444:q=12:bpp=10"
	write_etcd_global
	echo -e "x265 Software acceleration activated, Bitrate 15M \n"
}	

event_x265hw() {
# working on tweaking these values to something as reliable as possible.
	KEYNAME=uv_encoder
	KEYVALUE="libavcodec:encoder=hevc_qsv:bitrate=7M:gop=6:subsampling=444"
#	KEYVALUE="libavcodec:encoder=hevc_qsv:gop=12:bitrate=15M:bpp=10:subsampling=444:q=0:scenario=remotegaming:profile=main10"
	write_etcd_global
	echo -e "x265 Hardware acceleration activated, Bitrate 20M \n"
}

event_vp9sw() {
	KEYNAME=uv_encoder
	KEYVALUE="libavcodec:encoder=libvpx-vp9:gop=12:bitrate=20M"
	write_etcd_global
	echo -e "VP9 Software acceleration activated, Bitrate 20M \n"
}

event_vp9hw() {
	KEYNAME=uv_encoder
	KEYVALUE="libavcodec:encoder=vp9_qsv:gop=12:bitrate=20M:q=0:subsampling=444:bpp=10"
	write_etcd_global
	echo -e "VP9 Hardware acceleration activated, Bitrate 20M \n"
}

event_rav1esw() {
	KEYNAME=uv_encoder
	KEYVALUE="libavcodec:encoder=librav1e"
	write_etcd_global
	echo -e "AV1 Software acceleration activated \n"
}

event_av1hw() {
	KEYNAME=uv_encoder
	KEYVALUE="libavcodec:encoder=av1_qsv"
	write_etcd_global
	echo -e "AV1 Hardware acceleration activated \n"
}

wavelet-foursplit() {
# W
	current_event="wavelet-foursplit"
	KEYNAME=uv_input
	KEYVALUE=FOURSPLIT
	write_etcd_global
        # Set encoder restart flag to 1
        KEYNAME=encoder_restart
        KEYVALUE="1"
        write_etcd_global
}
wavelet-twosplit() {
# W
	current_event="wavelet-twosplit"
	KEYNAME=uv_input
	KEYVALUE=TWOSPLIT
	write_etcd_global
        # Set encoder restart flag to 1
        KEYNAME=encoder_restart
        KEYVALUE="1"
        write_etcd_global
}
wavelet-pip1() {
# Doesn't currently work, so disable.
	current_event="wavelet-pip1"
	KEYNAME=uv_input
	KEYVALUE=PIP1
	write_etcd_global
        # Set encoder restart flag to 1
        KEYNAME=encoder_restart
        KEYVALUE="1"
        write_etcd_global
}
wavelet-pip2() {
# Doesn't currently work, so disable.
	current_event="wavelet-pip2"
	KEYNAME=uv_input
	KEYVALUE=PIP2
	write_etcd_global
        # Set encoder restart flag to 1
        KEYNAME=encoder_restart
        KEYVALUE="1"
        write_etcd_global
}


wavelet-decoder-reset() {
# Finds all decoders and sets client reSET flag.  This restarts UltraGrid without a full system reboot.
	return_etcd_clients_ip=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix decoderip/ --keys-only)
	for host in ${return_etcd_clients_ip}; do
		etcdctl --endpoints=${ETCDENDPOINT} put "${host}/DECODER_RESET" -- "1"
		echo -e "DECODER_RESET flag enabled for ${host}..\n"
	done
	echo -e "Decoder tasks instructed to reset on all attached decoders.\n"
}

wavelet-encoder-reboot() {
# Finds all encoders and sets client reboot flag (need to implement reboot watcher service)
# re-use the reflector code and then foreach hostname set it to reboot encoders
# UltraGrid encoder task will SIGTERM every time a source is changed, this on the other hand reboots the WHOLE encoder.
	etcdctl --endpoints=${ETCDENDPOINT} put "ENCODER_REBOOT" -- "1"
	echo -e "Encoder reboot flag enabled, encoders will hard reset momentarily.."
}

wavelet-system-reboot() {
# This hard reboots everything, including the server.
# set reboot flag on every host in etcd
	etcdctl --endpoints=${ETCDENDPOINT} put "SYSTEM_REBOOT" -- "1"
	echo -e "All hosts instructed to hard reset.  Server and all reachable devices will restart immediately..\n"
}

wavelet-clear-inputs() {
# Removes all input devices from their appropriate prefixes.
# Until I fix the detection/removal stuff so that it works perfectly, this will effectively clean out any cruft from 'stuck'
# source devices which no longer exist, but still populate on the UI.
# bad solution
	etcdctl --endpoints=http://192.168.1.32:2379 del "interface" --prefix
  	etcdctl --endpoints=http://192.168.1.32:2379 del "/interface" --prefix
  	etcdctl --endpoints=http://192.168.1.32:2379 del "/hash" --prefix
  	etcdctl --endpoints=http://192.168.1.32:2379 del "/short" --prefix
  	etcdctl --endpoints=http://192.168.1.32:2379 del "/long" --prefix
  	echo -e "All interface devices and their configuration data, as well as labels have been deleted\n
  	Plugging in a new device will cause the detection module to run again.\n"
}

wavelet-detect-inputs() {
# Tells detectv4l to run on everything
  	echo -e "\nAll devices now redetecting available input video sources..\n"
  	etcdctl --endpoints=http://192.168.1.32:2379 set "DEVICE_REDETECT" -- "1"

}



###
#
# execute main function
#
###

exec >/home/wavelet/controller.log 2>&1
detect_self