#!/bin/bash
# Builds UltraGrid systemD user unit files and configures other basic parameters during initial deployment
# This is launched in userspace.  
# The service is called each logon from Sway, checks to see if already built, then calls other scripts as required.
# it launches run_ug if hostname/config flag are set.


ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
KEYVALUE=TRUE

detect_ug_version(){
	APPIMAGE=/usr/local/bin/UltraGrid.AppImage
	if test -f "$APPIMAGE"; then
		echo "UltraGrid AppImage detected, checking version.."
		VERSION=$(/usr/local/bin/UltraGrid.AppImage --tool uv -v | awk '{print $2}' | head -n1 | sed 's|[+,]||g')
		printf -v versions '%s\n%s' "$VERSION" "$EXPECTEDVERSION"
		if [[ $versions = "$(sort -V <<< "versions")" ]]; then
		echo "UltraGrid AppImage version too old, removing and downloading new version.."
		rm -rf /usr/local/bin/UltraGrid.AppImage
		#curl -O https://github.com/CESNET/UltraGrid/releases/download/continuous/UltraGrid.AppImage
		wget https://github.com/CESNET/UltraGrid/releases/download/continuous/UltraGrid-continuous-x86_64.AppImage -O /usr/local/bin/UltraGrid.AppImage
		chmod +x $APPIMAGE
		else
		echo "UltraGrid AppImage version OK, continuing.."
		fi
	else
		echo "UltraGrid AppImage not detected, downloading.."
		wget https://github.com/CESNET/UltraGrid/releases/download/continuous/UltraGrid-continuous-x86_64.AppImage -O /usr/local/bin/UltraGrid.AppImage
		chmod +x /usr/local/bin/UltraGrid.AppImage
	fi
}

detect_self(){
	systemctl --user daemon-reload
	UG_HOSTNAME=$(hostname)
	# Check to see if hostname has changed since last reboot
	if [[ -f /var/tmp/oldhostname.txt ]]; then
		check_hostname
	fi
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*) 					echo -e "I am an Encoder \n" && echo -e "Provisioning systemD units as an encoder.."			;	event_encoder
	;;
	decX.wavelet.local)		echo -e "I am a Decoder, but my hostname is generic.  Randomizing my hostname and rebooting"	;	systemctl start decoderhostname.service 
	;;
	dec*)					echo -e "I am a Decoder \n" && echo -e "Provisioning systemD units as a decoder.."				;	event_decoder
	;;
	livestream*)			echo -e "I am a Livestreamer \n" && echo -e "Provisioning systemD units as a livestreamer.."	;	event_livestreamer
	;;
	gateway*)				echo -e "I am an input Gateway for another video streaming system \n" 							;	event_gateway
	;;
	svr*)					echo -e "I am a Server. Proceeding..."															;	event_server
	;;
	*) 						echo -e "This device Hostname is not set approprately, exiting \n"								;	exit 0
	;;
	esac
}

# These codeblocks directly enable the appropriate service immediately.
# run_ug.sh will perform its own autodetection logic, this might seem redundant and probably is.
# It was written before the need for this script became apparent.
# to run systemd as another user (IE from root) do systemctl --user -M wavelet@  service.service

event_gateway(){
	echo -e "Not yet implemented.. \n"; exit 0
	systemctl --user daemon-reload
	systemctl --user enable wavelet_ndi_gateway.service
	etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/wavelet_build_completed" -- "${KEYVALUE}"
	event_generateHash gateway
	sleep 1
}


event_livestreamer(){
	# creates wavelet_livestream systemd unit.
	# Livestreamer box runs only when livestream flag is enabled - we "secure" this with hardware.
	echo -e "Generating Livestream SystemdD unit in /.config/systemd/user.."
	echo "
	[Unit]
	Description=etcd Livestream watcher 
	After=network-online.target
	Wants=network-online.target
	[Service]
	Environment=ETCDCTL_API=3
	ExecStart=/usr/bin/etcdctl --endpoints=192.168.1.32:2379 watch uv_islivestreaming -w simple -- sh -c /usr/local/bin/wavelet_livestream.sh
	Restart=always
	[Install]
	WantedBy=default.target
	" > /home/wavelet/.config/systemd/user/wavelet_livestream.service
		echo -e "Calling run_ug.service.."; exit 0
	systemctl --user daemon-reload
	event_decoder_restart
	event_reboot
	systemctl --user enable wavelet_livestream.service --now
	systemctl --user start run_ug.service
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/wavelet_build_completed" -- "${KEYVALUE}"
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/livestream_capable" -- 1
	event_generateHash livestream
	sleep 1
}


