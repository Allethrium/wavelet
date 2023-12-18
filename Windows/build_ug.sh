#!/bin/bash
# Builds UltraGrid systemD user unit files and configures other basic parameters during initial deployment
# This is launched in userspace.  The service is called each logon from Sway, checks to see if already built, then calls other scripts as required.
# it launches run_ug if hostname/config flag are set.
# 
# run_ug.sh initially started out doing some of this.

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
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*) 					echo -e "I am an Encoder \n" && echo -e "Provisioning systemD units as an encoder.."; event_encoder
	;;
	decX.wavelet.local)		echo -e "I am a Decoder, but my hostname is generic.  Randomizing my hostname, and rebooting"; systemctl start decoderhostname.service 
	;;
	dec*)					echo -e "I am a Decoder \n" && echo -e "Provisioning systemD units as a decoder.."; event_decoder
	;;
	livestream*)			echo -e "I am a Livestreamer \n" && echo -e "Provisioning systemD units as a livestreamer.."; event_livestreamer
	;;
	gateway*)				echo -e "I am an input Gateway for another video streaming system \n"  && echo -e "Provisioning systemD units as a gateway.."; event_gateway
	;;
	svr*)					echo -e "I am a Server. Proceeding..."  && event_server
	;;
	*) 						echo -e "This device Hostname is not set approprately, exiting \n" && exit 0
	;;
	esac
}

# These codeblocks directly enable the appropriate service immediately.
# run_ug.sh will perform its own autodetection logic, this might seem redundant and probably is.
# It was written before the need for this script became apparent.
# OK and now it won't let us enable anything like it's supposed to?  have to do this manually in Ignition via hardlinks?????
# to run systemd as another user (IE from root) do systemctl --user -M wavelet@  service.service

event_gateway(){
	echo -e "Not yet implemented.. \n"; exit 0
	systemctl --user daemon-reload
	systemctl --user enable wavelet_ndi_gateway.service
	etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/wavelet_build_completed" -- "${KEYVALUE}"
	sleep 2
}


event_livestreamer(){
	# creates wavelet-livestream systemd unit.
	# Livestreamer box runs only when livestream flag is enabled - we "secure" this with hardware.
	echo -e "Generating Livestream SystemdD unit in /.config/systemd/user.."
	echo "
	[Unit]
	Description=etcd Livestream watcher 
	After=network-online.target
	Wants=network-online.target
	[Service]
	Environment=ETCDCTL_API=3
	Execstart=/usr/bin/etcdctl --endpoints=192.168.1.32:2379 watch uv_islivestreaming -w simple -- sh -c /usr/local/bin/wavelet_livestream.sh
	Restart=always
	[Install]
	WantedBy=default.target
	" > /home/wavelet/.config/systemd/user/wavelet-livestream.service
		echo -e "Calling run_ug.service.."; exit 0
	systemctl --user daemon-reload
	systemctl --user enable wavelet-livestream.service --now
	systemctl --user start run_ug.service
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/wavelet_build_completed" -- "${KEYVALUE}"
	ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/livestream_capable" -- 1
	sleep 1
}


event_decoder(){
	echo -e "Decoder routine started.  Attempting to connect to preprovisioned WiFi.."
	# Finding the correct BSSID is VERY fussy, hence we do so many redundant rescans.
	nmcli dev wifi rescan
	sleep 1
	nmcli dev wifi rescan
	sleep 1
	nmcli dev wifi rescan
	sleep 1
	nmcli dev wifi rescan
	sleep 1
	nmcli dev wifi connect Wavelet-1
	sleep 1
	# need to do this twice - WiFi network *should* have already been provisioned by decoderhostname.sh
	nmcli dev wifi connect Wavelet-1
	echo -e "Setting up systemd services to be a decoder, moving to run_ug"
	systemctl --user daemon-reload
	systemctl --user enable run_ug.service --now
	etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/wavelet_build_completed" -- "${KEYVALUE}"
	sleep 2
}


event_encoder(){
	echo -e "reloading systemctl user daemon, moving to run_ug"
	systemctl --user daemon-reload
	systemctl --user enable run_ug.service --now
	etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/wavelet_build_completed" -- "${KEYVALUE}"
	sleep 2
}


