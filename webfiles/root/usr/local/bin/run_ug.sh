#!/bin/bash
# Checks device hostname to define behavior and launches services as appropriate

detect_self(){
	# Detect_self in this case relies on the etcd type key
	KEYNAME="/hostLabel/${hostNameSys}/type"; read_etcd_global
	echo -e "Host type is: ${printvalue}\n"
	case "${printvalue}" in
		enc*) 					echo -e "I am an Encoder"; event_encoder
		;;
		decX.wavelet.local)		echo -e "I am a Decoder, but my hostname is generic.\nAn error has occurred at some point, and needs troubleshooting.\nTerminating process."; exit 0
		;;
		dec*)					echo -e "I am a Decoder"; event_decoder
		;;
		svr*)					echo -e "I am a Server."; event_server
		;;
		*) 						echo -e "This device Hostname is not set appropriately, exiting"; exit 0
		;;
	esac
}

ipaddr
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

event_server(){
	# The server is a special case because it serves blanks screen, static image and test bars.
	# As a result, instead of using the normal runner, it calls wavelet_init.service
	# Ensure web interface is up
	systemctl --user start http-php-pod.service
	# Check for input devices
	KEYNAME="/${hostNameSys}/INPUT_DEVICE_PRESENT"; read_etcd_global
	if [[ "$printvalue" -eq 1 ]]; then
		echo -e "An input device is present on this server, proceeding\n"
		event_encoder_server
	else 
		echo -e "No input devices are present on this server.  System will serve static image/blank/SMPTE bars by default.\n"
		systemctl --user start wavelet_init.service
	fi
}

event_encoder_server() {
# Runs the server, then calls the encoder event.
	if systemctl --user is-active --quiet wavelet_controller; then
		echo -e "wavelet_controller service is running and watching for input events, continuing..."
		event_encoder
	else
		echo -e "\nController is inactive!  Bringing up Wavelet controller service, and sleeping for one second to allow config to settle..."
		systemctl --user start wavelet_init.service
		sleep 1
		echo -e "\n Running encoder..."
		event_encoder
	fi
}

event_encoder(){
	# Registers self as a decoder in etcd for the reflector to query & include in its client args
	echo -e "Calling wavelet_encoder systemd unit.."
	KEYNAME="/${hostNameSys}/ENCODER_BLANK"; KEYVALUE="0"; write_etcd_global
	# Telling Wavelet that this host will be actively streaming
	KEYNAME="ENCODER_ACTIVE"; KEYVALUE="${hostNamePretty}"; write_etcd_global
	# Call wavelet_encoder.service which will provision and start the AppImage proper
	systemctl --user start wavelet_encoder.service
}

event_decoder(){
	# Registers self as a decoder in etcd for the reflector to query & include in its client args
	echo -e "Populated IP Address is: ${IPVALUE}"
	KEYVALUE=${IPVALUE}
	write_etcd_client_ip
	# Ensure all reset, reveal and reboot flags are set to 0 so they are
	# 1) populated
	# 2) not active so the new device goes into a reboot/reset/reveal loop
	KEYNAME="/${hostNameSys}/DECODER_RESET"; KEYVALUE="0"; write_etcd_global
	KEYNAME="/${hostNameSys}/DECODER_REVEAL"; write_etcd_global
	KEYNAME="/${hostNameSys}/DECODER_REBOOT"; write_etcd_global
	KEYNAME="/${hostNameSys}/DECODER_BLANK"; write_etcd_global
	# Enable watcher services now all task activation keys are set to 0
	systemctl --user enable \
		wavelet_decoder_reset.service \
		wavelet_decoder_reveal.service \
		wavelet_decoder_reboot.service \
		wavelet_decoder_blank.service \
		wavelet_device_relabel.service \
		wavelet_promote.service --now
	# Note - ExecStartPre=-swaymsg workspace 2 is a failable command 
	# It will always send the UG output to a second display.  
	# If not connected the primary display will be used.
	# Tries three possible GPU devices for acceleration in order of efficiency, before failing.
	# If it crashes, you have hw/driver issues someplace or an improperly configured display env.
		KEYNAME=UG_ARGS; ug_args="--tool uv -d vulkan_sdl2:fs:keep-aspect:nocursor:nodecorate -r pipewire"; KEYVALUE="${ug_args}"; write_etcd
		rm -rf /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
		echo "
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
		systemctl --user restart UltraGrid.AppImage.service
		echo -e "Decoder systemd units instructed to start..\n"
		sleep 1
		return=$(systemctl --user is-active --quiet UltraGrid.AppImage.service)
		if [[ ${return} -eq !0 ]]; then
			echo "Decoder failed to start, there may be something wrong with the system.
			\nTrying GL as a fallback, and then failing for good.."
			KEYNAME=UG_ARGS; ug_args="--tool uv -d gl:fs -r pipewire"; KEYVALUE="${ug_args}"; write_etcd
			rm -rf /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
			echo "
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
			systemctl --user restart UltraGrid.AppImage.service
		else
			:
		fi
	get_ipValue
}

get_ipValue(){
	# Gets the current IP address for this host to register into server etcd.
	# Identify Ethernet interfaces by checking for "eth" in their name
	# There HAS to be a better way of doing this?
	primaryConnection=$(nmcli -g name con show | head -1)
	primaryConnectionIP=$(nmcli -f IP4 con show "${primaryConnection}" | grep IP4.ADDRESS | awk '{print $2}')
	echo -e "Detected primary connection \"${primaryConnection}\" with IP Address of \"${primaryConnectionIP}\""
	IPVALUE=${primaryConnectionIP%/*}
	# IP value MUST be populated or the decoder writes gibberish into the server
	if [[ "${IPVALUE}" == "" ]] then
			# sleep for two seconds, then call yourself again
			echo -e "IP Address is null, sleeping and calling function again\n"
			sleep 2
			get_ipValue
		else
			echo -e "IP Address is not null, testing for validity..\n"
			valid_ipv4() {
				local ip=$1 regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
				if [[ $ip =~ $regex ]]; then
					echo -e "\nIP Address is valid as ${ip}, continuing.."
					KEYNAME="/hostHash/${hostNameSys}/ipaddr"; KEYVALUE="${ip}"; write_etcd_global
					KEYNAME="/UI/${hostNameSys}/IP"; write_etcd_global
				else
					echo -e "IP Address is not valid, sleeping and calling function again\n"
					get_ipValue
				fi
			}
			valid_ipv4 "${IPVALUE}"
	fi
}

#####
#
# Main
#
#####



hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
#set -x
exec >/var/home/wavelet/logs/run_ug.log 2>&1
get_ipValue
detect_self