event_decoder(){
	echo -e "Decoder routine started.  Attempting to connect to preprovisioned WiFi.."
	# Finding the correct BSSID is VERY fussy and dependent on AP settings such as beacon interval, hence we do so many redundant rescans.
	nmcli dev wifi rescan
	sleep 1
	nmcli dev wifi rescan
	sleep 1
	nmcli dev wifi rescan
	nmcli dev wifi connect Wavelet-1
	# need to do this twice - WiFi network *should* have already been provisioned by decoderhostname.sh
	nmcli dev wifi connect Wavelet-1
	echo -e "Setting up systemd services to be a decoder, moving to run_ug"
	event_decoder_reset
	event_reveal
	event_reboot
	event_reset
	event_blankhost
	event_promote
	event_generateHash dec
	etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/wavelet_build_completed" -- "${KEYVALUE}"
	sleep 1
	/usr/local/bin/run_ug.sh
}

event_encoder(){
	echo -e "reloading systemctl user daemon, moving to run_ug"
	systemctl --user daemon-reload
	systemctl --user enable run_ug.service --now
	# Generate Systemd notifier services for encoders
	event_encoder_reboot
	event_reboot
	event_reset
	event_device_redetect
	event_promote
	etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/wavelet_build_completed" -- "${KEYVALUE}"
	hostname=$(hostname)
	# We need to add this switch here to ensure if we're a server we don't populate ourselves to the encoders DOM in the webUI..
	if [[ ${hostname} == *"enc"* ]]; then
		event_generateHash enc
	else
		# generateHash was already called from the server event function.
		:
	fi
	systemctl --user stop watch_encoderflag.service
	echo -e '[Unit]
	Description=Watches etcd for encoder restart
	After=network-online.target etcd-member.service
	Wants=network-online.target
	[Service]
	Environment=ETCDCTL_API=3
	ExecStart=etcdctl --endpoints=192.168.1.32:2379 watch /"%H"/encoder_restart -w simple -- sh -c /usr/local/bin/monitor_encoderflag.sh
	Restart=on-failure
	RestartSec=1
	[Install]
	WantedBy=default.target' > /home/wavelet/.config/systemd/user/watch_encoderflag.service
	systemctl --user daemon-reload
	systemctl --user enable watch_encoderflag.service --now
	sleep 1
}

event_server(){
	systemctl --user start container-etcd-member.service
	sleep 10	
	if service_exists container-etcd-member; then
		echo -e "Etcd service present, checking for bootstrap key\n"
			KEYNAME=SERVER_BOOTSTRAP_COMPLETED
			result=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
				if [[ "${result}" = 1 ]]; then
					echo -e "Server bootstrap is already completed, starting services and terminating process..\n"
					systemctl --user enable watch_reflectorreload.service --now
					systemctl --user start wavelet_init.service
					# N.B - the encoder reset flag script is supposed to run only on an active encoder
					# If the server is also an encoder, run_ug.service must be enabled manually
				else			
					echo -e "Server bootstrap key is not present, executing bootstrap process."
					server_bootstrap
				fi
	else
		echo -e "Etcd service is not present, cannot check for bootstrap key and assuming that bootstrap has not been run. Executing bootstrap process..\n"
		server_bootstrap
	fi
	event_generateHash svr
	# Server always also provisions as an encoder!
	event_encoder
	event_reboot
}

