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
	KEYNAME="/hostLabel/${hostNameSys}/type"; read_etcd_global
	echo -e "Hostname is ${printvalue} \n"
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
	KEYNAME="/hostHash/${hostNameSys}/relabel_active"; KEYVALUE="1"; write_etcd_global
	KEYNAME="/${hostNameSys}/Hash"; read_etcd_global; myHostHash="${printvalue}"
	echo -e "My hash is ${myHostHash}, attempting to find a my new device label..\n"
	KEYNAME="/${hostNameSys}/hostNamePretty"; read_etcd_global; myNewHostLabel="${printvalue}"
	echo -e "My *New* host label is ${myNewHostLabel}!\n"
	if [[ "${hostNamePretty}" == "${myNewHostLabel}" ]]; then
		echo -e "New label and current Pretty hostname are identical, setting flag to 0 and doing nothing..\n"
		KEYNAME="/hostHash/${hostNamePretty}/relabel_active"; KEYVALUE="0"; write_etcd_global
		exit 0
	else
		echo -e "New label and current Pretty hostname are different, proceding to initiate change.."
		set_newLabel
	fi
}

set_newLabel(){
	# Verifies fqdn and parses new label
	echo -e "My old host label is ${oldLabel}"
	echo -e "My new host label is ${myNewHostLabel}"
	echo -e "My system hostname is ${hostNameSys}"
	# Check for current FQDN in the case someone wrote gibberish in the text box.
	FQDN=$(nslookup ${hostNamePretty} -i | grep ${hostNamePretty} | head -n 1)
	NAME=$(echo "${FQDN##*:}" | xargs)
	echo -e "HostName FQDN is ${NAME}"
	# Compare current FQDN with input FQDN and append if necessary
	currentfqdnString=$(echo "${NAME}%.*")
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
	# Generate the necessary files, then reboot.
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
	KEYNAME="/hostHash/${myHostHash}"; read_etcd_global; myHostLabel="${printvalue}"
	echo -e "My host label is ${myHostLabel}"
	KEYNAME="/${hostNameSys}/type"; read_etcd_global; type=${printvalue}
		if [[ "${type}" = "dec" ]]; then
			echo "I am currently a decoder switching to an encoder"
			typeSwitch="enc"
			systemctl --user enable \
				wavelet_device_redetect \
				wavelet_encoder_query.service \
				watch_encoderflag.service \
				wavelet_promote.service --now
			KEYNAME="/decoderip/${hostNameSys}"; delete_etcd_global
			KEYNAME="DEVICE_REDETECT"; KEYVALUE="1"; write_etcd_global
			KEYNAME="reload_reflector"; write_etcd_global
		else
			echo "I am not a decoder, switching to become a decoder.."
			typeSwitch="dec"
			systemctl --user disable \
				run_ug.service \
				wavelet_encoder.service \
				wavelet_encoder_query.service \
				watch_encoderflag.service --now
			remove_associated_inputs
		fi
	KEYNAME="/hostLabel/${hostNameSys}/type"; KEYVALUE="${typeSwitch}"; write_etcd_global
	KEYNAME="/${hostNameSys}/type"; write_etcd_global
	systemctl restart getty@tty1.service
}

remove_associated_inputs(){
	echo "Removing input devices associated with my hostname.."
	KEYNAME="/interface/${hostNamePretty}/"; read_etcd_prefix_global; read -a devHash <<< "${printvalue}"
	for i in ${devHash[@]}; do
		echo "Working on hash: ${i}"
		KEYNAME="/short_hash/${i}"; delete_etcd_key_global
		KEYNAME="/hash/${i}"; delete_etcd_key_global
		KEYNAME="/${hostNamePretty}/devpath_lookup/${i}"; delete_etcd_global
		KEYNAME="uv_hash_select"; read_etcd_global
		if [[ ${printvalue} = "${i}" ]]; then
			echo "current device is the selected device, resetting streaming to seal."
			KEYNAME="uv_hash_select"; KEYVALUE="seal"; write_etcd_global
			KEYNAME="ENCODER_QUERY"; KEYVALUE="2"; write_etcd_global
			KEYNAME="input_update"; KEYVALUE="1"; write_etcd_global
		fi
	done
	# Now we have processed ALL of the interface items on this host, we can remove the interface labels:
	KEYNAME="/interface/${hostNamePretty}/"; delete_etcd_key_prefix
	KEYNAME="/${hostNameSys}/inputs"; delete_etcd_key_prefix
	KEYNAME="/${hostNamePretty}/inputs"; delete_etcd_key_prefix
	KEYNAME="/${hostNameSys}/INPUT_DEVICE_PRESENT"; delete_etcd_key_global	
}

remove_host_keys(){
	echo "Disabling watcher services and removing any remaining host keys.."
	systemctl --user disable \
		wavelet_device_redetect.service \
		wavelet_encoder_reboot.service \
		wavelet_monitor_decoder_blank.service \
		wavelet_monitor_decoder_reboot.service \
		wavelet_monitor_decoder_reveal.service \
		wavelet_monitor_decoder_reset.service \
		watch_encoderflag.service \
		wavelet_deprovision.service \
		wavelet_detectv4l.service \
		wavelet_device_relabel.service \
		wavelet_encoder.service \
		wavelet_encoder_query.service \
		wavelet_promote.service \
		wavelet_reboot.service \
		wavelet_reset.service --now
	KEYNAME="/${hostNameSys}"; delete_etcd_prefix
	KEYNAME="/hostHash/${hostNameSys}"; delete_etcd_prefix
	echo "Host keys deleted, shutting down!"
	systemctl poweroff -i
}

set_newHostName(){
	myNewHostname=$@
	if hostnamectl hostname --pretty ${myNewHostname}; then
		echo -e "\nHost Name set as ${myNewHostName} successfully!, writing relabel_active to 0."
		KEYNAME="/hostHash/${hostNameSys}/relabel_active"; KEYVALUE="0";	write_etcd_global
		KEYNAME="/${hostNameSys}/RECENT_RELABEL";	KEYVALUE="1"; 			write_etcd_global
		echo "Done, no further actions needed."
	else
		echo -e "\n Hostname change command failed, please check logs\n"
		exit 1
	fi
}

event_hostNameChange() {
	KEYNAME="/${hostNameSys}/RELABEL"; read_etcd_global
	if [[ "${printvalue}" -eq "0" ]]; then
		echo -e "Relabel task bit for this hostname is set to 0, doing nothing.."
		exit 0
	fi
	echo -e "Relabel bits active, resetting them to 0 prior to starting task.."
	KEYNAME="/hostHash/${hostNameSys}/relabel_active"; KEYVALUE="0"; write_etcd_global
	KEYNAME="/${hostNameSys}/RELABEL"; KEYVALUE="0"; write_etcd_global
	detect_self
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
		"relabel")		echo -e "\nCalled with relabel argument, not calling prefix function..\n"		;	event_hostNameChange
		;;
		"deprovision")	echo -e "\nCalled with deprov argument, removing inputs..\n"					;	remove_associated_inputs	;	remove_host_keys
		;;
		*)				echo -e "\nCalled with invalid argument, not calling prefix function..\n"		;	event_hostNameChange
		;;
	esac
done