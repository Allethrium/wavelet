#!/bin/bash
#
# The controller is responsible for orchestrating the rest of the system


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
	svr*)			echo -e "I am a Server. Proceeding..." && event_server
	;;
	*) 				echo -e "This device Hostname is not set approprately, exiting \n" &&	exit 0
	;;
	esac
}

event_server(){
echo -e "\n\n***Controller Called, checking input key and acting accordingly..***"
main
}

main() {
	KEYNAME=input_update; read_etcd_global
	if [[ "${printvalue}" == 1 ]]; then
		echo -e "input_update key is set to 1, continuing with task..\n"
	else
		echo -e "input_update key is set to 0, doing nothing..\n"
		exit 0
	fi
	KEYNAME="uv_hash_select"; read_etcd_global; event="${printvalue}"
	KEYNAME="uv_hash_select_old"; read_etcd_global; eventPrevious="${printvalue}"
	if [[ ${event} == ${eventPrevious} ]];  then
		echo "Event ID matches the previous input update, doing nothing."
		exit 0
	fi
	# Check livestream toggle UI value
	KEYNAME="/livestream/enabled"; read_etcd_global; livestream_state="${printvalue}"
		if [[ "${livestream_state}" = 0 ]]; then
			echo "Livestreaming is off, setting LiveStreaming flag to disabled"
			KEYNAME=uv_islivestreaming; KEYVALUE="0"; write_etcd_global
		else
			echo "Livestreaming is on, setting LiveStreaming flag to enabled"
			KEYNAME=uv_islivestreaming; KEYVALUE="1"; write_etcd_global
		fi
	bannerActive=0
	KEYNAME="/banner/enabled"; read_etcd_global
	if [[ ${printvalue} == "1" ]]; then
		bannerActive=${printvalue}
	fi
	if systemctl is-active --user --quiet wavelet_encoder.service; then 
		echo "Server Encoder process running, continuing"
		waveletcontroller
	else 
		echo "Server Encoder process is not running, attempting to start before proceeding.."
		systemctl --user start run_ug.service
		waveletcontroller
	fi
}