server_bootstrap(){
# Bootstraps the server processes including Apache HTTP server for repo and distribution files, and the web interface NGINX/PHP pod
	# Disabled, because we will call with the installer script
	until [ -f /home/wavelet/local_rpm_setup.complete ]
	do
		sleep 2
	done
	if test -f "/var/server_bootstrap_completed"; then
		echo -e "\n server bootstrap has already been completed, exiting..\n"
		exit 0
	fi
	bootstrap_http(){
		# check for bootstrap_completed, verify services running
		echo -e "Generating HTTPD server and copying/compressing wavelet files to server directory.."
		/usr/local/bin/build_httpd.sh	
		sleep 2
	}

	bootstrap_nginx_php(){
		# http PHP server for control interface	
		/usr/local/bin/build_nginx_php.sh
		sleep 2
	}

	bootstrap_nodejs(){
		/usr/local/bin/build_nodejs.sh
		sleep 2
	}

	bootstrap_dnsmasq_watcher_service(){
		echo -e "[Unit]
		Description=Dnsmasq inotify service
		After=network.target

		[Service]
		ExecStart=/usr/local/bin/wavelet_dnsmasq_inotify_service.sh
		RestartSec=10s
		Type=simple
		StandardOutput=inherit
		StandardError=inherit

		[Install]
		WantedBy=default.target" > wavelet_dnsmasq_inotify.service
		systemctl --user daemon-reload
		systemctl --user enable wavelet_dnsmasq_netsense_inotify.service --now
		echo -e "\ninotify service enabled for wavelet network sense via dnsmasq..\n"
	}

	echo -e "Pulling etcd and generating systemd services.."
	cd /home/wavelet/.config/systemd/user/
	/bin/podman pull quay.io/coreos/etcd:v3.5.9
	/bin/podman create --name etcd-member --net=host \
   quay.io/coreos/etcd:v3.5.9 /usr/local/bin/etcd              \
   --data-dir /etcd-data --name wavelet_svr                  \
   --initial-advertise-peer-urls http://192.168.1.32:2380 \
   --listen-peer-urls http://192.168.1.32:2380           \
   --advertise-client-urls http://192.168.1.32:2379       \
   --listen-client-urls http://192.168.1.32:2379,http://127.0.0.1:2379        \
	   --initial-cluster wavelet_svr=http://192.168.1.32:2380 \
	   --initial-cluster-state new
	/bin/podman generate systemd --files --name etcd-member --restart-policy=always -t 2
	systemctl --user daemon-reload
	echo -e "Attempting to start etcd container.."
	systemctl --user enable container-etcd-member.service --now
	sleep 2
	bootstrap_http
	bootstrap_nginx_php
	bootstrap_nodejs
	bootstrap_dnsmasq_watcher_service
	KEYNAME=SERVER_BOOTSTRAP_COMPLETED
	KEYVALUE=1
	touch /var/server_bootstrap_completed
	etcdctl --endpoints=${ETCDENDPOINT} put ${KEYNAME} -- ${KEYVALUE}
	echo -e "Reloading systemctl user daemon, and enabling the controller service immediately"
	systemctl --user daemon-reload
		if service_exists container-etcd-member; then
			etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/wavelet_build_completed" -- "${KEYVALUE}"
		else
			systemctl --user enable container-etcd-member.service --now
			etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/wavelet_build_completed" -- "${KEYVALUE}"
		fi
	echo -e "Enabling server notification services"
	systemctl --user enable wavelet_controller.service --now
	systemctl --user enable watch_reflectorreload.service --now
	systemctl --user enable wavelet_reflector.service --now
	# uncomment a firefox exec command into sway config, this will bring up the management console on the server in a new sway window, as a backup control surface.
	# - note we need to work on a firefox policy/autoconfig.
	sed -i '/exec firefox/s/^# *//' config $HOME/.config/sway/config
	#same for dnsmasq because it inexplicably stops working.
	sed -i '/exec systemctl restart dnsmasq.service/s/^# *//' config $HOME/.config/sway/config
	#
	sed -i '/exec \/usr\/local\/bin\/local_rpm.sh/s/^# *//' config $HOME/.config/sway/config
	# Next, we build the reflector prune function.  This is necessary for removing streams for old decoders and maintaining the long term health of the system
		# Get decoderIP list
		# Ping each decoder on list
		# If dead, ping more intensively for 30s
		# If still dead, remove from reflector subscription

	# Finally, add a service to prune dead FUSE mountpoints.  Every time the UltraGrid AppImage is restarted, it leaves stale mountpoints.  This timed task will help keep everything clean.
		# Get "alive mountpoints"
		# Prune anything !=alive
	#  Reboot the server
	echo -e "Server configuration is now complete, rebooting system fifteen seconds.."
	sleep 15
	systemctl reboot -i
}

