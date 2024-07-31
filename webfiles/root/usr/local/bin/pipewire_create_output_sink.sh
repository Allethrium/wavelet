#!/bin/bash
# Ref Arch Linux Wiki - https://wiki.archlinux.org/title/WirePlumber

#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
read_etcd(){
		ETCDCTL_API=3 printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get $(hostname)/${KEYNAME} --print-value-only)
		echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_prefix(){
		ETCDCTL_API=3 printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix $(hostname)/${KEYNAME} --print-value-only)
		echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_global(){
		ETCDCTL_API=3 printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
		echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for Global value"
}

write_etcd(){
		ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
		echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}

write_etcd_global(){
		ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
		echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
}

write_etcd_clientip(){
		# Variable changed to IPVALUE because the module was picking up incorrect variables and applying them to /decoderip !
		ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put decoderip/$(hostname) "${IPVALUE}"
		echo -e "decoderip/$(hostname) set to ${IPVALUE} for Global value"
}
read_etcd_clients_ip() {
		ETCDCTL_API=3 return_etcd_clients_ip=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix decoderip/ --print-value-only)
}


main(){
	# Create a new sink called Simultaneous Output
	pw-cli create-node adapter '{ factory.name=support.null-audio-sink node.name="SimultaneousOutput" \
								node.description="SimultaneousOutput" media.class=Audio/Sink object.linger=true \
								audio.position=[FL FR] }'
	
	# etcdctl find current video source
	KEYNAME="uv_hash_select"
	read_etcd_global
	currentVideoInputHash=${printvalue}
	KEYNAME="/short_hash/${currentVideoInputHash}"
	read_etcd_global
	currentVideoPath=${printvalue}

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