waveletcontroller() {
# Tests event input and runs appropriate event
case $event in
	# 1
	(1) 	echo -e "Option One, Blank activated\n"						;current_event="wavelet-blank"			;wavelet_blank								;;
	# Display a black screen on all devices
	# 2
	(2) 	echo -e "Option Two, Seal activated\n"						;current_event="wavelet-seal"			;wavelet_seal								;;
	# Display a static image of a court seal (find a better image!)
	# 3-8 are all dynamic inputs populated from v4l2 (or in the future, hopefully Decklink)
	# 9
	(9)		echo -e "Recording currently Not implemented"				;is_recording=false																	;;
	(T)		echo "Test Card activated"									;current_event="wavelet-testcard"		;wavelet_testcard							;;
	# System control options
	# (DR)	echo -e "Decoders instructed to reload\n"					;current_event="wavelet-decoder-reboot"	;wavelet_decoder-reset						;;
	(ER)	echo -e "Encoders instructed to reload\n"					;current_event="wavelet-encoder-reboot"	;wavelet_encoder_reboot						;;
	(SR)	echo -e "Whole system reboot\n"								;current_event="wavelet-system-reboot"	;wavelet_system_reboot						;;
	(CL)	echo -e "Clearing All Input Sources from keystore..\n"		;current_event="wavelet-clear-inputs"	;wavelet_clear_inputs						;;
	(RD)	echo -e "Running re-detection of source devices..\n"		;current_event="wavelet-detect-inputs"	;wavelet_refresh							;;
	# HW and SW modes selected for compatibility reasons - some decoders don't like HW encoded video.  SW encoding will need a *FAST* CPU unless you like latency, dropped frames and glitches.
	(A)		event_x264sw						&& echo "x264 Software video codec selected, updating encoder variables"						;;
	(B)		event_x264hw 						&& echo "x264 VA-API video codec selected, updating encoder variables"							;;
	(C)		event_libx265sw 					&& echo "HEVC Software libx265 video codec selected, updating encoder variables"				;;
	(C1)	event_libx265sw_low 				&& echo "HEVC Software libx265 video codec selected, updating encoder variables"				;;
	(D)		event_libsvt_hevc_sw				&& echo "HEVC Software svt_hevc video codec selected, updating encoder variables"				;;
	(D1)	event_libsvt_hevc_sw_zerolatency	&& echo "HEVC Software svt_hevc video codec selected, updating encoder variables"				;;
	(D2)	event_x265hw_qsv					&& echo "HEVC QSV video codec selected, updating encoder variables"								;;
	(D3)	event_x265hw_vaapi					&& echo "HEVC QSV video codec selected, updating encoder variables"								;;
	(E)		event_vp9sw							&& echo "VP-9 Software video codec selected, updating encoder variables"						;;
	(E1)	event_vp8sw							&& echo "VP-8 Software video codec selected, updating encoder variables"						;;
	(F)		event_vp9hw 						&& echo "VP-9 Hardware video codec selected, updating encoder variables"						;;
	(G)		event_rav1esw						&& echo "|*****||EXPERIMENTAL AV1 RAV1E codec selected, updating encoder variables||****|"		;;
	(H)		event_av1hw							&& echo "|*****||EXPERIMENTAL AV1 VA-API codec selected, updating encoder variables||****|"		;;
	(H1)	event_libaom_av1					&& echo "|*****||EXPERIMENTAL AV1 LibAOM codec selected, updating encoder variables||****|"		;;
	(H2)	event_libsvt_av1					&& echo "|*****||EXPERIMENTAL AV1 libSVT codec selected, updating encoder variables||****|"		;;
	(M1)	event_mjpeg_sw						&& echo "MJPEG SW activated - safest but high BW"												;;
	(M2)	event_mjpeg_qsv						&& echo "MJPEG QSV activated - safest but high BW"												;;
	(N1)	event_cineform						&& echo "Cineform SW activated - broken"														;;
	#
	# Multiple input modes go here (I wonder if there's a better, matrix-based approach to this?)
	#
	(W) echo "Four-way panel split activated"						;current_event="event_foursplit";wavelet_foursplit						;;
	(X) echo "Two-way panel split activated"						;current_event="event_twosplit"	;wavelet_twosplit						;;
	(Y) echo "Picture-in-Picture 1 activated"						;current_event="event_pip1"		;wavelet_pip1							;;
	(Z) echo "Picture-in-Picture 2 activated"						;current_event="event_pip2"		;wavelet_pip2							;;
	(*) echo "Unknown predefined input, passing hash to encoders.."	;current_event="dynamic"		;wavelet_dynamic						;;
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
read_etcd_json_revision(){
	# Special case used in controller
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_json_revision" uv_hash_select | jq -r '.header.revision')
}
read_etcd_lastrevision(){
	# Special case used in controller
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_lastrevision")	
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


###
#
# Event codeblocks that describe events which can happen in this script
#
###

wavelet_kill_all() {
# Sets global flags for encoders and reflectors to restart
KEYNAME=reload_reflector; KEYVALUE="1"; write_etcd_global
KEYNAME=encoder_restart; KEYVALUE="1"; write_etcd_global
KEYNAME=uv_islivestreaming; KEYVALUE="0"; write_etcd_global
echo -e "Process kill flags set, services should restart within ~5 seconds \n"
}

wavelet_blank() {
# 1
# Displays a black jpg to blank the screen fully
	current_event="wavelet-blank"
	KEYNAME=uv_input; KEYVALUE="blank"			;	write_etcd_global
	KEYNAME="ENCODER_QUERY"; KEYVALUE="1"		;	write_etcd_global
	# The server should not require any restarts as the UltraGrid.AppImage service should still be running from wavelet_init
	echo 'capture.data 0' | busybox nc -v 127.0.0.1 6160
	echo -e "Blank screen for all hosts activated."
}

wavelet_seal() {
# 2
# Serves a static image in .jpg format in a loop to the encoder.
	cd /home/wavelet/
	current_event="wavelet-seal"
	KEYNAME=uv_input; KEYVALUE="seal"			;	write_etcd_global
	KEYNAME="ENCODER_QUERY"; KEYVALUE="2"		;	write_etcd_global
	# We now use the switcher for simple things
	echo 'capture.data 1' | busybox nc -v 127.0.0.1 6160
	echo -e "Static image activated."
}

wavelet_testcard() {
# T
# Test Card
	current_event="wavelet-testcard"
	KEYNAME="uv_input"; KEYVALUE="smpte_bars"	;	write_etcd_global
	KEYNAME="ENCODER_QUERY"; KEYVALUE="T"		;	write_etcd_global
	echo 'capture.data 2' | busybox nc -v 127.0.0.1 6160
	echo "Testcard image activated."
}

wavelet_refresh() {
	# This is only called by the RD, refresh-devices button, and it finds the previous hash and resets to it.
	revisions=$(read_etcd_json_revision)
	lastrev=$((${revisions} - 1))
	KEYNAME=uv_hash_select; read_etcd_lastrevision; previousHash=${printvalue}
	KEYVALUE=${previousHash}; write_etcd_global
	echo -e "Previous hash value reset, running detectv4l to redetect local sources on all hosts.."
	wavelet_detect_inputs
}

wavelet_dynamic() {
	# Processes device hashes submitted from the WebUI through to the encoder
	# The only thing the controller is doing here ought to be determining the host
	# The encoder performs the necessary tasks from there.
	current_event="wavelet-dynamic"
	KEYNAME=uv_input; read_etcd_global;	controllerInputLabel=${printvalue}
	KEYNAME=uv_hash_select;	read_etcd_global; controllerInputHash=${printvalue}
	KEYNAME="uv_hash_select_old"; read_etcd_global; controllerInputHashPrevious="${printvalue}"
	if [[ ${controllerInputHash} == ${controllerInputHashPrevious} ]]; then
		echo "Hash selection is identical, assuming multiple clicks on UI and doing nothing."
		exit 0
	fi
	echo -e "Controller notified that input hash ${controllerInputHash}\nhas been selected with the input label: ${controllerInputLabel}\n"
	echo "Setting global encoder update bit"
	# The concept here is the query value is "pitched" out to the entire cluster, and the machine which has it "catches" the ball.
	# Do we need ANOTHER watcher service here? Or should the encoders simply watch INPUT_UPDATE and uv_hash_select?
	KEYNAME="ENCODER_QUERY"; KEYVALUE="${controllerInputHash}"; write_etcd_global
	# Write uv_hash_select_old so the system can remember the previous selected hash
	KEYNAME="uv_hash_select_old"; KEYVALUE="${controllerInputHash}"; write_etcd_global
}

wavelet_foursplit() {
	current_event="wavelet_foursplit"
	KEYNAME=uv_input; KEYVALUE="Multi source mix"; write_etcd_global
	#controllerInputLabel=${printvalue}
	KEYNAME=uv_hash_select; read_etcd_global; controllerInputHash=${printvalue}
	echo -e "\n\nController notified that the Four-way split input hash has been selected from the WebUI.\nEncoder will do its best to generate a software mix of up to four available input devices.\n\n "
	# Kill existing streaming on the SERVER
	systemctl --user stop UltraGrid.AppImage.service
	# Set encoder restart flag to 1
	KEYNAME=encoder_restart; KEYVALUE="1"; write_etcd_global
	KEYNAME=input_update; KEYVALUE="0"; echo -e "\n Task completed, resetting input_update key to 0.. \n"; write_etcd_global
}


# These events contain additional codec-specific settings that have been found to work acceptably well on the system.
# Since they are tuned by hand, you probably won't want to modify them unless you know exactly what you're doing.
# Proper operation depends on bandwidth, latency, network quality, encoder speed.  It's highly hardware dependent.
# These operate in conjunction with the standard defined variables set above.  

event_prores() {
	# BROKEN - Clients never receive any frames, they drop everything
	# Which is a shame because this ought to be the 'fastest' codec out there that can scale well to 8K
	KEYNAME=uv_encoder; KEYVALUE="libavcodec:encoder=prores:safe"; write_etcd_global
	echo -e "Cineform Software acceleration activated\n"
	wavelet-decoder-reset
}
event_cineform() {
	# BROKEN - Clients never receive any frames, they drop everything
	KEYNAME=uv_encoder; KEYVALUE="cineform"; write_etcd_global
	echo -e "Cineform Software acceleration activated\n"
	wavelet-decoder-reset
}
event_mjpeg_sw() {
	KEYNAME=uv_encoder; KEYVALUE="libavcodec:encoder=mjpeg:huffman=1:q=10:safe"; write_etcd_global
	echo -e "MJPEG Software acceleration activated, Bitrate will be around 40-70M\n"
	wavelet-decoder-reset
}
event_mjpeg_qsv() {
	KEYNAME=uv_encoder; KEYVALUE="libavcodec:encoder=mjpeg_qsv:safe"; write_etcd_global
	echo -e "MJPEG QSV Acceleration activated, Bitrate 50-70M \n"
	wavelet-decoder-reset
}
event_gpujpeg_() {
	# requires CUDA and therefore an nvidia GPU
	KEYNAME=uv_encoder; KEYVALUE="libavcodec:encoder=mjpeg_qsv:safe"; write_etcd_global
	echo -e "CUDA JPG Activated, Bitrate 50-70M\n"
	wavelet-decoder-reset
}
event_x264hw() {
	KEYNAME=uv_encoder; KEYVALUE="libavcodec:encoder=h264_qsv:gop=6:bitrate=20M"; write_etcd_global
	echo -e "x264 Hardware acceleration activated, Bitrate 20M, decoder task restart bit set. \n"
	wavelet-decoder-reset
}
event_libx265sw() {
	# HIGH bw software HEVC encoding in UI
	KEYNAME=uv_encoder;	KEYVALUE="libavcodec:encoder=libx265:preset=ultrafast:threads=0:safe"; write_etcd_global
	echo -e "libx265 Software mode activated, decoder task restart bit set. \n"
	wavelet-decoder-reset
}
event_libx265sw_low() {
	# LOW bw software HEVC encoding in UI
	KEYNAME=uv_encoder;	KEYVALUE="libavcodec:encoder=libx265:preset=superfast:crf=40:threads=0:safe"; write_etcd_global
	echo -e "libx265 software mode activated, crf 40, decoder task restart bit set. \n"
	wavelet-decoder-reset
}
event_libsvt_hevc_sw() {
	# Feedback from deployment:
	# produces a higher latency stream than libx265, can situationally be more stable.   No longer maintained so mark as obsolete..
	KEYNAME=uv_encoder; KEYVALUE="libavcodec:encoder=libsvt_hevc:preset=7:thread_count=0:safe";	write_etcd_global
}
event_libsvt_hevc_sw_zerolatency() {
	# NB zerolatency disables frame parallelism, can't use multicore!
	KEYNAME=uv_encoder;	KEYVALUE="libavcodec:encoder=libsvt_hevc:preset=6:tune=zerolatency:pred_struct=0:safe";	write_etcd_global
}
event_x265hw_qsv() {
# working on tweaking these values to something as reliable as possible.
	KEYNAME=uv_encoder; KEYVALUE="libavcodec:encoder=hevc_qsv:async_depth=4:safe"; write_etcd_global
	echo -e "x265 QSV Hardware acceleration activated, decoder task restart bit set. \n"
	wavelet-decoder-reset
}
event_x265hw_vaapi() {
	# Intel VA-API hw acceleration, probably depreciated soon in favor of QSV
	KEYNAME=uv_encoder; KEYVALUE="libavcodec:encoder=hevc_vaapi:low_power=1:safe"; write_etcd_global
	echo -e "x265 QSV Hardware acceleration activated, decoder task restart bit set. \n"
	wavelet-decoder-reset
}
event_vp8sw() {
	KEYNAME=uv_encoder;	KEYVALUE="libavcodec:encoder=libvpx:gop=30:bitrate=10M:safe"; write_etcd_global
	echo -e "VP8 Software acceleration activated, Bitrate 10M \n"
	wavelet-decoder-reset
}
event_vp9sw() {
	KEYNAME=uv_encoder; KEYVALUE="libavcodec:encoder=libvpx-vp9:safe"; write_etcd_global
	echo -e "VP9 Software acceleration activated\n"
	wavelet-decoder-reset
}
event_libsvt_vp9() {
	KEYNAME=uv_encoder; KEYVALUE="libavcodec:encoder=libsvt-vp9:safe"; write_etcd_global
	echo -e "VP9 Software acceleration activated\n"
	wavelet-decoder-reset
}
event_vp9hw() {
	KEYNAME=uv_encoder; KEYVALUE="libavcodec:encoder=vp9_qsv:safe"; write_etcd_global
	echo -e "VP9 Hardware acceleration activated\n"
	wavelet-decoder-reset
}
event_rav1esw() {
	KEYNAME=uv_encoder; KEYVALUE="libavcodec:encoder=librav1e:speed=8:safe"; write_etcd_global
	echo -e "AV1 Software acceleration activated \n"
	wavelet-decoder-reset
}
event_av1hw() {
	KEYNAME=uv_encoder;	KEYVALUE="libavcodec:encoder=av1_qsv:safe"; write_etcd_global
	echo -e "AV1 Hardware acceleration activated \n"
	wavelet-decoder-reset
}
event_libaom_av1() {
	KEYNAME=uv_encoder; KEYVALUE="libavcodec:encoder=libaom-av1:usage=realtime:cpu-used=8:safe"; write_etcd_global
	echo -e "LibAOM-AV1 Software compression activated \n"
	wavelet-decoder-reset
}
event_libsvt_av1() {
	KEYNAME=uv_encoder; KEYVALUE="libavcodec:encoder=libsvtav1:preset=12"; write_etcd_global
	echo -e "LibSVT-AV1 Software compression activated! \n"
	wavelet-decoder-reset
}

wavelet_foursplit() {
# W
	current_event="wavelet-foursplit"
	KEYNAME=uv_input; KEYVALUE=FOURSPLIT; write_etcd_global
	# Set encoder restart flag to 1
	KEYNAME=encoder_restart; KEYVALUE="1"; write_etcd_global
}
wavelet_twosplit() {
# W
	current_event="wavelet-twosplit"
	KEYNAME=uv_input; KEYVALUE=TWOSPLIT; write_etcd_global
	# Set encoder restart flag to 1
	KEYNAME=encoder_restart; KEYVALUE="1"; write_etcd_global
}
wavelet_pip1() {
# Doesn't currently work, so disable.
	current_event="wavelet-pip1"
	KEYNAME=uv_input; KEYVALUE=PIP1; write_etcd_global
	# Set encoder restart flag to 1
	KEYNAME=encoder_restart; KEYVALUE="1"; write_etcd_global
}
wavelet_pip2() {
# Doesn't currently work, so disable.
	current_event="wavelet-pip2"
	KEYNAME=uv_input; KEYVALUE=PIP2; write_etcd_global
	# Set encoder restart flag to 1
	KEYNAME=encoder_restart; KEYVALUE="1"; write_etcd_global
}

wavelet_decoder_reset() {
	# Finds all decoders and sets client reSET flag.  This restarts UltraGrid without a full system reboot.
	# Have to clean /DECODER_RESET from result or we get recursion, remember etcd isn't hierarchical!
	return_etcd_clients_ip=$(read_etcd_clients_ip)
	RESULT="${return_etcd_clients_ip///DECODER_RESET/}"
	for host in ${RESULT}; do
		trimmed_host=$(echo ${host} | sed 's|decoderip/||g')
		echo -e "working on : ${trimmed_host}"
		KEYNAME="/${trimmed_host}/DECODER_RESET"; KEYVALUE="1"; write_etcd_global
		echo -e "DECODER_RESET flag enabled for ${trimmed_host}..\n"
	done
	echo -e "Decoder tasks instructed to reset on all attached decoders.\n"
}

wavelet_encoder_reboot() {
# Finds all encoders and sets client reboot flag (need to implement reboot watcher service)
# re-use the reflector code and then foreach hostname set it to reboot encoders
# UltraGrid encoder task will SIGTERM every time a source is changed, this on the other hand reboots the WHOLE encoder.
	KEYNAME="ENCODER_REBOOT"; KEYVALUE="1"; write_etcd_global
	echo -e "Encoder reboot flag enabled, encoders will hard reset momentarily.."
}

wavelet_system_reboot() {
# This hard reboots everything, including the server.
# set reboot flag on every host in etcd
	KEYNAME="SYSTREM_REBOOT"; KEYVALUE="1"; write_etcd_global
	echo -e "All hosts instructed to hard reset.  Server and all reachable devices will restart immediately..\n"
}

wavelet_clear_inputs() {
# Removes all input devices from their appropriate prefixes.
# Until I fix the detection/removal stuff so that it works perfectly, this will effectively clean out any cruft from 'stuck'
# source devices which no longer exist, but still populate on the UI.
# bad solution
	hostname="$(hostname)"
	keysArray=("/interface/" "/hash/" "/short_hash/" "/long_interface/" "/${hostname}/inputs/" "/network_long/" "/network_short/" "/network_interface/" "/network_ip/" "/network_uv_stream_command/")
	for key in ${keysArray[@]}; do
		KEYNAME="${key}"
		echo "Deleting: ${key}"
		delete_etcd_key_prefix
	done
	echo -e "All interface devices and their configuration data, as well as labels have been deleted\nPlugging in a new device will cause the detection module to run again.\n"
}

wavelet_detect_inputs() {
	# Tells detectv4l to run on everything, all encoders watch this flag when they are provisioned as such.
	KEYNAME="DEVICE_REDETECT"; KEYVALUE=1; write_etcd_global
	echo -e "\nAll devices now redetecting available input video sources..\n"
}


###
#
# Main
#
###

logName="controller.log"
if [[ -e $logName || -L $logName ]] ; then
	i=0
	while [[ -e $logName-$i || -L $logName-$i ]] ; do
		let i++
	done
	logName=$logName-$i
fi
#set -x
exec >${logName} 2>&1


detect_self