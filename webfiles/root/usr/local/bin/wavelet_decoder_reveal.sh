#!/bin/bash
#
# This script resets the appropriate flag back to 0 and then resets the AppImage service.
# Should fix some errors and cheaper than a reboot.
detect_self(){
systemctl --user daemon-reload
UG_HOSTNAME=$(hostname)
				echo -e "Hostname is $UG_HOSTNAME \n"
				case $UG_HOSTNAME in
				enc*)                                   echo -e "I am an Encoder \n"            ;       exit 0
				;;
				dec*)                                   echo -e "I am a Decoder \n"             ;       event_decoder
				;;
				svr*)                                   echo -e "I am a Server \n"              ;       exit 0
				;;
				*)                                      echo -e "This device is other \n"       ;       event_decoder
				;;
				esac
}



#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
ETCDCTL_API=3

read_etcd_global(){
		ETCDCTL_API=3 printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
		echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for Global value"
}


event_decoder(){
# Kill the systemd monitor task for a few moments
systemctl --user stop wavelet-decoder-reveal.service
echo -e "\nDecoder Reveal flag change detected, resetting flag and displaying reveal card for 15 seconds..\n\n\n"
etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/DECODER_REVEAL" -- "0"
systemctl --user stop UltraGrid.AppImage.service
mv /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service.old.reveal
# set ug_args to generate and display smpte testcard
ug_args="--tool uv -t testcard:pattern=smpte_bars -d vulkan_sdl2:fs --param use-hw-accel"
echo -e "
[Unit]
Description=UltraGrid AppImage executable
After=network-online.target
Wants=network-online.target
[Service]
ExecStartPre=-swaymsg workspace 2
ExecStart=/usr/local/bin/UltraGrid.AppImage ${ug_args}
Restart=always
[Install]
WantedBy=default.target" > /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
systemctl --user daemon-reload
systemctl --user start UltraGrid.AppImage.service
sleep 10
systemctl --user stop UltraGrid.AppImage.service
mv /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service.old.reveal /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
systemctl --user daemon-reload
systemctl --user start UltraGrid.AppImage.service
echo -e "\nTask Complete.\n"
exit 0
}

###
#
# Main 
#
###

set -x
exec >/home/wavelet/wavelet_reveal_decoder.log 2>&1

KEYNAME=/$(hostname)/DECODER_REVEAL
		read_etcd_global
		if [[ "${printvalue}" == 1 ]]; then
				echo -e "\ninput_update key is set to 1, continuing with task.. \n"
				detect_self
		else
				echo -e "\ninput_update key is set to 0, doing nothing.. \n"
				exit 0
		fi
