#!/bin/bash
# This file concatenates appropriate command line values and passes them to a systemd environment file
# Directly launches and terminates the reflector as a service.
# User permissions for this service are handled via Polkit, as the service is installed via Ignition.

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

wavelet_reflector() {
# queries etcd for list of registered decoders
	# Write the reflector IP address to an etcd key so we can find it from other hosts.
	KEYNAME="REFLECTOR_IP"; KEYVALUE=$(hostname -I | cut -d " " -f 1); write_etcd_global
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
		# this removes duplicate IP's from the subscription
		deDupReturnClientsIP=$(echo "${return_etcd_clients_ip}" | tr ' ' '\n' | nl | sort -u -k2 | sort -n | cut -f2- | tr '\n' ' ')
		deDupProcessedIP=$(echo "${processed_clients_ip}" | tr ' ' '\n' | nl | sort -u -k2 | sort -n | cut -f2-)
		echo -e "Systemd will execute hd-rum-transcode with commandline:\nhd-rum-transcode 2M 5004 ${return_etcd_clients_ip}"
		KEYNAME=REFLECTOR_ARGS
		# Reduce HD-RUM buffer to 2M
		# v. 1.9.4 will introduce hd-rum-av which can handle both audio and video in the same reflector, so we can drop the second systemd unit.
		# args="--tool hd-rum-av --control-port 6161 2M 5004 ${processed_clients_ip}"
		# as of pre 1.9.5 release, --control-port appears to break hd-rum-transcode, so we will drop it for now.
		# Set reflector args
		ugargs="--tool hd-rum-transcode 2M 5004 ${deDupReturnClientsIP}"
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
		KEYNAME=reload_reflector; KEYVALUE=0; write_etcd_global
		# Audio reflector, IP settings identical to video reflector so we don't need to do all that again
		KEYNAME=AUDIO_REFLECTOR_ARGS; ugargs="--tool hd-rum-transcode 2M 5006 ${deDupReturnClientsIP}"; KEYVALUE="${ugargs}"; write_etcd_global
		echo -e "[Unit]
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

		# setup Reflector cleanup service
		# This timer and systemd unit call a script which will attempt to ping for dead hosts every five minutes, and trim dead IP's.
		echo -e "[Unit]
		Description=Wavelet Reflector Janitor Service
		After=network-online.target
		Wants=network-online.target
		[Service]
		Type=onshot
		ExecStart=/usr/local/bin/wavelet_host_janitor.sh
		[Install]
		WantedBy=timers.target
		" > /home/wavelet/.config/systemd/user/Wavelet_reflector_janitor.service
		echo -e "[Unit]
		Description=Wavelet Reflector Janitor Service
		After=network-online.target
		Wants=network-online.target
		[Timer]
		OnBootSec=500s
		OnUnitActiveSec=500s
		[Install]
		WantedBy=default.target
		" > /home/wavelet/.config/systemd/user/Wavelet_reflector_janitor.timer
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