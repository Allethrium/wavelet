#!/bin/bash
# Called from the relabel watcher service
# Generates an oldHostName file in /home/wavelet and restarts run_ug.sh to start detection process

#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
read_etcd(){
	ETCDCTL_API=3 printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get /$(hostname)/${KEYNAME} --print-value-only)
	echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_prefix(){
	ETCDCTL_API=3 printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix /$(hostname)/${KEYNAME} --print-value-only)
	echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_global(){
	ETCDCTL_API=3 printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
	echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for Global value"
}

write_etcd(){
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
	echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}

write_etcd_global(){
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
	echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
}

write_etcd_clientip(){
	# Variable changed to IPVALUE because the module was picking up incorrect variables and applying them to /decoderip !
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put /decoderip/$(hostname) "${IPVALUE}"
	echo -e "decoderip/$(hostname) set to ${IPVALUE} for Global value"
}
read_etcd_clients_ip() {
	ETCDCTL_API=3 return_etcd_clients_ip=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix /decoderip/ --print-value-only)
}

detect_self(){
systemctl --user daemon-reload
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
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
	oldHostName=$(hostname)
	echo "${oldHostName}" > /home/wavelet/oldHostName.txt
	KEYNAME="/hostHash/$(hostname)/relabel_active"
	KEYVALUE="1"
	write_etcd_global
	KEYNAME="/$(hostname)/Hash"
	read_etcd_global
	myHostHash="${printvalue}"
	echo -e "My hash is ${myHostHash}, attempting to find a my new device label..\n"
	KEYNAME="/hostHash/${myHostHash}/newHostLabel"
	read_etcd_global
	myNewHostLabel="${printvalue}"
	echo -e "My *New* host label is ${myNewHostLabel}!\n"
	if [[ "$(hostname)" == "${myNewHostLabel}" ]]; then
		echo -e "New label and current hostname are identical, doing nothing..\n"
		KEYNAME="/hostHash/$(hostname)/relabel_active"
		KEYVALUE="0"
		write_etcd_global
		exit 0
	else
		echo -e "New label and current hostname are different, proceding to initiate change.."
		currentHostName=$(hostname)
		set_newLabel
	fi
}

set_newLabel(){
	# Verifies fqdn and parses new label
	echo -e "My old host label is ${oldHostName}\n"
	echo -e "My new host label is ${myNewHostLabel}\n"
	# Check for current FQDN in the case someone wrote gibberish in the text box.
	FQDN=$(nslookup $(hostname) -i | grep $(hostname) | head -n 1)
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
	KEYNAME="/hostHash/${myHostHash}/newHostLabel"
	# remove the newHostLabel value
	etcdctl --endpoints=${ETCDENDPOINT} del ${KEYNAME}
	KEYNAME="${currentHostName}/RECENT_RELABEL"
	KEYVALUE="1"
	write_etcd_global
	# Generate the necessary files, then reboot.
	set_newHostName ${appendedHostName}
}