service_exists() {
	local n=$1
	if [[ $(systemctl list-units --user -t service --full --no-legend "$n.service" | sed 's/^\s*//g' | cut -f1 -d' ') == $n.service ]]; then
		return 0
	else
		return 1
	fi
}

event_reboot(){
	# Everything should watch the system reboot flag for a hard reset
	echo -e "Generating Reboot SystemdD unit in /.config/systemd/user.."
	echo "[Unit]
	Description=etcd System reboot watcher 
	After=network-online.target
	Wants=network-online.target
	[Service]
	Environment=ETCDCTL_API=3
	ExecStart=/usr/bin/etcdctl --endpoints=192.168.1.32:2379 watch SYSTEM_REBOOT -w simple -- sh -c \"/usr/local/bin/wavelet_reboot.sh\"
	Restart=on-failure
	RestartSec=2
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/wavelet_reboot.service
	# and the same for the host reboot
	echo "[Unit]
	Description=Wavelet System Reboot Service
	After=network-online.target etcd-member.service
	Wants=network-online.target
	[Service]
	Type=simple
	ExecStart=etcdctl --endpoints=192.168.1.32:2379 watch /$(hostname)/DECODER_REBOOT -w simple -- sh -c \"/usr/local/bin/wavelet_reboot.sh\"
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/wavelet_monitor_decoder_reboot.service

	systemctl --user daemon-reload
	systemctl --user enable wavelet_reboot.service --now
	systemctl --user enable wavelet_monitor_decoder_reboot.service --now
}

event_reset(){
	# Everything should watch the system reboot flag for a task reset
	echo -e "Generating Reset SystemdD units in /.config/systemd/user.."
	echo -e "[Unit]
	Description=etcd System reset watcher 
	After=network-online.target
	Wants=network-online.target
	[Service]
	Environment=ETCDCTL_API=3
	ExecStart=/usr/bin/etcdctl --endpoints=192.168.1.32:2379 watch SYSTEM_RESET -w simple -- sh -c "/usr/local/bin/wavelet_reset.sh"
	Restart=always
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/wavelet_reset.service

	# and the same for the host reset
	echo -e "[Unit]
	Description=Wavelet Task Reset Service
	After=network-online.target etcd-member.service
	Wants=network-online.target
	[Service]
	Type=simple
	ExecStart=etcdctl --endpoints=192.168.1.32:2379 watch /"%H"/DECODER_RESET -w simple -- sh -c \"/usr/local/bin/wavelet_decoder_reset.sh\"
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/wavelet_monitor_decoder_reset.service

	systemctl --user daemon-reload
	systemctl --user enable wavelet_reset.service --now
	systemctl --user enable wavelet_monitor_decoder_reset.service --now
}

event_reveal(){
	# Tells specific host to display SMPTE bars on screen, useful for finding which is what and where
	echo -e "[Unit]
	Description=Wavelet Task Reveal Service
	After=network-online.target etcd-member.service
	Wants=network-online.target
	[Service]
	Type=simple
	ExecStart=etcdctl --endpoints=192.168.1.32:2379 watch /"%H"/DECODER_REVEAL -w simple -- sh -c \"/usr/local/bin/wavelet_decoder_reveal.sh\"
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/wavelet_monitor_decoder_reveal.service
	systemctl --user daemon-reload
	systemctl --user enable wavelet_monitor_decoder_reveal.service --now
}

