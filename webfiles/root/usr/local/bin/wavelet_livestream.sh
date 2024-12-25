#!/bin/bash
# Livestream script
# Launched from a systemd watcher service configured from run_ug.sh
# This module corresponds to the livestream option under advanced settings on the webui

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

event_livestream(){
	KEYNAME=uv_islivestreaming; read_etcd
	if [[ ${printvalue} -eq 0 ]]; then
		echo -e "uv_islivestreaming is NOT enabled, and yet the service was called. Exiting silently.\n"
		exit 0
	fi
	KEYNAME=/livestream/url; read_etcd_global
	liveStreamURL=${printvalue}
	if [[ ${printvalue} = "" ]]; then
		echo -e "There is no livestream URL populated.  Exiting.\n"
		exit 0
	fi
	KEYNAME=/livestream/apikey
	read_etcd_global; if [[ ${printvalue} = "" ]]; then
		echo -e "There is no livestream API key populated.  We can continue here if we know the service doesn't require an API key.\n"
		# Something to determine if server needs apikey?  curl command?
		# if [[ result = OK ]]; then
		#	echo -e "Continuing to livestream without API key..\n"
		#	call_ffmpeg
		# fi
		# echo -e "Server requires API key!\n"
	fi	
	liveStreamAPIKey=${printvalue}

	#KEYNAME=/hostHash/svr.wavelet.local/Hash
	# UltraGrid now comes build in with live555 RTP server, so we can take a generated output from there with FFMPEG, and stream to our target URL.
	# This could be expanded in future to stream to a proper forwarding cluster which would generate appropriate stream qualities as necessary.
	# Run FFMPEG direct from server with appropriate settings;
	call_ffmpeg
}

call_ffmpeg(){
	ffmpeg -protocol_whitelist tcp,udp,http,rtp,file -i http://${serverIP}:8554/ug.sdp -c:v libx264 -g 25 -preset fast -b:v 4096k -c:a aac -ar 44100 -f flv rtmp://${liveStreamURL}/${liveStreamAPIKey}
}

# Main
#set -x
exec >/home/wavelet/livestreaming.log 2>&1
event_livestream
