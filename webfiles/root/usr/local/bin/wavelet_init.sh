#!/bin/bash

# This forms the basis of an init script when the server starts and run_ug.sh is called to determine the system type
# It runs once, sets initial values in etcd which the controller then handles appropriately.  
# This effectively starts the controller in a default state, on "best" settings

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


event_init_codec() {
	KEYNAME=uv_encoder;	KEYVALUE="libavcodec:encoder=libx265:preset=ultrafast:threads=0:bitrate=8M"; write_etcd_global
	echo -e "Default LibX265 activated, bitrate 8M\n"
}

event_init_av1() {
	KEYNAME=uv_encoder;	KEYVALUE="libavcodec:encoder=libaom-av1:usage=realtime:cpu-used=8:safe"; write_etcd_global
	echo -e "Default libaom_av1 activated, bitrate controlled by codec\n"     
}

event_init_seal(){
	# Because of the way the controller operates with video switchers, we initially need to start Wavelet with a single input option
	# 2
	# Serves a static image in .jpg format in a loop to the encoder.
	# Note that it starts the UG AppImage service directly and doesn't rely on run_ug, like an encoder will.
	current_event="wavelet-seal"
	rm -rf seal.mp4
	ffmpeg -fflags +genpts -i ny-stateseal.jpg -c:v mjpeg -vf fps=30 -color_range 2 -t 240 -pix_fmt yuvj444p seal.mp4
	KEYNAME=uv_input; KEYVALUE="SEAL"; write_etcd_global
	cd /home/wavelet/
	# call uv_hash_select to process the provided device hash and select the input from these data
	KEYNAME=uv_hash_select; read_etcd_global; 
	# Reads Filter settings, should be banner.pam most of the time
	KEYNAME=uv_filter_cmd; read_etcd_global; filtervar=${printvalue}
	# Reads Encoder codec settings, should be populated from the Controller
	KEYNAME=uv_encoder;	read_etcd_global; encodervar=${printvalue}
	# Videoport is always 5004 unless we are doing some strange future project requiring bidirectionality or conference modes
	KEYNAME=uv_videoport; read_etcd_global; video_port=${printvalue}
	# Audio Port is always 5006, unless UltraGrid has gotten far better at handling audio we likely won't use this.
	KEYNAME=uv_audioport; read_etcd_global;	audio_port=${printvalue}
	# Destination IP is the IP address of the UG Reflector
	destinationipv4="192.168.1.32"
	UGMTU="9000"
	# There may be a bug in UG continuous regarding streaming the static image
	# avformat_seek_file(s->fmt_ctx, -1, INT64_MIN, s->fmt_ctx->start_time, INT64_MAX, 0): Operation not permitted
	# test against 1.9.8
	ugargs="--tool uv ${filtervar} --control-port 6160 -f V:rs:200:250 -t switcher -t testcard:pattern=blank -t file:/var/home/wavelet/seal.mp4:loop -t testcard:pattern=smpte_bars -c ${encodervar} -P ${video_port} -m ${UGMTU} ${destinationipv4}"
	KEYNAME=UG_ARGS; KEYVALUE=${ugargs}; write_etcd
	echo -e "Verifying stored command line:\n"
	echo -e "${ugargs}"
	echo -e "[Unit]
Description=UltraGrid AppImage executable
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/UltraGrid.AppImage ${ugargs}
KillMode=mixed
TimeoutStopSec=0.5
RestartSec=5
Restart=always
RemainAfterExit=no

[Install]
WantedBy=graphical-session.target" > /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
	systemctl --user daemon-reload
	echo -e "Starting UG executable and then restarting UltraGrid.AppImage.service..\n"
	systemctl --user enable UltraGrid.AppImage.service --now
	# Sleep for a couple of seconds to allow the encoder to come up, then Select switcher input #1 which should always be the Seal image.
	sleep 2
	echo 'capture.data 1' | busybox nc -v 127.0.0.1 6160
}

# Populate standard values into etcd
#set -x
# Sleep for five seconds to allow etcd cluster to start
echo -e "Sleep for five seconds to allow etcd cluster to stabilize..\n"
sleep 5

exec >/home/wavelet/initialize.log 2>&1
echo -e "Populating standard values into etcd, the last step will trigger the Controller and Reflector functions, bringing the system up.\n"
KEYNAME="uv_videoport"; KEYVALUE="5004"; write_etcd_global
KEYNAME="uv_audioport"; KEYVALUE="5006"; write_etcd_global
KEYNAME="/livestream/enabled"; KEYVALUE="0"; write_etcd_global
KEYNAME="uv_hash_select"; KEYVALUE="2"; write_etcd_global
KEYNAME="/banner/enabled"; KEYVALUE="0"; write_etcd_global
KEYNAME="uv_filter_cmd"; KEYVALUE=""; write_etcd_global
event_init_av1

echo -e "Enabling monitor services..\n"
systemctl --user enable watch_reflectorreload.service --now
systemctl --user enable wavelet_reflector.service --now
systemctl --user enable watch_encoderflag.service --now
echo -e "Values populated, monitor services launched.  Starting reflector\n\n"
systemctl --user enable ultragrid.reflector.service --now
systemctl --user restart wavelet_reflector.service --now
systemctl --user enable wavelet_controller.service --now

# Attempt to connect to a cached bluetooth audio output device
/usr/local/bin/wavelet_set_bluetooth_connect.sh
# Ping detectv4l so that we populate devices
/usr/local/bin/wavelet_detectv4l.sh

event_init_seal