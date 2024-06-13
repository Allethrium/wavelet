#!/bin/bash
# This file concatenates appropriate command line values and passes them to a systemd environment file
# Directly launches and terminates the reflector as a service.
# User permissions for this service are handled via Polkit, as the service is installed via Inition.

#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
read_etcd(){
	printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get $(hostname)/${KEYNAME})
	echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for host $(hostname)"
}

read_etcd_global(){
	printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get "${KEYNAME}")
	echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for Global value"
}

write_etcd(){
	etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
	echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}

write_etcd_global(){
	etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
	echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
}

write_etcd_clientip(){
	etcdctl --endpoints=${ETCDENDPOINT} put decoderip/$(hostname) "${KEYVALUE}"
	echo -e "$(hostname) set to ${KEYVALUE} for Global value"
}
read_etcd_clients_ip() {
	return_etcd_clients_ip=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix decoderip/ --print-value-only)
}
read_etcd_clients_ip_sed() {
	# We need this to manage the \n that etcd returns, 
	# the above is useful for generating the reference text file but this is better for immediate processing.
	processed_clients_ip=$(ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} get --prefix decoderip --print-value-only | sed ':a;N;$!ba;s/\n/ /g')
}

wavelet_reflector() {
# queries etcd for list of registered decoders
# cleans data, runs hd-rum-transcode with appropriate settings for audio and video streams
# reset sets reload_reflector flag to 0
# HD-RUM-TRANSCODE supports capture filters directly, so we'd like to use that instead of bothering the encoder..
# systemd is a user service that is configured in the build_ug.sh script
	read_etcd_clients_ip

	# we need some validation here to make sure bad addresses don't sneak their way in
	# forEach IP in list do
	#echo -e "\nIP Address is not null, testing for validity..\n"
	#valid_ipv4() {
		#local ip=$1 regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
			#if [[ $ip =~ $regex ]]; then
				#echo -e "\nIP Address is valid, continuing..\n"
				#return 0
			#else
				#echo "\nIP Address is not valid, discarding\n"
				#event_decoder
			#fi
		#}
		#valid_ipv4 "${IPVALUE}"
		#fi

	read_etcd_clients_ip_sed
	echo ${return_etcd_clients_ip} > /home/wavelet/reflector_clients_ip.txt
	if [[ ! -z "${return_etcd_clients_ip}" ]]; then
		reflectorclients_file=/home/wavelet/reflector_clients_ip.txt
		# KEYNAME=uv_filter_cmd
		# read_etcd
		# uv_filterString=return_etcd
		echo -e "Systemd will execute hd-rum-transcode with commandline: \n\nhd-rum-transcode 2M 5004 ${return_etcd_clients_ip}\nafter a half-second delay"
		KEYNAME=REFLECTOR_ARGS
		# Reduce HD-RUM buffer to 2M
		ugargs="--tool hd-rum-transcode 2M 5004 ${processed_clients_ip}"
		KEYVALUE="${ugargs}"
		echo -e "Generating initial reflector clients list.."
		echo "${return_etcd_clients_ip}" > /home/wavelet/reflector_clients_ip.txt
		write_etcd_global
		sleep 0.5
		echo "
		[Unit]
		Description=UltraGrid AppImage Reflector
		After=network-online.target
		Wants=network-online.target
		[Service]
		ExecStart=/usr/local/bin/UltraGrid.AppImage ${ugargs}
		Restart=always
		[Install]
		WantedBy=default.target" > /home/wavelet/.config/systemd/user/UltraGrid.Reflector.service
		systemctl --user daemon-reload
		systemctl --user restart UltraGrid.Reflector.service
		echo -e "Reload_reflector flag is being set to 0.."
		KEYNAME=reload_reflector
		KEYVALUE=0
		write_etcd_global
		# Audio reflector, IP settings identical to video reflector so we don't need to do all that again
		KEYNAME=AUDIO_REFLECTOR_ARGS
		ugargs="--tool hd-rum-transcode 2M 5006 ${processed_clients_ip}"
		KEYVALUE="${ugargs}"
		write_etcd_global
		echo "
		[Unit]
		Description=UltraGrid AppImage Audio Reflector
		After=network-online.target
		Wants=network-online.target
		[Service]
		ExecStart=/usr/local/bin/UltraGrid.AppImage ${ugargs}
		[Install]
		WantedBy=default.target" > /home/wavelet/.config/systemd/user/UltraGrid.Audio.Reflector.service
		systemctl --user daemon-reload
		systemctl --user restart UltraGrid.Audio.Reflector.service
		echo -e "Reload_reflector flag is being set to 0.."

	else
		echo -e "It appears there are no populated client IP's for the reflector, sleeping for two minutes and exiting.  The reflector reload watcher will re-launch this script at that time."
		sleep 120
		KEYNAME=reload_reflector
		KEYVALUE="1"
		write_etcd_global
		exit 0
	fi
}

#set -x
exec >/home/wavelet/reflector.log 2>&1
wavelet_reflector
