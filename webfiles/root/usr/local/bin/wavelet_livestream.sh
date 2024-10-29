#!/bin/bash
# Livestream script
# Launched from a systemd watcher service configured from run_ug.sh
# This module corresponds to the livestream option under advanced settings on the webui


#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
ETCDCTL_API=3
read_etcd(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get /$(hostname)/${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}
read_etcd_prefix(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix /$(hostname)/${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}
read_etcd_global(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for Global value"
}
write_etcd(){
        etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}
write_etcd_global(){
        etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
}

event_livestream(){
	KEYNAME=uv_islivestreaming
	read_etcd
	if [[ uv_islivestreaming -eq 0 ]]; then
		echo -e "uv_islivestreaming is NOT enabled. Something is misbehaving!\n"
		exit 1
	fi

	KEYNAME=/livestream/url
	read_etcd_global
	liveStreamURL=${result}

	KEYNAME=/livestream/apikey
	read_etcd_global
	liveStreamAPIKey=${result}

	KEYNAME=/hostHash/svr.wavelet.local/Hash
	# UltraGrid now comes build in with live555 RTP server, so we can take a generated output from there with FFMPEG, and stream to our target URL.
	# This could be expanded in future to stream to a proper forwarding cluster which would generate appropriate stream qualities as necessary.
	# Run FFMPEG direct from server with appropriate settings;
	ffmpeg -protocol_whitelist tcp,udp,http,rtp,file -i http://${serverIP}:8554/ug.sdp -c:v libx264 -g 25 -preset fast -b:v 4096k -c:a aac -ar 44100 -f flv rtmp://${liveStreamURL}/${liveStreamAPIKey}
}

# Main
#set -x
exec >/home/wavelet/livestreaming.log 2>&1
event_livestream
