#!/bin/bash
# Bluetooth module, tweaked in this case to automatically connect to nearest ExUBT Tesira system, which is what we currently use
# Called from webUI after bluetooth MAC field update, or failing that called from cached value already present in system upon reboot

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

main(){
	# etcdctl set bluetooth connection notification bit to 0
	KEYNAME="/audio/bluetooth_connect_notify"
	KEYVALUE="0"
	write_etcd_global

	# check to see if audio is even enabled, if not, we exit 0
	KEYNAME="/audio_interface/bluetooth_connect_active"
	read_etcd_global
	if [[ "${printvalue}" -eq "0" ]]; then
	echo -e "\nAudio bit is not enabled, disabling bluetooth and exiting\n"
	echo -e 'power off\n' | bluetoothctl
	exit 0
	fi

	# etcdctl - get bluetooth MAC for ExUBT (set in Audio control portion on webUI)
	KEYNAME="/audio_interface_bluetooth_mac"
	read_etcd_global
	bluetoothMAC=${printvalue}
	# if bluetoothMAC=""; then
	# echo -e "Bluetooth MAC ID is not populated! Exiting and resetting connect bit"
	# KEYNAME="/interface/bluetooth_connect_active"
	# KEYVALUE="0"
	# write_etcd_global

	# we echo a set of commands to bluetoothctl here.  Obviously this won't work if the server machine has no bluetooth capability!
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

	# etcdctl set bluetooth connection successful for webUI tracking
	KEYNAME="/audio_interface/bluetooth_connect_active"
	KEYVALUE="1"
	write_etcd_global
	echo -e "Bluetooth connection set for ${bluetoothMAC}"
	# do we need to do anything with Pipewire here to set the exUBT/BT device as the audio sink?  
}


set -x
exec >/home/wavelet/bluetooth_connect.log 2>&1
main