event_prefix_set(){
	# Finds our current hash and gets the current label from Etcd as set from UI
	# First, disable all reset watchers so that the host isn't instructed to reboot the moment a flag changes!
	systemctl --user disable wavelet_device_redetect.service --now
	systemctl --user disable wavelet_encoder_reboot.service --now
	systemctl --user disable wavelet_monitor_decoder_blank.service --now
	systemctl --user disable wavelet_monitor_decoder_reboot.service --now
	systemctl --user disable wavelet_monitor_decoder_reveal.service --now
	systemctl --user disable wavelet_monitor_decoder_reset.service --now
	systemctl --user disable wavelet_device_relabel.service --now
	KEYNAME="/$(hostname)/Hash"
	read_etcd_global
	myHostHash="${printvalue}"
	KEYNAME="/hostHash/${myHostHash}"
	read_etcd_global
	myHostLabel="${printvalue}"
	echo -e "My host label is ${myHostLabel}!\n"
	FQDN=$(nslookup $(hostname) -i | grep $(hostname) | head -n 1)
	NAME=$(echo "${FQDN##*:}" | xargs)
	echo -e "HostName FQDN is ${NAME}"
	# Compare current FQDN with input FQDN and append if necessary
	currentfqdnString=${NAME}
	inputfqdnString=${myHostLabel}
	if [[ "${currentfqdnString}" == "${inputfqdnString}" ]]; then
		echo -e "FQDN strings are correct, proceeding.."
		appendedHostName=${inputfqdnString}
	else
		echo -e "New label was input without an FQDN, appending automatically..\n"
		appendedHostName="${myNewHostLabel}.${currentfqnString}"
		echo -e "Generated FQDN hostname as ${appendedHostName}\n"
	fi
	# Replace dec with enc or enc with dec as appropriate..
	echo -e "Performing search and replace for ${arg} in ${appendedHostName}\n"
	if [[ "${arg}" == "dec" ]]; then
		concatHostName=$(echo -e "${appendedHostName,,}" | sed "s|${arg,,}|enc|g")
	else
		concatHostName=$(echo -e "${appendedHostName,,}" | sed "s|${arg,,}|dec|g")
	fi
	# Generate the necessary files, then reboot.
	echo -e "Switched host identifier from ${arg}, generating new host label as: ${concatHostName,,}, and instructing host to reboot..\n"
	KEYNAME="/hostHash/${myHostHash}/newHostLabel";	KEYVALUE="${concatHostName}";	write_etcd_global
	KEYNAME="/${concatHostName}/RECENT_RELABEL";	KEYVALUE="1";	write_etcd_global
	echo $(hostname) > /home/wavelet/oldHostName.txt
	echo -e "${concatHostName,,}" > /home/wavelet/newHostName.txt
	remove_old_keys ${oldHostName}
	if sudo hostnamectl hostname ${concatHostName,,}; then
		echo -e "\nHost Name set as ${concatHostName,,} successfully!  rebooting!\n"
		systemctl reboot
	else
		echo -e "\n Hostname change command failed, please check logs\n"
		exit 1
	fi	
}

remove_old_keys(){
	# Get the old hostname from the file, then remove it because it's not necessary until the hostname is changed again.
	oldHostName=$(cat /home/wavelet/oldHostName.txt)
	echo -e "Detecting device type of ${oldHostName}"
	case ${oldHostName} in
	enc*) 					echo -e "\nI was an Encoder\n"					; clean_oldEncoderHostnameSettings ${oldHostname}
	;;
	decX.wavelet.local)		echo -e "\nI was an unconfigured Decoder\n"		; exit 0
	;;
	dec*)					echo -e "\nI was a Decoder \n"					; clean_oldDecoderHostnameSettings ${oldHostname}
	;;
	livestream*)			echo -e "\nI was a Livestreamer \n"				; clean_oldLivestreamHostnameSettings ${oldHostname}
	;;
	gateway*)				echo -e "\nI was an input Gateway\n"  			; clean_oldGatewayHostnameSettings ${oldHostname}
	;;
	svr*)					echo -e "\nI was a Server. Proceeding..."			; clean_oldServerHostnameSettings ${oldHostname}
	;;
	*) 						echo -e "\nThis device Hostname was not set appropriately, exiting \n" && exit 0
	;;
	esac
}

clean_oldEncoderHostnameSettings(){
	# Finds and cleans up any references in etcd to the old hostname
	# Delete all reverse lookups, labels and hashes for this device
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /encoderlabel/${oldHostName} --prefix
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /hostHash/${oldHostName} --prefix
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /hostLabel/${oldHostName} --prefix
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /${oldHostName} --prefix
}

clean_oldDecoderHostnameSettings(){
	# Finds and cleans up any references in etcd to the old hostname
	# Delete all reverse lookups, labels and hashes for this device
	echo -e "Attempting to remove all legacy keys for: ${oldHostName}\n"
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /hostLabel/${oldHostName} --prefix
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /hostHash/${oldHostName} --prefix
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /hostLabel/${oldHostName} --prefix
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /${oldHostName} --prefix
}

