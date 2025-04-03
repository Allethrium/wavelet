#!/bin/bash
# Bluetooth module, tweaked in this case to automatically connect to nearest ExUBT Tesira system, which is what we currently use
# Called from webUI after bluetooth MAC field update, or failing that called from cached value already present in system upon reboot


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


main(){
	# set bluetooth connection notification bit to 0
	KEYNAME="/audio/bluetooth_connect_notify"; KEYVALUE="0"; write_etcd_global

	# check to see if audio is even enabled, if not, we exit 0
	KEYNAME="/ui/audio"; read_etcd_global
	if [[ "${printvalue}" -eq "0" ]]; then
	echo -e "\nAudio bit is not enabled, disabling bluetooth and exiting\n"
	echo -e 'power off\n' | bluetoothctl
	exit 0
	fi

	# Get bluetooth MAC for ExUBT (set in Audio control portion on webUI)
	KEYNAME="/interface/audio/bluetooth_mac"; read_etcd_global; bluetoothMAC=${printvalue}
	# if bluetoothMAC=""; then
	# echo -e "Bluetooth MAC ID is not populated! Exiting and resetting connect bit"
	# KEYNAME="/interface/bluetooth_connect_active"
	# KEYVALUE="0"
	# write_etcd_global

	# we echo a set of commands to bluetoothctl here.  Obviously this won't work if the server machine has no bluetooth capability!
	# ... so we might want to include a test here and disable the entire area on the webUI if it isn't there?
	echo -e 'power on\n' | bluetoothctl
	echo -e 'default-agent\n' | bluetoothctl
	echo -e 'discoverable on\ndiscoverable-timeout 100\nscan on\n' | bluetoothctl
	sleep 10
	echo -e 'pairable on\n' | bluetoothctl
	echo -e "trust ${bluetoothMAC}\n" | bluetoothctl
	echo -e "pair ${bluetoothMAC}\n" | bluetoothctl
	echo -e "connect ${bluetoothMAC}\n" | bluetoothctl
	# Clean up to stop unauthorized pairing
	echo -e 'pairable off\n' | bluetoothctl

	# Set bluetooth connection successful for webUI tracking
	KEYNAME="/interface/audio/bluetooth_connect_active"; KEYVALUE="1"; write_etcd_global
	echo -e "Bluetooth connection set for ${bluetoothMAC}"
	# do we need to do anything with Pipewire here to set the exUBT/BT device as the audio sink?  
}

hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)

#set -x
exec >/var/home/wavelet/logs/bluetooth_connect.log 2>&1
main