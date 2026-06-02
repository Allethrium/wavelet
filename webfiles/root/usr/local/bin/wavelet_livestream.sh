#!/bin/bash
# Livestream script
# This module corresponds to the livestream option under advanced settings on the webui, or will once the feature is complete.


# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
ETCDINTERACTIONHOOKS=""
if [[ -f "/var/wavelet_ramfs/etcd_interaction_hooks.sh" ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source "/usr/local/bin/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/usr/local/bin/etcd_interaction_hooks.sh"
fi


event_livestream(){
	# Livestreaming is now set per group, so we first need this hosts group hash
	KEYNAME="/UI/HOSTS/$hostHash/control/GROUP"; read_etcd_global; groupHash="$printvalue"
	KEYNAME="/UI/GROUPS/$groupHash/control/LIVESTREAM"; read_etcd_global
	if [[ ${printvalue} -eq 0 ]]; then
		exit 0
	fi
	KEYNAME="/UI/GROUPS/$groupHash/control/LiveStreamData"; read_etcd_global
	liveStreamURL="${printvalue#*;}"
	liveStreamKey="${printvalue%;*}"
	if [[ -z "$liveStreamURL" ]]; then
		echo "There is no livestream URL populated.  Exiting."
		exit 0
	fi
	if [[ -z $liveStreamKey ]]; then
		echo "There is no livestream API key populated.  We can continue here if we know the service doesn't require an API key."
		# Something to determine if server needs apikey?  curl command?
		# if [[ result = OK ]]; then
		#	echo -e "Continuing to livestream without API key..\n"
		#	call_ffmpeg
		# fi
		# echo -e "Server requires API key!\n"
	fi	
	# Run FFMPEG direct from server with appropriate settings;
	call_ffmpeg
}

call_ffmpeg(){
	# Extract SDP stream from UltraGrid and transcode to Livestream target with standard settings.
	ffmpeg -protocol_whitelist tcp,udp,http,rtp,file -i http://"${serverIP}":8554/ug.sdp -c:v libx264 -g 25 -preset fast -b:v 4096k -c:a aac -ar 44100 -f flv rtmp://"${liveStreamURL}"/"${liveStreamAPIKey}"
}

hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)

exec >/home/wavelet/livestreaming.log 2>&1
event_livestream
