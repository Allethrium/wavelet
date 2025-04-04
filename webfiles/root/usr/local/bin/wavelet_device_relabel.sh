#!/bin/bash
# Called from the relabel watcher service
# We use the "pretty" hostname, the base hostname remains stable after imaging.


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
read_etcd_prefix_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_prefix_global" "${KEYNAME}")
	echo -e "Key Name: {$KEYNAME} read from etcd for global value $printvalue\n"
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


detect_self(){
	KEYNAME="/UI/hosts/${hostNameSys}/type"; read_etcd_global
	echo -e "Host type key is ${printvalue} \n"
	case ${printvalue} in
		enc*)                                   echo -e "I am an Encoder \n"            ;       check_label
		;;
		dec*)                                   echo -e "I am a Decoder \n"             ;       check_label
		;;
		svr*)                                   echo -e "I am a Server \n"              ;       exit 0
		;;
		*)                                      echo -e "This device is other \n"       ;       check_label
		;;
		esac
}

check_label(){
	# Finds our current hash and gets the new label from Etcd as set from UI
	oldLabel=${hostNamePretty}
	echo "${oldLabel}" > /home/wavelet/oldLabel.txt
	KEYNAME="/${hostNameSys}/Hash"; read_etcd_global; myHostHash="${printvalue}"
	echo -e "My hash is ${myHostHash}, attempting to find a my new device label..\n"
	KEYNAME="/UI/hosts/${hostNameSys}/control/label"; read_etcd_global; myNewHostLabel="${printvalue}"
	echo -e "My *New* host label is ${myNewHostLabel}!\n"
	if [[ "${hostNamePretty}" == "${myNewHostLabel}" ]]; then
		echo -e "New label and current Pretty hostname are identical, setting flag to 0 and doing nothing..\n"
		KEYNAME="/${hostNameSys}/relabel_active"; KEYVALUE="0"; write_etcd_global
		exit 0
	else
		echo -e "New label and current Pretty hostname are different, proceding to initiate change.."
		KEYNAME="/${hostNameSys}/relabel_active"; KEYVALUE="1"; write_etcd_global
		set_newLabel
	fi
}

set_newLabel(){
	# Verifies fqdn and parses new label
	echo -e "My old host label is ${oldLabel}"
	echo -e "My new host label is ${myNewHostLabel}"
	echo -e "My system hostname is ${hostNameSys}"
	# Check for current FQDN in the case someone wrote gibberish in the text box.
	currentfqdnString=${hostNameSys}
	inputfqdnString=$(echo "${myNewHostLabel}%.*")
	if [[ "${currentfqdnString} == ${inputfqdnString}" ]]; then
		echo -e "FQDN strings are correct, proceeding.."
		appendedHostName=${myNewHostLabel}
	else
		echo -e "New label was input without an FQDN, appending automatically..\n"
		appendedHostName="${myNewHostLabel}.${currentfqnString}"
		echo -e "Generated FQDN hostname as ${appendedHostName}\n"
	fi
	echo "${appendedHostName}" > newHostName.txt
	KEYNAME="/${hostNameSys}/RECENT_RELABEL"; KEYVALUE="1"; write_etcd_global
	# Generate the necessary files, then reboot if needed.
	set_newHostName ${appendedHostName}
}

event_prefix_set(){
	# Switches the type designator under /hostLabel/$(hostname)/type
	# First, disable all reset watchers so that the host isn't instructed to reboot the moment a flag changes!
	systemctl --user disable \
		wavelet_device_redetect.service \
		wavelet_encoder_reboot.service \
		wavelet_monitor_decoder_blank.service \
		wavelet_monitor_decoder_reboot.service \
		wavelet_monitor_decoder_reveal.service \
		wavelet_monitor_decoder_reset.service --now
	KEYNAME="/${hostNameSys}/Hash"; read_etcd_global; myHostHash="${printvalue}"
	KEYNAME="/UI/hosts/${hostNameSys}/control/label"; read_etcd_global; myHostLabel="${printvalue}"
	echo -e "My host label is ${myHostLabel}"
	KEYNAME="/UI/hosts/${hostNameSys}/type"; read_etcd_global; type=${printvalue}
		if [[ "${type}" = "dec" ]]; then
			echo "I am currently a decoder switching to an encoder"
			typeSwitch="enc"
			event_generate_wavelet_encoder_query
			systemctl --user enable \
				wavelet_device_redetect \
				wavelet_encoder_query.service \
				wavelet_promote.service --now
			KEYNAME="/DECODERIP/${hostNameSys}"; delete_etcd_key_global
			KEYNAME="NEW_DEVICE_ATTACHED"; KEYVALUE="1"; write_etcd_global
			#myHostLabel=$(echo ${myHostLabel} | cut -c 4-)
			#hostNamePretty="${typeSwitch}${myHostLabel}"
		else
			echo "I am not a decoder, switching to become a decoder.."
			typeSwitch="dec"
			systemctl --user disable \
				run_ug.service \
				wavelet_encoder.service \
				wavelet_encoder_query.service \
				watch_encoderflag.service --now
			remove_associated_inputs
			KEYNAME=/UI/UV_HASH_SELECT; read_etcd_global; currentInputHash=${printvalue}
			KEYNAME=/UI/UV_HASH_SELECT_OLD; read_etcd_global; previousInputHash=${printvalue}
			if [[ ${currentInputHash} == ${previousInputHash} ]]; then
				echo "This is the current and previously active device, wavelet will switch back to the SEAL option."
				KEYNAME="ENCODER_QUERY"; KEYVALUE="SEAL"
			else
				# needs client rw on the target key
				KEYNAME="ENCODER_QUERY"; KEYVALUE=${previousInputHash}; write_etcd_global
			fi
		#myHostLabel=$(echo ${myHostLabel} | cut -c 4-)
		#hostNamePretty="${typeSwitch}${myHostLabel}"
		fi
	KEYNAME="/UI/hosts/${hostNameSys}/type"; KEYVALUE="${typeSwitch}"; write_etcd_global
	KEYNAME="/${hostNameSys}/type"; write_etcd_global
	#KEYNAME="/UI/hosts/${hostNameSys}/control/label"; KEYVALUE="${hostNamePretty}"; write_etcd_global
	systemctl restart getty@tty1.service
}

