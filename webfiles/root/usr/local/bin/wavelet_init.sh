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
        # Further testing shows that simply setting everything to the fastest, laziest preset generates a bad stream. 
        # We choose preset 6 so we get some work happening, SVT then behaves itself again.
        KEYNAME=uv_encoder
        KEYVALUE="ibavcodec:encoder=libsvt_hevc:preset=6:gop=60:thread_count=0:safe:qp=38"
        write_etcd_global
        KEYNAME=uv_gop
        KEYVALUE=6
        write_etcd_global
        KEYNAME=uv_bitrate
        KEYVALUE="25M"
        write_etcd_global
        echo -e "LibSVT_HEVC activated with 60 GOP, preset 6 and qp=38 \n"
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
event_x265sw
systemctl --user enable wavelet_controller.service --now
wait 2
KEYNAME=input_update
KEYVALUE=1
write_etcd_global
systemctl --user restart wavelet_reflector.service --now