event_blankhost(){
	# Tells specific host to display a black testcard on the screen, use this for privacy modes as necessary.
	echo -e "[Unit]
	Description=Wavelet Task Blank Service
	After=network-online.target etcd-member.service
	Wants=network-online.target
	[Service]
	Type=simple
	ExecStart=etcdctl --endpoints=192.168.1.32:2379 watch /"%H"/DECODER_BLANK -w simple -- sh -c \"/usr/local/bin/wavelet_decoder_blank.sh\"
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/wavelet_monitor_decoder_blank.service
	systemctl --user daemon-reload
	systemctl --user enable wavelet_monitor_decoder_blank.service --now
}

event_promote(){
	# This flag watches the hostname to instruct the machine to (pro/de)mote the (en/de)coder as appropriate.
	echo -e "Generating Promoter SystemdD unit in /.config/systemd/user.."
	echo -e "[Unit]
	Description=etcd Host Promotion watcher 
	After=network-online.target
	Wants=network-online.target
	[Service]
	Environment=ETCDCTL_API=3
	ExecStart=/usr/bin/etcdctl --endpoints=192.168.1.32:2379 watch /"%H"/PROMOTE -w simple -- sh -c \"/usr/local/bin/wavelet_promote.sh\"
	Restart=always
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/wavelet_promote.service

	systemctl --user daemon-reload
	systemctl --user enable wavelet_promote.service --now
}

event_encoder_reboot(){
	# Encoders have their own reboot flag should watch the system reboot flag for a hard reset
	echo -e "Generating Encoder Reboot SystemdD unit in /.config/systemd/user.."
	echo -e "[Unit]
	Description=etcd Encoder reboot watcher 
	After=network-online.target
	Wants=network-online.target
	[Service]
	Environment=ETCDCTL_API=3
	ExecStart=/usr/bin/etcdctl --endpoints=192.168.1.32:2379 watch /"%H"/SYSTEM_REBOOT -w simple -- sh -c \"/usr/local/bin/wavelet_reboot.sh\"
	Restart=always
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/wavelet_encoder_reboot.service

	systemctl --user daemon-reload
	systemctl --user enable wavelet_encoder_reboot.service --now
}

event_decoder_reset(){
	# Resets the decoder UltraGrid task, which is cheaper than a reboot..
	echo -e "Generating Reboot SystemdD unit in /.config/systemd/user.."
	echo -e "[Unit]
	Description=etcd Decoder retart watcher 
	After=network-online.target
	Wants=network-online.target
	[Service]
	Environment=ETCDCTL_API=3
	ExecStart=/usr/bin/etcdctl --endpoints=192.168.1.32:2379 watch /"%H"/DECODER_RESET -w simple -- sh -c \"/usr/local/bin/wavelet_decoder_reset.sh\"
	Restart=always
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/wavelet_decoder_reset.service

	systemctl --user daemon-reload
	systemctl --user enable wavelet_decoder_reset.service --now
}

event_audio_toggle(){
	# Toggles audio functionality on and off
	echo -e "Generating Reboot SystemdD unit in /.config/systemd/user.."
	echo -e "[Unit]
	Description=etcd Decoder retart watcher 
	After=network-online.target
	Wants=network-online.target
	[Service]
	Environment=ETCDCTL_API=3
	ExecStart=/usr/bin/etcdctl --endpoints=192.168.1.32:2379 watch /interface/audio/enabled -w simple -- sh -c \"/usr/local/bin/wavelet_audio_toggle.sh\"
	Restart=always
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/wavelet_audio_toggle.service

	systemctl --user daemon-reload
	systemctl --user enable wavelet_audio_toggle.service --now
}

event_audio_bluetooth_connect(){
	# Monitors the bluetooth MAC value and updates the system if there's a change
	echo -e "Generating Reboot SystemdD unit in /.config/systemd/user.."
	echo -e "[Unit]
	Description=etcd Decoder retart watcher 
	After=network-online.target
	Wants=network-online.target
	[Service]
	Environment=ETCDCTL_API=3
	ExecStart=/usr/bin/etcdctl --endpoints=192.168.1.32:2379 watch /audio_interface_bluetooth_mac -w simple -- sh -c \"/usr/local/bin/wavelet_set_bluetooth_connect.sh\"
	Restart=always
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/wavelet_bluetooth_audio.service

	systemctl --user daemon-reload
	systemctl --user enable wavelet_bluetooth_audio.service --now
}

