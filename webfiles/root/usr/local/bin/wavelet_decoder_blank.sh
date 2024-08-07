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

read_etcd_oldkeyname(){
		ETCDCTL_API=3 oldprintvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get ${OLDKEYNAME} --print-value-only)
		echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for Global value"
}

write_etcd_oldkeyname(){
		ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put ${OLDKEYNAME} -- ${VALUE}
		echo -e "Key Name {$OLDKEYNAME} set to value ${VALUE} for state tracking.."
}



event_decoder_blank(){
# Kill the systemd monitor task for a few moments
systemctl --user stop wavelet_decoder_blank.service
echo -e "\nDecoder Blank flag change detected, switching to blank input...\n\n\n"
systemctl --user stop UltraGrid.AppImage.service
mv /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service.old.blank
# set ug_args to generate and display smpte testcard
ug_args="--tool uv -t testcard:pattern=blank -d vulkan_sdl2:fs:keep-aspect:nocursor:nodecorate"
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
echo -e "\nTask Complete.\n"
exit 0
}

event_decoder_unblank(){
# Kill the systemd monitor task for a few moments
systemctl --user stop wavelet-decoder-blank.service
echo -e "\nDecoder Blank flag change detected, restoring previous input...\n\n\n"
systemctl --user stop UltraGrid.AppImage.service
mv /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service.old.blank /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
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
exec >/home/wavelet/wavelet_blank_decoder.log 2>&1

KEYNAME=/$(hostname)/DECODER_BLANK
read_etcd_global
OLDKEYNAME=/$(hostname)/DECODER_BLANK_PREV
read_etcd_oldkeyname
	if [[ ${printvalue} == ${oldprintvalue} ]]; then
		echo -e "\n Blank setting and previous blank setting match, the webpage has been refreshed, doing nothing..\n"
		:
	else
		if [[ "${printvalue}" == 1 ]]; then
				echo -e "\ninput_update key is set to 1, setting blank display for this host.. \n"
				VALUE="1"
				write_etcd_oldkeyname
				event_decoder_blank
				# add ifexists to do nothing if service.old.blank exists, because we don't want the decoders blanking on EVERY web refresh!
				# orr.. just work out something better here because this won't work well.
				# use a switcher, have the decoders all running a blank in the background?
		else
				echo -e "\ninput_update key is set to 0, reverting to previous display.. \n"
				VALUE="0"
				write_etcd_oldkeyname
				event_decoder_unblank
		fi
	fi