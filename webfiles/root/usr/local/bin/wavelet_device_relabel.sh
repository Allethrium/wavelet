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
	KEYNAME="/hostHash/$(hostname)/relabel_active"
	KEYVALUE="1"
	write_etcd_global
	KEYNAME="/$(hostname)/Hash"
	read_etcd_global
	myHostHash="${printvalue}"
	echo -e "My hash is ${myHostHash}, attempting to find a my Current device label..\n"
	KEYNAME="/hostHash/${myHostHash}/newHostLabel"
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
		echo $(hostname) > /home/wavelet/oldhostname.txt
		set_newLabel
	fi
}

set_newLabel(){
	# Finds our current hash and gets the new label from Etcd as set from UI
	KEYNAME="/$(hostname)/Hash"
	read_etcd_global
	myHostHash="${printvalue}"
	echo -e "My hash is ${myHostHash}, attempting to find a new device label..\n"
	KEYNAME="/hostHash/${myHostHash}/newHostLabel"
	read_etcd_global
	myNewHostLabel="${printvalue}"
	echo -e "My new host label is ${myNewHostLabel}!\n"
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
	# Generate the necessary files, then reboot and let run/build_ug handle everything from there.
	systemctl reboot
}

event_prefix_set(){
	# Finds our current hash and gets the current label from Etcd as set from UI
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
	if [[ "${arg}" == "dec" ]]; then
		appendedHostName=$(echo -e "${appendedHostName}" | sed "s|${arg}|enc|g")
	else
		appendedHostName=$(echo -e "${appendedHostName}" | sed "s|${arg}|dec|g")
	fi
	# Generate the necessary files, then reboot and let run/build_ug handle everything from there.
	echo -e "Switched host identifier from ${arg}, generating ref file as ${appendedHostName}, and instructing host to reboot..\n"
	KEYNAME="/hostHash/${myHostHash}/newHostLabel"
	KEYVALUE="${appendedHostName}"
	write_etcd_global
	echo $(hostname) > /home/wavelet/oldhostname.txt
	echo -e "${appendedHostName}" > newHostName.txt
	systemctl reboot
}

###
#
# Main
#
###

# Parse input options (I.E if called by promote service)
for arg in "$@"; do
	case  ${arg^^} in
		DEC*)   echo -e "Called with decoder argument, promoting to Encoder\n" 			 	;	event_prefix_set "${arg}"; exit 0
		;;
		ENC*)   echo -e "Called with encoder argument, promoting to Decoder\n"  			;	event_prefix_set "${arg}"; exit 0
		;;
		*)  	echo -e "Called with invalid argument, not calling prefix function..\n"		;
	esac
done

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

KEYNAME="/$(hostname)/RELABEL"
read_etcd_global
if [[ "${printvalue}" -eq "0" ]]; then
	echo -e "Relabel bit for this hostname is set to 0, doing nothing.."
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