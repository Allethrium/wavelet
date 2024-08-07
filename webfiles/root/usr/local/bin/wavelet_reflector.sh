#!/bin/bash
# This file concatenates appropriate command line values and passes them to a systemd environment file
# Directly launches and terminates the reflector as a service.
# User permissions for this service are handled via Polkit, as the service is installed via Inition.

#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
read_etcd(){
	printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get /$(hostname)/${KEYNAME})
	echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for host $(hostname)"
}

read_etcd_global(){
	printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get "${KEYNAME}")
	echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for Global value"
}

write_etcd(){
	etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
	echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}

write_etcd_global(){
	etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
	echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
}

write_etcd_clientip(){
	etcdctl --endpoints=${ETCDENDPOINT} put /decoderip/$(hostname) "${KEYVALUE}"
	echo -e "$(hostname) set to ${KEYVALUE} for Global value"
}
read_etcd_clients_ip() {
	return_etcd_clients_ip=$(etcdctl --endpoints=${ETCDENDPOINT} get "/decoderip/" --prefix --print-value-only)
}
read_etcd_clients_ip_sed() {
	# We need this to manage the \n that etcd returns, 
	# the above is useful for generating the reference text file but this is better for immediate processing.
	processed_clients_ip=$(ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} get "/decoderip/" --prefix --print-value-only | sed ':a;N;$!ba;s/\n/ /g')
}

wavelet_reflector() {
# queries etcd for list of registered decoders
	read_etcd_clients_ip
	read_etcd_clients_ip_sed
	echo ${return_etcd_clients_ip} > /home/wavelet/reflector_clients_ip.txt
	# We can use a control port to add or remove clients from hd-rum as a subscription list.  This will be better than killing/restarting the process.
	# Our problem here is hd-rum-multi can't tell us what the "root create-port" is currently sending to, so we must do our own bookkeeping.
	# 0) echo 'stats on' | busybox nc -v 127.0.0.1 6161
	# 1) read out reflector_clients_ip to an array
	# 2) compare array values and determine what the discrepancy between the new and old data are
	# 3) if hostadded
	#	3a) foreach %i in addedhosts
	#	3a) echo 'root add-port ${i%}' | busybox nc -v 127.0.0.1 6161
	# 3b) else
	#	3b) foreach %i in removedhosts
	#	3b) echo 'root delete-port ${i%}' | busybox nc -v 127.0.0.1 6161
	# 3c) update the "old/current" etcd list of IP's so any further changes will compare against that
	# 4) echo 'root add-port ${i%}' | busybox nc -v 127.0.0.1 6161
	if [[ ! -z "${return_etcd_clients_ip}" ]]; then
		reflectorclients_file=/home/wavelet/reflector_clients_ip.txt
		# KEYNAME=uv_filter_cmd
		# read_etcd
		# uv_filterString=return_etcd
		echo -e "Systemd will execute hd-rum-transcode with commandline: \n\nhd-rum-transcode 2M 5004 ${return_etcd_clients_ip}\nafter a half-second delay"
		KEYNAME=REFLECTOR_ARGS
		# Reduce HD-RUM buffer to 2M
		# v. 1.9.4 will introduce hd-rum-av which can handle both audio and video in the same reflector, so we can drop the second systemd unit.
		# args="--tool hd-rum-av --control-port 6161 2M 5004 ${processed_clients_ip}"
		# as of pre 1.9.5 release, --control-port appears to break hd-rum-transcode, so we will drop it for now.
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
		# Hashed out comments would pin the reflector to a dedicated CPU core (core 1) - if we had appropriate perms
		#ExecStartPre=/bin/bash -c '/usr/bin/echo "1" > /sys/fs/cgroup/cpuset/wavelet/cpuset.cpus'
		#ExecStartPre=/bin/bash -c '/usr/bin/echo "0" > /sys/fs/cgroup/cpuset/wavelet/cpuset.mems'
		ExecStart=/usr/local/bin/UltraGrid.AppImage ${ugargs}
		#ExecStartPost=/bin/bash -c '/usr/bin/echo $MAINPID >> /sys/fs/cgroup/wavelet/tasks'
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
