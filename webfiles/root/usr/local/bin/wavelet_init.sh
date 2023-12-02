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


event_x265sw() {
	KEYNAME=uv_encoder
	KEYVALUE="libavcodec:encoder=libx265:gop=6:bitrate=15M:subsampling=444"
	write_etcd_global
	KEYNAME=uv_gop
	KEYVALUE=6
	write_etcd_global
	KEYNAME=uv_bitrate
	KEYVALUE="15M"
	write_etcd_global
	echo -e "x265 Software acceleration activated, GOP 6 frames,  Bitrate 15M \n"
}

# Populate standard values into etcd
set -x
echo -e "Populating standard values into etcd, the last step will trigger the Controller and Reflector functions, bringing the system up.\n"
KEYNAME=uv_videoport
KEYVALUE=5004
write_etcd_global
KEYNAME=uv_audioport
KEYVALUE=5006
write_etcd_global
KEYNAME=uv_islivestreaming
KEYVALUE=0
write_etcd_global
recording="0"
KEYNAME=uv_input
KEYVALUE="SEAL"
write_etcd_global
echo -e "Enabling monitor services.."
systemctl --user enable wavelet_controller.service --now
systemctl --user enable watch_reflectorreload.service --now
systemctl --user enable watch_encoderflag.service --now
echo -e "Values populated, starting reflector"
systemctl --user enable UltraGrid.Reflector.service --now
event_x265sw
# Runs wavelet_controller.sh directly because otherwise, it will wait for values to be populated.  
# During Init, we want to run it on its own.
/usr/local/bin/wavelet_controller.sh