clean_oldLivestreamHostnameSettings(){
	# Finds and cleans up any references in etcd to the old hostname
	# We'd be doing livestream specific stuff here, but since we haven't developed that feature this is just here as a placeholder
	echo -e "\nRemoving and disabling services referring to his host's previous role as a livestreamer..\n"
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /livestreamlabel/${oldHostName} --prefix
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /hostHash/${oldHostName} --prefix
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /hostLabel/${oldHostName} --prefix
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /${oldHostName} --prefix
}

clean_oldGatewayHostnameSettings(){
	# Finds and cleans up any references in etcd to the old hostname
	# We'd be doing gateway specific stuff here, but since we haven't developed that feature this is just here as a placeholder
	# Delete all reverse lookups, labels and hashes for this device
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /gatewaylabel/${oldHostName} --prefix
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /hostHash/${oldHostName} --prefix
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /hostLabel/${oldHostName} --prefix
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del /${oldHostName} --prefix
}

clean_oldServerHostnameSettings(){
	# Finds and cleans up any references in etcd to the old hostname
	# The server has many more settings than any other device with the way the system currently works.
	# This is also a silly function to have, but putting it here for completeness' sake.
	# Delete all reverse lookups, labels and hashes for this device
	echo -e "\nDeleting the server is quite a silly thing to do.  So we won't be doing that.\n"  
	exit 0
}

set_newHostName(){
	myNewHostname=${appendedHostName}
	remove_old_keys "${oldHostName}"
	# added a sudo rule for this.. less than ideal but.. meh
	if sudo hostnamectl hostname ${myNewHostname}; then
		echo -e "\n Host Name set as ${myNewHostName} successfully!, writing relabel_active to 0 and rebooting!\n"
		KEYNAME="/hostHash/${myNewHostname}/relabel_active";	KEYVALUE="0"; write_etcd_global
		KEYNAME="/${myNewHostname}/RECENT_RELABEL";	KEYVALUE="1"; write_etcd_global
		systemctl reboot
	else
		echo -e "\n Hostname change command failed, please check logs\n"
		exit 1
	fi
}

event_hostNameChange() {
# Check to see if hostname has changed since last session
if [[ -f /home/wavelet/oldhostname.txt ]]; then
		check_hostname
fi


KEYNAME="/$(hostname)/RELABEL"
read_etcd_global
if [[ "${printvalue}" -eq "0" ]]; then
	echo -e "Relabel task bit for this hostname is set to 0, doing nothing.."
	exit 0
fi

echo -e "Relabel bits active, resetting them to 0 prior to starting task.."
KEYNAME="/hostHash/$(hostname)/relabel_active"
KEYVALUE="0"
write_etcd_global
KEYNAME="/$(hostname)/RELABEL"
KEYVALUE="0"
write_etcd_global
detect_self
}

###
#
# Main
#
###

set -x
# Check for pre-existing log file
# This is necessary because of system restarts, the log will get overwritten, and we need to see what it's doing across reboots.
logName=/home/wavelet/changehostname.log
if [[ -e $logName || -L $logName ]] ; then
	i=0
	while [[ -e $logName-$i || -L $logName-$i ]] ; do
		let i++
	done
	logName=$logName-$i
fi
exec > "${logName}" 2>&1

# Parse input options (I.E if called by promote service)
echo -e "Parsing input options..\n"
for arg in "$@"; do
	echo -e "\nArgument is: ${arg}\n"
	case ${arg} in
		dec*)		echo -e "\nCalled with decoder argument, promoting to Encoder\n"				;	event_prefix_set "${arg}"
		;;
		enc*)		echo -e "\nCalled with encoder argument, promoting to Decoder\n"				;	event_prefix_set "${arg}"
		;;
		"relabel")	echo -e "\nCalled with relabel argument, not calling prefix function..\n"		;	event_hostNameChange
		;;
		*)			echo -e "\nCalled with invalid argument, not calling prefix function..\n"		;	event_hostNameChange
		;;
	esac
done