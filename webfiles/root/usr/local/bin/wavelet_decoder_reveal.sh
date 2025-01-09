#!/bin/bash
#
# This script resets the appropriate flag back to 0 and then resets the AppImage service.
# Should fix some errors and cheaper than a reboot.


detect_self(){
	systemctl --user daemon-reload
	echo -e "Hostname is ${hostNameSys} \n"
	case ${hostNameSys} in
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
	echo -e "Key Name: {$KEYNAME} read from etcd for value: $printvalue for host: ${hostNameSys}\n"
}
read_etcd_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}") 
	echo -e "Key Name: {$KEYNAME} read from etcd for Global Value: $printvalue\n"
}
read_etcd_prefix(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_prefix" "${KEYNAME}")
	echo -e "Key Name: {$KEYNAME} read from etcd for value $printvalue for host: ${hostNameSys}\n"
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
	echo -e "Key Name: ${KEYNAME} set to ${KEYVALUE} under /${hostNameSys}/\n"
}
write_etcd_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name: ${KEYNAME} set to: ${KEYVALUE} for Global value\n"
}
write_etcd_client_ip(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_client_ip" "${KEYNAME}" "${KEYVALUE}"
}
delete_etcd_key(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key" "${KEYNAME}"
}
delete_etcd_key_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key_global" "${KEYNAME}"
}
delete_etcd_key_prefix(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key_prefix" "${KEYNAME}"
}
generate_service(){
	# Can be called with more args with "generate_servier" ${keyToWatch} 0 0 "${serviceName}"
	/usr/local/bin/wavelet_etcd_interaction.sh "generate_service" "${serviceName}"
}

event_decoder(){
	# Kill the systemd monitor task for a few moments
	systemctl --user stop wavelet-decoder-reveal.service
	echo -e "\nDecoder Reveal flag change detected, resetting flag and displaying reveal card for 10 seconds..\n"
	KEYNAME="/${hostNameSys}/DECODER_REVEAL"; KEYVALUE="0"; write_etcd_global
	systemctl --user stop UltraGrid.AppImage.service
	mv /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service.old.reveal
	# set ug_args to generate and display smpte testcard
	ug_args="--tool uv -t testcard:pattern=smpte_bars -d vulkan_sdl2:fs --param use-hw-accel"
echo -e "[Unit]
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

hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)

#set -x
exec >/var/home/wavelet/logs/wavelet_reveal_decoder.log 2>&1

KEYNAME="/${hostNameSys}/DECODER_REVEAL"; read_etcd_global
		if [[ "${printvalue}" == 1 ]]; then
				echo -e "\ninput_update key is set to 1, continuing with task.. \n"
				detect_self
		else
				echo -e "\ninput_update key is set to 0, doing nothing.. \n"
				exit 0
		fi