event_generateHash(){
		# Can be modified from webUI, populates with hostname by default
		currentHostName=$(hostname)
		echo -e "device hostname is: $(hostname)"
		hostHash=$(cat /etc/machine-id | sha256sum | tr -d "[:space:]-")
		echo -e "generated device hash: ${hostHash} \n"
		# Check for pre-existing keys here
		hashExists=$(ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} get "/hostHash/${hostHash}" --print-value-only)
		if [[ -z "${hashExists}" || ${#hashExists} -le 40 ]] then
			echo -e "\nHash value was set to ${hashExists}, which is null or less than 40 chars. \n"
			# Populate what will initially be used as the label variable from the webUI
			case ${1} in
				enc*)			ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put /hostLabel/${currentHostName}/type -- enc
				;;
				dec*)			ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put /hostLabel/${currentHostName}/type -- dec
				;;
				livestream*)	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put /hostLabel/${currentHostName}/type -- lvstr
				;;
				gateway*)		ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put /hostLabel/${currentHostName}/type -- gtwy
				;;
				svr*)			ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put /hostLabel/${currentHostName}/type -- svr
				;;
				*)				echo -e "hostname invalid, exiting."	;	exit 0
				;;
			esac
		# And the reverse lookup for the device
		ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "/hostHash/${currentHostName}/Hash" -- "${hostHash}"
		ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "/hostHash/${hostHash}" -- "${currentHostName}"
		ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "/${currentHostName}/Hash" -- "${hostHash}"
		ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "/hostHash/${currentHostName}/label" -- "${currentHostName}"
		else
			echo -e "\nHash value exists as /hostHash/${hashExists}\n"
			echo -e "This means the device is already populated, or has not been removed cleanly. Checking to see if we've been relabeled.."
			KEYNAME="/${currentHostName}/RECENT_RELABEL"
			read_etcd_global
			if [[ "${printvalue}" == "1" ]]; then
				echo -e "This device was recently relabeled!  Clearing hash and running this function again..\n"
				KEYNAME="${currentHostName}/RECENT_RELABEL"
				KEYVALUE="0"
				write_etcd_global
				ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} del "/hostHash/${hostHash}"
				event_generateHash
			fi
		fi
}

event_device_redetect(){
	# Watches for a device redetection flag, then runs detectv4l.sh
	echo -e "Generating Reboot SystemdD unit in /.config/systemd/user.."
	echo -e "[Unit]
	Description=etcd Device redetection watcher
	After=network-online.target
	Wants=network-online.target
	[Service]
	Environment=ETCDCTL_API=3
	ExecStart=/usr/bin/etcdctl --endpoints=192.168.1.32:2379 watch DEVICE_REDETECT -w simple -- sh -c \"/usr/local/bin/wavelet_detectv4l.sh rd\"
	Restart=always
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/wavelet_device_redetect.service
	systemctl --user daemon-reload
	systemctl --user enable wavelet_device_redetect.service --now
}

event_host_relabel_watcher(){
	# Watches for a device relabel flag, then runs wavelet_device_relabel.sh
	echo -e "Generating Reboot SystemdD unit in /.config/systemd/user.."
	echo -e "[Unit]
	Description=etcd Device hostname change watcher
	After=network-online.target
	Wants=network-online.target
	[Service]
	Environment=ETCDCTL_API=3
	ExecStart=/usr/bin/etcdctl --endpoints=192.168.1.32:2379 watch /"%H"/RELABEL -w simple -- sh -c \"/usr/local/bin/wavelet_device_relabel.sh\"
	Restart=always
	[Install]
	WantedBy=default.target" > /home/wavelet/.config/systemd/user/wavelet_device_relabel.service
	systemctl --user daemon-reload
	systemctl --user enable wavelet_device_relabel.service --now
}

# Execution order

set -x
exec >/home/wavelet/build_ug.log 2>&1
detect_self