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


# Populate standard values into etcd
set -x
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
systemctl --user enable wavelet_controller.service --now
sleep 2
KEYNAME=input_update
KEYVALUE=1
write_etcd_global
systemctl --user restart wavelet_reflector.service --now
