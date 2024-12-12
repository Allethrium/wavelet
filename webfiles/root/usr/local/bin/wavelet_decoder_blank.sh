#!/bin/bash
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

event_decoder_blank(){
	echo -e "\nDecoder Blank flag change detected, switching host to blank input...\n\n\n"
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
	systemctl --user restart wavelet_decoder_blank.service
	echo -e "\nTask Complete.\n"
	exit 0
}

event_decoder_unblank(){
	echo -e "\nDecoder Blank flag change detected, restoring host to previous input...\n\n\n"
	systemctl --user stop UltraGrid.AppImage.service
	mv /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service.old.blank /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
	systemctl --user daemon-reload
	systemctl --user start UltraGrid.AppImage.service
	systemctl --user restart wavelet_decoder_blank.service
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

KEYNAME="/$(hostname)/DECODER_BLANK_PREV"; read_etcd_global; oldKeyValue=${printvalue}
KEYNAME="/$(hostname)/DECODER_BLANK"; read_etcd_global; newKeyValue=${printvalue}
	if [[ ${newKeyValue} == ${oldKeyValue} ]]; then
		echo -e "\n Blank setting and previous blank setting match, the webpage has been refreshed, doing nothing..\n"
		:
	else
		if [[ "${newKeyValue}" == 1 ]]; then
				echo -e "\ninput_update key is set to 1, setting blank display for this host, and writing prevKey \n"
				KEYNAME="/($hostname)DECODER_BLANK_PREV"; KEYVALUE="1";	write_etcd_global
				event_decoder_blank
				# use a switcher, have the decoders all running a blank in the background?
		else
				echo -e "\ninput_update key is set to 0, reverting to previous display, and writing prevKey.. \n"
				KEYNAME="/$(hostname)/DECODER_BLANK_PREV"; KEYVALUE="0"; write_etcd_global
				event_decoder_unblank
		fi
	fi