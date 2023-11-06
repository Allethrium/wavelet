#!/bin/bash
#
# The controller is responsible for orchestrating the rest of the system


# Define event parameters
event_livestream="0"
event_blank="1"
event_seal="2"
event_evidence="4"
event_hdmi="4"
event_evidence_hdmi="5"
event_hybrid="6"
event_witnesscam="7"
event_courtroomcam="8"
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
uv_encoder="-c libavcodec:encoder=h264_vaapi:gop=12:bitrate=20M"
uv_gop="12"
uv_bitrate="20M"
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
set -x
echo -e "\n Controller Called, checking input key and acting accordingly..\n"
# Now called by etcd so inputting standard values to etcd would overwrite everything every time an event happened.  
# These are populated by wavelet_init.sh
main
}


main() {
KEYNAME=input
read_etcd_global
event=${printvalue}
waveletcontroller
}


waveletcontroller() {
# Tests event input and runs appropriate event
case $event in
	# 1
	(1) echo -e "Option One, Blank activated\n"							;current_event="wavelet-blank"			;wavelet-blank;;
	# Display a black screen on all devices
	# 2
	(2) echo -e "Option Two, Seal activated\n"							;current_event="wavelet-seal"			;wavelet-seal;;
	# Display a static image of a court seal (find a better image!)
	# 3
	(3) echo -e "Option Three, Document Camera activated\n"				;current_event="wavelet-evidence"		;wavelet-evidence;;
	# Feed from USB Document Camera attached to encoder
	# 4
	(4) echo -e "Option Four, Counsel HDMI Input Activated\n"			;current_event="wavelet-hdmi"			;wavelet-hdmi;;
	# Feed from HDMI Input, generally anticipated to be an HDMI switcher from the Defendent/Plaintiff tables and display from Counsel's laptop
	# 5
	(5) echo -e "Option Five, HDMI Capture Input activated\n"			;current_event="wavelet-evidence-hdmi"	;wavelet-evidence-hdmi;;
	# An additional HDMI feed from another device.  Can be installed or not, anticipate some kind of permanently present Media Player or similar
	# Probably too interchangable with counsel's HDMI input but strikes me as useful enough to maintain here.
	# 6
	(6) echo -e "Option Six, Hybrid Mode activated\n"					;current_event="wavelet-hybrid"			;wavelet-hybrid;;
	# Switch to a screen capture pulling a Teams meeting window via HDMI input.  
	# Target machine should have HDMI Input to grab Waveket Output from a decoder box as a video source
	# Target machine should have HDMI output to Wavelet so the teams gallery can be seen, think HDMI-USB dongle
	# Needs configuring by installation engineers
	# 7
	(7) echo -e "Option Seven, Witness cam activated\n"					;current_event="wavelet-witness"		;wavelet-witness;;
	# feed from Webcam or any kind of RTP/RTSP stream, generally anticipated to capture the Witness Box and Well for detail view
	# Needs configuring by installation engineers
	# 8
	(8) echo -e "Option Eight, Courtroom Wide-angle activated\n"		;current_event="wavelet-courtroomcam"	;wavelet-courtroomcam;;
	# feed from wide-angle Courtroom camera generally anticipated to capture the Well + Jury zone, perhaps front row of gallery
	# Needs configuring by installation engineers
	# 9
	(9) echo "Not implemented"											;is_recording=false;;
#	if [ $recording = true ]; then
#		echo "Recording to archive file" && recording=true && wavelet_record_start
#	if [ $recording = false ]; then
#		($false) echo "Recording to archive file" && recording=true && wavelet_record_start;; 
	# does not kill any streams, instead copies stream and appends to a labeled MKV file (not implemented)
	#
	# 0
	#
	(0)	echo "LiveStream toggle set.."									;event_livestream;;
	# starts and stops livestreaming as a toggle, then sets livestreamer variable appropriately.
	#
	# video codec selection
	# HW and SW modes selected for compatibility reasons - some decoders don't like HW encoded video.  SW encoding will need a *FAST* CPU unless you like latency, dropped frames and glitches.
	(A)		event_x264sw	&& echo "x264 Software video codec selected, updating encoder variables";;
	(B)		event_x264hw 	&& echo "x264 VA-API video codec selected, updating encoder variables";;
	(C)		event_x265sw 	&& echo "HEVC Software video codec selected, updating encoder variables";;
	(D)		event_x265hw	&& echo "HEVC VA-API video codec selected, updating encoder variables";;
	(E)		event_vp9sw		&& echo "VP-9 Software video codec selected, updating encoder variables";;
	(F)		event_vp9hw 	&& echo "VP-9 Hardware video codec selected, updating encoder variables";;
	(G)		event_rav1esw	&& echo "|*****||EXPERIMENTAL AV1 RAV1E codec selected, updating encoder vaiables||****|";;
	(H)		event_av1hw		&& echo "|*****||EXPERIMENTAL AV1 VA-API codec selected, updating encoder vaiables||****|";;
	#
	# Multiple input modes go here (I wonder if there's a better, matrix-based approach to this?)
	#
	(W) echo "Four-way panel split activated \n"						;current_event="event_foursplit"	;wavelet-foursplit;;
	(X) echo "Two-way panel split activated \n"							;current_event="event_twosplit"		;wavelet-twosplit;;
	(Y) echo "Picture-in-Picture 1 activated \n"						;current_event="event_pip1"		;wavelet-pip1;;
	(Z) echo "Picture-in-Picture 2 activated \n"						;current_event="event_pip2"		;wavelet-pip2;;
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


event_livestream() {
# Livestream switches an additional dedicated livestream decoder ON.
# GLOBAL flag for entire system
	KEYNAME=uv_islivestreaming
	read_etcd_global
	livestreaming=$printvalue
			if [[ "$livestreaming" = 0 ]]; then
				echo "Livestreaming is off, setting LiveStreaming flag to Enabled"
				KEYNAME=uv_islivestreaming
	    	    KEYVALUE="1"
	    	    write_etcd_global
	    	    KEYNAME=encoder_restart
	    	    KEYVALUE="1"
	    	    write_etcd_global
			else
				echo "Livestreaming is on, setting LiveStreaming flag to Disabled"
	    	    KEYNAME=uv_islivestreaming
	    	    KEYVALUE="0"
	    	    write_etcd_global
	    	    KEYNAME=encoder_restart
	    	    KEYVALUE="1"
	    	    write_etcd_global
fi
}

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

wavelet_kill_livestream() {
# A dedicated routine to kill FFMPEG and UG on the livestream box
	KEYNAME=uv_islivestreaming
	read_etcd_global
			if [[ "$livestreaming" = "0" ]]; then
				echo "Livestreaming is off, nothing to do!"
				:
			else
				echo "Livestreaming is enabled, killing processes on livestreamer device"
				# placeholder either ssh or run systemctl to kill ffmpeg + uv as necessary on livestream box
				# either that or kill the IP address on the reflector.  It's the only way to be sure..
	    	    KEYNAME=uv_islivestreaming
	    	    KEYVALUE="0"
	    	    write_etcd_global
		    KEYNAME=encoder_restart
	    	    KEYVALUE="1"
	    	    write_etcd_global
			fi
}

wavelet-blank() {
# 1
# Displays a black jpg to blank the screen fully
	current_event="wavelet-blank"
	KEYNAME=uv_input
	KEYVALUE="BLANK"
	write_etcd_global
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
        # Set encoder restart flag to 1
        KEYNAME=encoder_restart
        KEYVALUE="1"
        write_etcd_global
}

wavelet-evidence() {
# 3
# Evidence camera 
# run_ug.sh & detectv4l.sh on the encoder system decides specifics
	current_event="wavelet-evidence"
#	KEYNAME=uv_islivestreaming
#	read_etcd_global
#	livestreaming=$printvalue
#			if [[ "$livestreaming" = "0" ]]; then
#				echo "Livestreaming is off, setting standard value for $current_event"
#				KEYNAME=uv_filter
#	    	    KEYVALUE="FilterEvidenceCam"
#	    	    write_etcd_global
#			else
#				echo "Livestreaming is enabled, setting Livestream value for $current_event"
#	    	    KEYNAME=uv_filter
#	    	    KEYVALUE="FilterEvidenceCamLiveStream"
#	    	    write_etcd_global
#			fi
	KEYNAME=uv_input
	KEYVALUE="EVIDENCECAM1"
	write_etcd_global
    # Set encoder restart flag to 1
    KEYNAME=encoder_restart
	KEYVALUE="1"
    write_etcd_global
}

wavelet-hdmi() {
# 4
# Counsel HDMI Input, anticipating a hardened HDMI switcher A-B input, C Output direct to HDMI Capture device on encoder
	current_event="wavelet-hdmi"
	KEYNAME=uv_input
	KEYVALUE=HDMI1
	write_etcd_global
        # Set encoder restart flag to 1
        KEYNAME=encoder_restart
        KEYVALUE="1"
        write_etcd_global
}

wavelet-evidence-hdmi() {
# 5
# Counsel HDMI Input, anticipating a hardened HDMI switcher A-B input, C Output direct to HDMI Capture device on encoder
	current_event="wavelet-evidence-hdmi"
	KEYNAME=uv_input
	KEYVALUE=HDMI2
	write_etcd_global
        # Set encoder restart flag to 1
        KEYNAME=encoder_restart
        KEYVALUE="1"
        write_etcd_global
}

wavelet-hybrid() {
# 6
# Hybrid mode.  This involves using dual HDMI capture cards or a dual-home Windows PC to allow UG inputs and outputs with a live Teams call.  
# Care needs to be taken during operation re; Hall of Mirrors effect due to recursion in the video streams.
	current_event="wavelet-hybrid"
	KEYNAME=uv_input
	KEYVALUE=HYBRID
	write_etcd_global
        # Set encoder restart flag to 1
        KEYNAME=encoder_restart
        KEYVALUE="1"
        write_etcd_global
}

wavelet-witnesscam() {
# 7
# Witness Camera setup appropriately for detail view on Counsel/Witness/area to ensure Witness is not being coached etc.
	current_event="wavelet-witnesscam"
	KEYNAME=uv_input
	KEYVALUE=WITNESS
	write_etcd_global
        # Set encoder restart flag to 1
        KEYNAME=encoder_restart
        KEYVALUE="1"
        write_etcd_global
}

wavelet-courtroomcam() {
# 8
# Wide-angle Courtroom camera capturing the entire well + some of the gallery, typically would be a wall / ceiling installation.  
	current_event="wavelet-courtroomcam"
	KEYNAME=uv_input
	KEYVALUE=COURTOOM
	write_etcd_global
        # Set encoder restart flag to 1
        KEYNAME=encoder_restart
        KEYVALUE="1"
        write_etcd_global
}

# These events contain additional codec-specific settings that have been found to work acceptably well on the system.
# Since they are tuned by hand, you probably won't want to modify them unless you know exactly what you're doing.
# Proper operation depends on bandwidth, latency, network quality, encoder speed.  It's highly hardware dependent.
# These operate in conjunction with the standard defined variables set above.  


event_x264hw() {
	KEYNAME=uv_encoder
	KEYVALUE="libavcodec:encoder=h264_vaapi:gop=12:bitrate=20M"
	write_etcd_global
	echo -e "x264 Software acceleration activated, Bitrate 20M \n"
}

event_x264sw() {
	KEYNAME=uv_encoder
	KEYVALUE="libavcodec:encoder=libx264:gop=12:bitrate=20M"
	write_etcd_global
	echo -e "x264 Software acceleration activated, Bitrate 20M \n"
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
	KEYVALUE="libavcodec:encoder=hevc_qsv:gop=12:bitrate=15M:bpp=10:subsampling=444:q=0:scenario=remotegaming:profile=main10"
	write_etcd_global
	echo -e "x265 Hardware acceleration activated, Bitrate 15M \n"
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
	KEYVALUE="libavcodec:encoder=av1_qsv:preset=veryfast"
	write_etcd_global
	echo -e "AV1 Hardware acceleration activated \n"
}

wavelet-foursplit() {
# W
# Witness Camera setup appropriately for detail view on Counsel/Witness/area to ensure Witness is not being coached etc.
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
# Witness Camera setup appropriately for detail view on Counsel/Witness/area to ensure Witness is not being coached etc.
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
# W
# Witness Camera setup appropriately for detail view on Counsel/Witness/area to ensure Witness is not being coached etc.
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
# W
# Witness Camera setup appropriately for detail view on Counsel/Witness/area to ensure Witness is not being coached etc.
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

###
#
# execute main function
#
###

set -x
exec >/home/wavelet/controller.log 2>&1
detect_self
