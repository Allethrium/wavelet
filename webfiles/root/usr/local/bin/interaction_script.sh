#!/bin/bash
# Simple user interaction file for the system

#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
read_etcd(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get /$(hostname)/${KEYNAME})
        echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for host $(hostname)"
}

read_etcd_global(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get "${KEYNAME}")
        echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for Global value"
}

write_etcd(){
        etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}

write_etcd_global(){
        etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
}

write_etcd_clientip(){
        etcdctl --endpoints=${ETCDENDPOINT} put /decoderip/$(hostname) "${KEYVALUE}"
        echo -e "$(hostname) set to ${KEYVALUE} for Global value"
}
read_etcd_clients_ip() {
        return_etcd_clients_ip=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix /decoderip/ --print-value-only)
}


SELECT=""
while [[ "$SELECT" != $'\x0a' && "$SELECT" != $'\x20' ]]; do
  echo "Select session type:"
  echo "valid options: \n 
  1     -       blank screen\n 
  2        -       NY state Seal\n 
  3       -       Document Camera\n 
  4     -       HDMI Input 1\n 
  5        -       HDMI Input 2\n 
  6        -       Hybrid Teams\n 
  7        -       witness cam\n 
  8 -       courtroom cam\n
  9     -       recording function\n
  10    -       livestreaming toggle\n"
  read -s -N 1 SELECT
  echo "Debug/$SELECT/${#SELECT}"
  case $SELECT in
        # 1
        (1) echo -e "Option One, Blank activated\n";       etcdctl --endpoints=${ETCDENDPOINT} put input "1";;
        # Display a black screen on all devices
        # 2
        (2) echo -e "Option Two, Seal activated\n";       etcdctl --endpoints=${ETCDENDPOINT} put input "2";;
        # Display a static image of a court seal (find a better image!)
        # 3
        (3) echo -e "Option Three, Document Camera activated\n"; etcdctl --endpoints=${ETCDENDPOINT} put input "3"      ;;
        # Feed from USB Document Camera attached to encoder
        # 4
        (4) echo -e "Option Four, Document Camera activated\n"; etcdctl --endpoints=${ETCDENDPOINT} put input "4"      ;;                 
        # Feed from HDMI Input, generally anticipated to be an HDMI switcher from the Defendent/Plaintiff tables and display from Counsel's laptop
        # 5
        (5) echo -e "Option Five, HDMI Capture Input activated\n"; etcdctl --endpoints=${ETCDENDPOINT} put input "5"      ;;              
        # An additional HDMI feed from another device.  Can be installed or not, anticipate some kind of permanently present Media Player or similar
        # Probably too interchangable with counsel's HDMI input but strikes me as useful enough to maintain here.
        # 6
        (6) echo -e "Option Six, Hybrid Mode activated\n"; etcdctl --endpoints=${ETCDENDPOINT} put input "6"      ;;                    
        # Switch to a screen capture pulling a Teams meeting window via HDMI input.  
        # Target machine should be dual-homed to an internet capable connection, running Teams
        # The teams feed is ingested into UltraGrid for local display
        # 7
        (7) echo -e "Option Seven, Witness cam activated\n"; etcdctl --endpoints=${ETCDENDPOINT} put input "7"      ;;                    
        # feed from Webcam or any kind of RTP/RTSP stream, generally anticipated to capture the Witness Box and Well for detail view
        # 8
        (8) echo -e "Option Eight, Courtroom Wide-angle activated\n"; etcdctl --endpoints=${ETCDENDPOINT} put input "8"      ;;          
        # feed from wide-angle Courtroom camera generally anticipated to capture the Well + Jury zone, perhaps front row of gallery
        # 9
        (9) echo "Not implemented"                                              ;;
        (A)                                                                                                                             event_livestream;;
        (B)             event_x264sw            && echo "x264 Software video codec selected, updating encoder variables";;
        (C)             event_x264hw            && echo "x264 VA-API video codec selected, updating encoder variables";;
        (D)             event_x265sw            && echo "HEVC Software video codec selected, updating encoder variables";;
        (E)             event_x265hw            && echo "HEVC VA-API video codec selected, updating encoder variables";;
        (F)             event_vp9sw             && echo "VP-9 Software video codec selected, updating encoder variables";;
        (G)             event_vp9hw             && echo "VP-9 Hardware video codec selected, updating encoder variables";;
        (H)             event_rav1esw           && echo "|*****||EXPERIMENTAL AV1 RAV1E codec selected, updating encoder vaiables||****|";;
        (I)             event_av1hw             && echo "|*****||EXPERIMENTAL AV1 VA-API codec selected, updating encoder vaiables||****|";;
esac
done