event_server(){
# We're setting up a local http server so that subordinate devices don't have to copy and re-download everything.
# Ultimately if we're feeling clever we might want to setup an RPM caching mirror here to service clients for system packages
# This will need securing with HTTPS certificates ideally.
	systemctl --user start container-etcd-member.service
	sleep 10
	
	if service_exists container-etcd-member; then
		echo -e "Etcd service present, checking for bootstrap key"
			KEYNAME=SERVER_BOOTSTRAP_COMPLETED
			result=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
				if [[ "${result}" = 1 ]]; then
					echo -e "Server bootstrap is already completed, starting services and terminating process.."
					systemctl --user start watch_reflectorreload.service
					systemctl --user start wavelet_init.service
					# N.B - the encoder reset flag script is supposed to run only on an active encoder
					# If the server is also an encoder, run_ug.service must be enabled manually
				else			
					echo -e "Server bootstrap key is not present, executing bootstrap process."
					server_bootstrap
				fi
	else
		echo -e "Etcd service is not present, cannot check for bootstrap key and assuming that bootstrap has not been run. E xecuting bootstrap process.."
		server_bootstrap
	fi
}

server_bootstrap(){
	bootstrap_http(){
    	# check for bootstrap_completed, verify services running
    	KEYNAME=SERVER_HTTP_BOOTSTRAP_COMPLETED
		echo -e "Generating HTTPD server and copying/compressing wavelet files to server directory.."
		cd /home/wavelet/http
		cp /usr/local/bin/{overlay_rpm.sh,rpmfusion_repo.sh} /home/wavelet/http/
		tar -czf wavelet-files.tar.gz /etc/dnsmasq.conf /etc/skel/.bash_profile /etc/skel/.bashrc /etc/containers/registries.conf.d/10-wavelet.conf /home/wavelet/{.bash_profile,.bashrc,seal.mp4} /home/wavelet/.config/sway/config /home/wavelet/.config/waybar/{config,style.css,time.sh} /usr/local/bin/{build_dnsmasq.sh,build_httpd.sh,build_ug.sh,configure_ethernet.sh,decoderhostname.sh,detectv4l.sh,monitor_encoderflag.sh,promote_to_server.sh,removedevice.sh,run_ug.sh,start_appimage.sh,start_reflector.sh,udev_call.sh,wavelet_client_poll.sh,wavelet_controller.sh,wavelet_reflector.sh,wavelet_livestream.sh}
		# http server for PXE, archives, RPM repo etc.
		cp /usr/local/bin/UltraGrid.AppImage /home/wavelet/http
		/usr/local/bin/build_httpd.sh	
	}
	bootstrap_nginx_php(){
		# http PHP server for control interface	
		KEYNAME=SERVER_HTTP-PHP_BOOTSTRAP_COMPLETED
		/usr/local/bin/build_nginx_php.sh
		sleep 10
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
    sleep 3
    if bootstrap_http; then
    	if bootstrap_nginx_php; then
    		KEYNAME=SERVER_BOOTSTRAP_COMPLETED
			KEYVALUE=1
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
			systemctl --user enable wavelet_controller.service
			systemctl --user enable watch_reflectorreload.service
			systemctl --user enable wavelet_reflector.service
			# unlink build_ug service now we're done.
			echo -e "A Server/Encoder combined box must be manually enabled by the user. with the following command: \n\n systemctl --user enable run_ug.service \n\n"
			sleep 2
			echo -e "Server configuration is now complete, rebooting system one minute.."
			sleep 60
			systemctl reboot -i
		else
			echo "Controller bootstrap failed, ending.."
			exit 1
		fi
	else
		echo "HTTP server bootstrap failed, ending.."
		exit 1
	fi
}

service_exists() {
    local n=$1
    if [[ $(systemctl list-units --user -t service --full --no-legend "$n.service" | sed 's/^\s*//g' | cut -f1 -d' ') == $n.service ]]; then
        return 0
    else
        return 1
    fi
}


# Execution order
set -x
exec >/home/wavelet/build_ug.log 2>&1
detect_self