event_generate_wavelet_encoder_query(){
	# Taken from build_ug.sh, easier to replicate this here.
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service "ENCODER_QUERY" 0 0 "wavelet_encoder_query"
}

remove_associated_inputs(){
	echo "Removing input devices associated with my hostname.."
	KEYNAME="/UI/interface/${hostNameSys}"; read_etcd_prefix_global; read -a devHash <<< "${printvalue}"
	for i in ${devHash[@]}; do
		KEYNAME="/UI/UV_HASH_SELECT"; read_etcd_global
		if [[ ${printvalue} = "${i}" ]]; then
			echo "current device is the selected device, resetting streaming to seal."
			KEYNAME="/UI/UV_HASH_SELECT"; KEYVALUE="seal"; write_etcd_global
			KEYNAME="ENCODER_QUERY"; KEYVALUE="2"; write_etcd_global
			# this is deprecated
			#KEYNAME="input_update"; KEYVALUE="1"; write_etcd_global
		fi
		echo "Working on hash: ${i}"
		KEYNAME="/UI/short_hash/${i}"; read_etcd_global; deviceLabel=${printvalue}
		KEYNAME="/UI/short_hash/${i}"; delete_etcd_key_global
		KEYNAME="/UI/interface/${deviceLabel}"; delete_etcd_key_global
		KEYNAME="/${hostNameSys}/devpath_lookup/${i}"; delete_etcd_key_global
	done
	# Now we have processed ALL of the UI items on this host, we can remove the interface items from the host system side:
	KEYNAME="/${hostNameSys}/inputs"; delete_etcd_key_prefix
	KEYNAME="/${hostNameSys}/INPUT_DEVICE_PRESENT"; delete_etcd_key_global
}

set_newHostName(){
	myNewHostname=$@
	if hostnamectl hostname --pretty ${myNewHostname}; then
		echo -e "\nHost Name set as ${myNewHostName} successfully!, writing relabel_active to 0."
		KEYNAME="/${hostNameSys}/relabel_active"; KEYVALUE="0";	write_etcd_global
		KEYNAME="/${hostNameSys}/RECENT_RELABEL"; KEYVALUE="1"; write_etcd_global
		echo "Done, no further actions needed."
	else
		echo -e "\n Hostname change command failed, please check logs\n"
		exit 1
	fi
}


###
#
# Main
#
###

#set -x
# Check for pre-existing log file
logName=/var/home/wavelet/logs/changehostname.log
if [[ -e $logName || -L $logName ]] ; then
	i=0
	while [[ -e $logName-$i || -L $logName-$i ]] ; do
		let i++
	done
	logName=$logName-$i
fi
exec > "${logName}" 2>&1

# Parse input options (I.E if called by promote service)
echo -e "Called from SystemD unit parsing input options: ${@}.."
hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
for arg in "$@"; do
	echo -e "\nArgument is: ${arg}\n"
	case ${arg} in
		dec*)			echo -e "\nCalled with decoder argument, promoting to Encoder\n"				;	event_prefix_set "${arg}"
		;;
		enc*)			echo -e "\nCalled with encoder argument, promoting to Decoder\n"				;	event_prefix_set "${arg}"
		;;
		"relabel")		echo -e "\nCalled with relabel argument, not calling prefix function..\n"		;	detect_self
		;;
		*)				echo -e "\nCalled with invalid argument, not calling prefix function..\n"		;	detect_self
		;;
	esac
done