#!/bin/bash

# This forms the basis of an init script when the server starts and run_ug.sh is called to determine the system type
# It runs once, sets initial values in etcd which the controller then handles appropriately.  
# This effectively starts the controller in a default state, on "best" settings

ETCDENDPOINT=192.168.1.32:2379
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


event_init_codec() {
	KEYNAME=uv_encoder
	KEYVALUE="libavcodec:encoder=libx265:preset=ultrafast:threads=0:bitrate=8M"
	write_etcd_global
	echo -e "Default LibX265 activated, bitrate 8M\n"
}

event_init_av1() {
	KEYNAME=uv_encoder
	KEYVALUE="libavcodec:encoder=libaom-av1:usage=realtime:cpu-used=8:safe"
	write_etcd_global
	echo -e "Default LibX265 activated, bitrate 8M\n"     
}

event_init_seal(){
	# Because of the way the controller operates with video switchers, we initially actually need to start Wavelet with a single input option
	# 2
	# Serves a static image in .jpg format in a loop to the encoder.
	current_event="wavelet-seal"
	rm -rf seal.mp4
	ffmpeg -r 1 -i ny-stateseal.jpg -c:v mjpeg -vf fps=30 -color_range 2 -pix_fmt yuv440p seal.mp4
	KEYNAME=uv_input
	KEYVALUE="SEAL"
	write_etcd_global
	cd /home/wavelet/
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
	UGMTU="9000"
    ugargs="--tool uv $filtervar --control-port 6160 -f V:rs:200:250 -t switcher -t testcard:pattern=blank -t file:/home/wavelet/seal.mp4:loop -t testcard:pattern=smpte_bars -c ${encodervar} -P ${video_port} -m ${UGMTU} ${destinationipv4}"
	KEYNAME=UG_ARGS
	KEYVALUE=${ugargs}
	write_etcd
	echo -e "Verifying stored command line:\n"
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
	# Sleep for a couple of seconds to allow the encoder to come up, then Select switcher input #1 which should always be the Seal image.
	sleep 2
	echo 'capture.data 1' | busybox nc -v 127.0.0.1 6160
}

# Populate standard values into etcd
set -x
exec >/home/wavelet/initialize.log 2>&1
echo -e "Populating standard values into etcd, the last step will trigger the Controller and Reflector functions, bringing the system up.\n"
KEYNAME="uv_videoport"
KEYVALUE="5004"
write_etcd_global
KEYNAME="uv_audioport"
KEYVALUE="5006"
write_etcd_global
KEYNAME="/livestream/enabled"
KEYVALUE="0"
write_etcd_global
recording="0"
KEYNAME=uv_input
KEYVALUE="SEAL"
write_etcd_global
KEYNAME="uv_hash_select"
KEYVALUE="2"
write_etcd_global
KEYNAME="/banner/enabled"
KEYVALUE="0"
write_etcd_global
echo -e "Enabling monitor services..\n"
systemctl --user enable watch_reflectorreload.service --now
systemctl --user enable wavelet_reflector.service --now
systemctl --user enable watch_encoderflag.service --now
echo -e "Values populated, monitor services launched.  Starting reflector\n\n"
systemctl --user enable UltraGrid.Reflector.service --now
event_init_av1
systemctl --user restart wavelet_reflector.service --now
systemctl --user enable wavelet_controller.service --now