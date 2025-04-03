#!/bin/bash
#
# This module is run exclusively on the server and will poll a deprovisioned host's keys after thirty seconds
# If the key is still active after this timer expires, the server will forcibly remove the host's keys from the system
# This runs under the standard server context and thus has access to /UI and also host subkeys.

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


check_and_wait(){
	# Checks the deprovision flag is 1, then checks the system deprovision active flag.  If no changes occur in 30s, move to next step.
	KEYNAME="/UI/hosts/${hostNameSys}/control/DEPROVISION"; read_etcd_global
	if [[ ${printvalue} == 1 ]]; then
		echo "UI deprovision key is set to 1, setting the system deprovision key and waiting"
		KEYNAME="/${hostNameSys}/DEPROVISION_ACTIVE"; KEYVALUE=1; write_etcd_global
		sleep 30
		read_etcd_global
		if [[ ${printvalue} == 1 ]]; then 
			echo "Deprovision key is still active after thirty seconds, deprovisioning has failed or the host is nonresponsive."
			echo "Forcing deprovision.."
			# Remove host system keys
			KEYNAME="/${hostNameSys}"; delete_etcd_key_prefix
			# Remove host UI keys
			KEYNAME="/UI/hosts/${hostNameSys}"; delete_etcd_key_prefix
			KEYNAME="/UI/hostHash/${hostNameSys}"; delete_etcd_key_prefix
			KEYNAME="/UI/hostlist/${hostNameSys}"; delete_etcd_key_prefix
			# Remove IP registration for reflector
			KEYNAME="/DECODERIP/${hostNameSys}"
			# Remove host user and roles - needs to call service from wavelet-root for etcd root permissions!
			KEYNAME="/PROV/FORCE_REMOVE"; KEYVALUE="${hostNameSys}"; write_etcd_global
			if [[ ${hostNameSys} == *"enc" ]]; then
				# Check if I am the active encoder, and reset feed to seal
				KEYNAME="ENCODER_QUERY"; read_etcd_global; currentHash=${printvalue}
				KEYNAME="/UI/short_hash/${currentHash}"; read_etcd_global; targetHost="${printvalue%/*}"
				if [[ "${targetHost}" == *"${hostNamePretty}"* ]]; then
					echo -e "The active input is hosted from me!  Setting the current stream back to the static image."
					KEYNAME="ENCODER_QUERY"; KEYVALUE=SEAL; write_etcd_global
				fi
		else
			echo "Key is gone, or null - deprovisioning completed, doing nothing."
			exit 0
		fi
	else
		echo "Deprovision key is not active or doesn't exist, doing nothing."
		exit 0
	fi
}


#####
#
# Main 
#
#####


logName=/var/home/wavelet/logs/force_deprovision.log

set -x
exec >> "${logName}" 2>&1
callingKey=$ETCD_WATCH_KEY
echo "Called with ${ETCD_WATCH_KEY}"
hostNameSys="${ETCD_WATCH_KEY#*/UI/hosts/}"
hostNameSys="${hostNameSys%%/*}"

if [[ ${hostNameSys} == "" ]]; then
	echo "system hostname not populated!"
	exit 1
fi
echo "Host name: ${hostNameSys}"
check_and_wait