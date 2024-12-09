

#!/bin/bash

# This forms the basis of an init script when the server starts and run_ug.sh is called to determine the system type
# It runs once, sets initial values in etcd which the controller then handles appropriately.  
# This effectively starts the controller in a default state, on "best" settings

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
	echo -e "Key Name ${KEYNAME} set to ${KEYVALUE} under: /$(hostname)/\n"
}
write_etcd_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name ${KEYNAME} set to: ${KEYVALUE} for Global value\n"
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
generate_service(){
	# Can be called with more args with "generate_servier" ${keyToWatch} 0 0 "${serviceName}"
	/usr/local/bin/wavelet_etcd_interaction.sh "generate_service" "${serviceName}"
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
	rm -rf seal.mkv
	# Generate an image
	ffmpeg -fflags +genpts -loop 1 -i ny-stateseal.jpg -t 10 -c:v mjpeg -vf scale=1080x1080 -t 10 seal.mkv
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
	# We can use the default UG audio port which binds to 5006, we only need to mess with that if we are sending and receiving.
	# We use a sparse array so the decans can be utilized for additional arguments if needed.  Note this isn't associative, we need ordering here.
	commandLine=(\
		[1]="--tool uv" \
		[21]="${filtervar}" \
		[31]="--control-port 6160" \
		[41]="-f V:rs:200:250" \
		[51]="-t switcher:select=1:fallback" [52]="-t testcard:pattern=blank" [53]="-t file:/var/home/wavelet/seal.mkv:loop" [54]="-t testcard:pattern=smpte_bars" \
		[61]="-c ${encodervar}" \
		[71]="-P ${video_port}" [72]="-m ${UGMTU}" [73]="${destinationipv4}" [74]="param control-accept-global");
	ugargs="${commandLine[@]}"
	# Note that UG_ARGS is NOT a global key, and is therefore base64 encoded.
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
WantedBy=default.target" > /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
	systemctl --user daemon-reload
	echo -e "Starting UG executable and then restarting UltraGrid.AppImage.service..\n"
	systemctl --user enable UltraGrid.AppImage.service --now
	# Sleep for a couple of seconds to allow the encoder to come up, then Select switcher input #1 which should always be the Seal image.
	sleep 1
	echo 'capture.data 1' | busybox nc -v 127.0.0.1 6160
}


#####
#
# Main
#
#####


# Populate standard values into etcd
#set -x
# Wait until etcd cluster is up ( we are checking for "IS LEADER" = true here )
until [[ $(/usr/local/bin/wavelet_etcd_interaction.sh "check_status" | awk '{print $6}') = "true," ]]; do
	echo -e "Etcd still down.. waiting one second.."
	sleep 1
done
sleep 2
echo -e "Etcd cluster is up and responding, continuing.."
exec >/home/wavelet/initialize.log 2>&1
echo -e "Populating standard values into etcd, the last step will trigger the Controller and Reflector functions, bringing the system up.\n"
KEYNAME="uv_videoport"; KEYVALUE="5004"; write_etcd_global
KEYNAME="uv_audioport"; KEYVALUE="5006"; write_etcd_global
KEYNAME="/livestream/enabled"; KEYVALUE="0"; write_etcd_global
KEYNAME="uv_hash_select"; KEYVALUE="2"; write_etcd_global
KEYNAME="/banner/enabled"; KEYVALUE="0"; write_etcd_global
KEYNAME="uv_filter_cmd"; delete_etcd_key_global

event_init_av1

echo -e "Enabling monitor services..\n"
systemctl --user enable watch_reflectorreload.service --now
systemctl --user enable watch_encoderflag.service --now
echo -e "Values populated, monitor services launched.  Starting Reflector and Controller\n"
systemctl --user enable wavelet_reflector.service --now
systemctl --user enable wavelet_controller.service --now

# Attempt to connect to a cached bluetooth audio output device
/usr/local/bin/wavelet_set_bluetooth_connect.sh
# Ping detectv4l so that we populate devices
/usr/local/bin/wavelet_detectv4l.sh

event_init_seal