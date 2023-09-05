#!/bin/bash
# Livestream script
# Launched from a systemd watcher service configured from run_ug.sh
# basically a decoder w/ multiple video outs.
# One of these should be an HDMI capture card to the windows machine that ties into another automation system
# The LiveStream is designed as a dedicated device, not a decoder with a cloned stream
# It works this way because there are concerns of user notification when
# the system is streaming to any external source

#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
ETCDCTL_API=3
read_etcd(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get $(hostname)/${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_prefix(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix $(hostname)/${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_global(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for Global value"
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


event_decoder(){
# Copy of the event_decoder block from run_ug.sh
	KEYVALUE=$(ip a | grep 192.168.1 | awk '/inet / {gsub(/\/.*/,"",$2); print $2}')
	write_etcd_clientip
	# Run ultragrid 
	KEYNAME=UG_ARGS
	ug_args="--tool uv -d vulkan_sdl2 --param use-hw-accel"
	KEYVALUE="${ug_args}"
	write_etcd
	rm -rf /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
	echo "
	[Unit]
	Description=UltraGrid AppImage executable
	After=network-online.target
	Wants=network-online.target
	[Service]
	ExecStart=/usr/local/bin/UltraGrid.AppImage ${ug_args}
	ExecStopPost=/usr/local/bin/exit_handler.sh
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
	systemctl --user daemon-reload
	systemctl --user start UltraGrid.AppImage.service
	echo -e "Decoder systemd units instructed to start..\n"
	sleep 5
	return=$(systemctl --user is-active --quiet UltraGrid.AppImage.service)
	if [[ ${return} -eq !0 ]]; then
		echo "SystemD unit failed with Vulkan_sdl2 driver for hwaccel, trying with GL driver.."
		KEYNAME=UG_ARGS
		ug_args="--tool uv -d gl --param use-hw-accel"
		KEYVALUE="${ug_args}"
		write_etcd
		rm -rf /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
		echo "
		[Unit]
		Description=UltraGrid AppImage executable
		After=network-online.target
		Wants=network-online.target
		[Service]
		ExecStart=/usr/local/bin/UltraGrid.AppImage ${ug_args}
		ExecStopPost=/usr/local/bin/exit_handler.sh
		Restart=always
		[Install]
		WantedBy=default.target" > /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
		systemctl --user daemon-reload
		systemctl --user start UltraGrid.AppImage.service
		echo -e "Decoder systemd units instructed to start..\n"
		return=$(systemctl --user is-active --quiet UltraGrid.AppImage.service)
		if [[ ${return} -eq !0 ]]; then
			echo "Decoder failed to start, there may be something wrong with the system."
		else
			:
		fi
	else
		:
	fi
}


event_livestream(){
	KEYNAME=uv_islivestreaming
	read_etcd
	if [[ uv_islivestreaming -eq 1 ]]; then
		echo "Livestreaming is set to enabled, stopping decoder"
		systemctl --user stop UltraGrid.AppImage.service
	else
		echo "Livestreaming is not currently enabled, Starting Decoder.."
		event_decoder
	fi
}

# Main
set -x
exec >/home/wavelet/livestream.log 2>&1
event_livestream
