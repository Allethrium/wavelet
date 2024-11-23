#!/bin/bash
# Ref Arch Linux Wiki - https://wiki.archlinux.org/title/WirePlumber

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


main(){
	# Create a new sink called Simultaneous Output
	pw-cli create-node adapter '{ factory.name=support.null-audio-sink node.name="SimultaneousOutput" \
								node.description="SimultaneousOutput" media.class=Audio/Sink object.linger=true \
								audio.position=[FL FR] }'
	
	# etcdctl find current video source
	KEYNAME="uv_hash_select"; read_etcd_global; currentVideoInputHash=${printvalue}
	KEYNAME="/short_hash/${currentVideoInputHash}"; read_etcd_global; currentVideoPath=${printvalue}

	case in ${currentVideoPath}
		if we have a magewell device we probably have a serial number
			;;
		if we have an IPEVO device, we probably won't want audio from it 
			;;
		if we have an LG capture card, we will just pick one and hope for the best..
			;;
	esac

	magewell(){
		grep for serial number
		return search string
	}

	ipevo(){
		find any audio that's sqawking at all and select it
		return search string
	}

	lgCapture(){
		find any lg device we can
		return search string
	}

	# compare current video source to available audio inputs, start w/ Vendor and then run through serial# etc..
	# if ${searchstring} match; then
	# ${audioInputL}= grep for searchstring | grep for FL
	# ${audioInputR}= grep for searchstring | grep for FL
	
	# etdctl pull bluetooth MAC address
	KEYNAME="/interface/bluetooth_mac"
	read_etcd_global
	bluetoothMAC=${printvalue}
	# find bluez output for BT MAC
	${btAudioOutL}=$(pw-link -o | grep bluez_output | grep ${bluetoothMAC} | grep FL)
	${btAudioOutL}=$(pw-link -o | grep bluez_output | grep ${bluetoothMAC} | grep FR)
	# pw-link ${audioInputL} ${btAudioOutL}
	# pw-link ${audioInputR} ${btAudioOutR}
	
	# Connect the normal permanent sound card output to the new sink
	pw-link SimultaneousOutput:playback_FL bluez_output.${btMACAddress}.1:monitor_FL
	pw-link SimultaneousOutput:playback_FR bluez_output.${btMACAddress}.1:monitor_FR
	
	# Switch the default output to the new virtual sink
	wpctl set-default `wpctl status | grep "\. SimultaneousOutput" | egrep '^ │( )*[0-9]*' -o | cut -c6-55 | egrep -o '[0-9]*'`wpctl}

set -x
main