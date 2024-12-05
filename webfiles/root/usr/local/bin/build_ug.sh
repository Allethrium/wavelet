#!/bin/bash
# Builds UltraGrid systemD user unit files and configures other basic parameters during initial deployment
# This is launched in userspace.  
# The service is called each logon from Sway, checks to see if already built, then calls other scripts as required.
# it launches run_ug if hostname/config flag are set.

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
read_etcd_json_revision(){
	# Special case used in controller
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_json_revision" uv_hash_select | jq -r '.header.revision')
}
read_etcd_lastrevision(){
	# Special case used in controller
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_lastrevision")	
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
delete_etcd_key_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key_global" "${KEYNAME}"
}
generate_service(){
	# Can be called with more args with "generate_servier" ${keyToWatch} 0 0 "${serviceName}"
	/usr/local/bin/wavelet_etcd_interaction.sh "generate_service" "${serviceName}"
}


detect_ug_version(){
	# This is fairly redudant, as the provisioning process should not get this far without download UG during Ignition..
	APPIMAGE=/usr/local/bin/UltraGrid.AppImage
	if test -f "$APPIMAGE"; then
		echo "UltraGrid AppImage detected, checking version.."
		VERSION=$(/usr/local/bin/UltraGrid.AppImage --tool uv -v | awk '{print $2}' | head -n1 | sed 's|[+,]||g')
		printf -v versions '%s\n%s' "$VERSION" "$EXPECTEDVERSION"
		if [[ $versions = "$(sort -V <<< "versions")" ]]; then
		echo "UltraGrid AppImage version too old, removing and downloading new version.."
		rm -rf /usr/local/bin/UltraGrid.AppImage
		# This would rebase on the continuous build which might have broken features...
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
	event_generateHash gateway
	sleep 1
}

wifi_connect_retry(){
	# No.wifi tag should be set on the server
	if [[ -f /var/no.wifi ]]; then
		echo "Device configured to ignore wifi!"
		exit 0
	fi

	if nmcli device status | grep -a 'wifi.*connect'; then
		echo -e "WiFi device detected, proceeding.."
		# Look for active wifi
		if [[ $(nmcli con show --active | grep -q 'wifi') ]]; then
			echo -e "Active WiFi connection available! return 0"
			return 0
		else
			echo -e "Attempting to connect to WiFi.  If this device is NOT planned to be on WiFi, run the command as a privileged user:\n"
			echo -e "touch /var/no.wifi"
			while ! /usr/local/bin/connectwifi.sh; do
				sleep 2
			done
		fi
	else
		echo -e "This machine has no wifi connectivity, exiting..\n"
		exit 0
	fi
}

event_decoder(){
	echo -e "Decoder routine started."
	echo -e "Setting up systemd services to be a decoder, moving to run_ug"
	wifi_connect_retry
	event_reveal
	event_reboot
	event_reset
	event_blankhost
	event_host_relabel_watcher
	event_promote
	event_generateHash dec
	KEYNAME="wavelet_build_completed"; KEYVALUE="1"; write_etcd
	sleep 1
	/usr/local/bin/run_ug.sh
}

event_encoder(){
	echo -e "reloading systemctl user daemon, moving to run_ug"
	if [[ -f /var/no.wifi ]]; then
		echo "wifi disabled on this host.."
		:
	else		
		wifi_connect_retry
	fi
	systemctl --user daemon-reload
	/usr/local/bin/run_ug.sh
	# Generate Systemd notifier services for encoders
	event_encoder_reboot
	event_reboot
	event_reset
	event_device_redetect
	event_host_relabel_watcher
	event_generate_watch_encoderflag
	event_promote
}

event_generate_watch_encoderflag(){
	KEYNAME="wavelet_build_completed"; KEYVALUE="1"; write_etcd
	hostname=$(hostname)
	# We need to add this switch here to ensure if we're a server we don't populate ourselves to the encoders DOM in the webUI..
	if [[ ${hostname} == *"enc"* ]]; then
		event_generateHash enc
	else
		# generateHash was already called from the server event function.
		:
	fi
	systemctl --user stop watch_encoderflag.service
	# Can be called directly, remember to escape quotes if we want to preserve them as per bash standards.
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service /\"%H\"/encoder_restart 0 0 "watch_encoderflag"
	systemctl --user daemon-reload
	systemctl --user enable watch_encoderflag.service --now
}

event_server(){
	if [[ -f /var/pxe.complete ]]; then
		echo -e "\nPXE service up and running, continuing..\n"
	else
		echo -e "\nPXE service has not completed setup, exiting until the next reboot..\n"
		exit 1
	fi

	if [[ -f /var/home/wavelet/server_bootstrap_completed ]]; then
		echo -e "Server bootstrap completed, continuing"
		systemctl --user enable run_ug.service --now
		systemctl --user enable wavelet_init.service --now
	else
		echo -e "Server bootstrap not completed\n"
		server_bootstrap
	fi
	event_generateHash svr
	# Server always also provisions as an encoder!
	event_encoder
	event_generate_reflector
	event_generate_controllerWatch
	event_generate_reflectorreload
	event_reboot
}

server_bootstrap(){
# Bootstraps the server processes including Apache HTTP server for distribution files, and the web interface NGINX/PHP pod
	sleep 5
	# Build_httpd and build http-php both seem to have issues pulling the container images from quadlets, so we will try to head that issue off by pulling the images here.
	podman pull docker://docker.io/library/nginx:alpine
	podman pull docker://docker.io/library/php:fpm
	podman pull docker://docker.io/library/httpd
	until [[ -f /var/ug_depends.complete ]]; do
		sleep 1
	done

	if [[ -f "/var/home/wavelet/server_bootstrap_completed" ]]; then
		echo -e "\n server bootstrap has already been completed, exiting..\n"
		exit 0
	fi

	bootstrap_http(){
		# check for bootstrap_completed, verify services running
		echo -e "Generating HTTPD server and copying/compressing wavelet files to server directory.."
		/usr/local/bin/build_httpd.sh	
		# Remove executable bit from all webserver files and make sure to reset +x for the directory only
		#find /var/home/wavelet/http/ -type f -print0 | xargs -0 chmod 644
		chmod +x /var/home/wavelet/http
	}

	bootstrap_nginx_php(){
		# http PHP server for control interface	
		/usr/local/bin/build_nginx_php.sh
		# Remove executable bit from all webserver files and make sure to reset +x for the directory only
		#find /var/home/wavelet/http-php/ -type f -print0 | xargs -0 chmod 644
		chmod +x /var/home/wavelet/http
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
WantedBy=default.target" > /var/home/wavelet/.config/systemd/user/wavelet_dnsmasq_inotify.service
		systemctl --user daemon-reload
		systemctl --user enable wavelet_dnsmasq_inotify.service --now
		echo -e "\ninotify service enabled for wavelet network sense via dnsmasq..\n"
	}

	bootstrap_livestream(){
		# This might not even be worth the hassle given we just installed ffmpeg and all the support packages on the base OS..
		podman build -t localhost/livestreamer -f /home/wavelet/containerfiles/Containerfile.livestreamer
		podman tag localhost/livestreamer localhost:5000/livestreamer:latest
		podman push localhost:5000/coreos_overlay:latest 192.168.1.32:5000/livestreamer--tls-verify=false
		echo -e "[Unit]
Description=Livestreamer

[Container]
Image=192.168.1.32:5000/livestreamer
ContainerName=Wavelet Livestreamer
AutoUpdate=registry
ShmSize=256m
Notify=true
PodmanArgs=--group-add keep-groups --network=host

[Service]
Restart=always
TimeoutStartSec=600

[Install]
WantedBy=default.target" > /var/home/wavelet/.config/containers/systemd/livestream.container
	}
	bootstrap_http
	bootstrap_nginx_php
	#bootstrap_nodejs		#	WAY in the future for UI stuff.
	#bootstrap_livestream 	#	Probably not necessary to spin up a whole container for this..
	bootstrap_dnsmasq_watcher_service
	touch /var/home/wavelet/server_bootstrap_completed
	echo -e "Reloading systemctl user daemon, and enabling the controller service immediately"
	systemctl --user daemon-reload
	echo -e "Enabling server notification services"
	event_generate_controller
	event_generate_reflectorreload
	event_generate_watch_encoderflag
	event_generate_run_ug
	systemctl --user enable wavelet_controller.service --now
	systemctl --user enable watch_reflectorreload.service --now
	systemctl --user enable wavelet_reflector.service --now
	# uncomment a firefox exec command into sway config, this will bring up the management console on the server in a new sway window, as a backup control surface.
	# - note we need to work on a firefox policy/autoconfig.
	sed -i '/exec firefox/s/^# *//' /var/home/wavelet/.config/sway/config

	# Next, we build the reflector prune function.  This is necessary for removing streams for old decoders and maintaining the long term health of the system
		# Get decoderIP list
		# Ping each decoder on list
		# If dead, ping more intensively for 30s
		# If still dead, remove from reflector subscription

	# Finally, add a service to prune dead FUSE mountpoints.  Every time the UltraGrid AppImage is restarted, it leaves stale mountpoints.  This timed task will help keep everything clean.
		# Get "alive mountpoints"
		# Prune anything !=alive
	echo -e "Server configuration is now complete, rebooting system.."
	systemctl reboot
}

event_reboot(){
	# Everything should watch the system reboot flag for a hard reset
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service SYSTEM_REBOOT 0 0 "wavelet_reboot"
	# and the same for the host reboot
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service /\"%H\"/DECODER_REBOOT 0 0 "wavelet_decoder_reboot"
	systemctl --user daemon-reload
	systemctl --user enable wavelet_reboot.service --now
	systemctl --user enable wavelet_decoder_reboot.service --now
}

event_reset(){
	# Everything should watch the system reboot flag for a task reset
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service SYSTEM_RESET 0 0 "wavelet_reset"
	# and the same for the host reset
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service /\"%H\"/DECODER_RESET 0 0 "wavelet_decoder_reset"
	systemctl --user daemon-reload
	systemctl --user enable wavelet_reset.service --now
	systemctl --user enable wavelet_watch_decoder_reset.service --now
}

event_reveal(){
	# Tells specific host to display SMPTE bars on screen, useful for finding which is what and where
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service /\"%H\"/DECODER_REVEAL 0 0 "wavelet_decoder_reveal"
	systemctl --user enable wavelet_watch_decoder_reveal.service --now
}

event_blankhost(){
	# Tells specific host to display a black testcard on the screen, use this for privacy modes as necessary.
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service /\"%H\"/DECODER_BLANK 0 0 "wavelet_decoder_blank"
	systemctl --user daemon-reload
	systemctl --user enable wavelet_watch_decoder_blank.service --now
}

event_promote(){
	# This flag watches the hostname to instruct the machine to (pro/de)mote the (en/de)coder as appropriate.
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service /\"%H\"/PROMOTE 0 0 "wavelet_promote"
	systemctl --user enable wavelet_promote.service --now
}

event_encoder_reboot(){
	# We want to regenerate this every time because the hostname may change
		# Generate userspace run_ug service
		# Encoders have their own reboot flag should watch the system reboot flag for a hard reset
		/usr/local/bin/wavelet_etcd_interaction.sh generate_service /\"%H\"/SYSTEM_REBOOT 0 0 "wavelet_reboot"
		systemctl --user daemon-reload
		systemctl --user enable wavelet_encoder_reboot.service --now
}

event_audio_toggle(){
	if [[ -f ~/.config/systemd/user/wavelet_audio_toggle.service ]]; then
		echo -e "Unit file already generated, moving on\n"
		:
	else
		echo -e "Unit file does not exist, generating..\n"
		# Generate userspace run_ug service
		# Toggles audio functionality on and off
		/usr/local/bin/wavelet_etcd_interaction.sh generate_service "/interface/audio/enabled" 0 0 "wavelet_audio_toggle"
		systemctl --user daemon-reload
		systemctl --user enable wavelet_audio_toggle.service --now
	fi
}

event_audio_bluetooth_connect(){
	if [[ -f ~/.config/systemd/user/wavelet_bluetooth_audio.service ]]; then
		echo -e "Unit file already generated, moving on\n"
		:
	else
		echo -e "Unit file does not exist, generating..\n"
		# Generate userspace run_ug service
		# Monitors the bluetooth MAC value and updates the system if there's a change
		/usr/local/bin/wavelet_etcd_interaction.sh generate_service "/audio_interface_bluetooth_mac" 0 0 "wavelet_set_bluetooth_connect"
		echo -e "Generating Reboot SystemdD unit in /.config/systemd/user.."
		systemctl --user daemon-reload
		systemctl --user enable wavelet_bluetooth_audio.service --now
	fi
}

event_livestreamservice(){
	if [[ -f ~/.config/systemd/user/wavelet_livestream.service ]]; then
		echo -e "Unit file already generated, moving on\n"
		:
	else
		echo -e "Unit file does not exist, generating..\n"
		# Generate userspace run_ug service
		# creates wavelet_livestream systemd unit.
		# I think this can run on the server without causing performance issues.
		/usr/local/bin/wavelet_etcd_interaction.sh generate_service "uv_islivestreaming" 0 0 "wavelet_livestream"
		systemctl --user daemon-reload
		systemctl --user enable wavelet_livestream.service --now
	fi
}
event_generate_reflector(){
	if [[ -f ~/.config/systemd/user/wavelet_reflector.service ]]; then
		echo -e "Unit file already generated, moving on\n"
		:
	else
		echo -e "Unit file does not exist, generating..\n"
		# Generate userspace reflector service
		/usr/local/bin/wavelet_etcd_interaction.sh generate_service "REFLECTOR_ARGS" 0 0 "wavelet.reflector"
		# ExecStart=/usr/local/bin/UltraGrid.AppImage $(etcdctl --endpoints=${ETCDENDPOINT} get REFLECTOR_ARGS --print-value-only)
		systemctl --user daemon-reload
		systemctl --user enable wavelet.reflector.service --now
	fi
}

event_generate_controller(){
	if [[ -f ~/.config/systemd/user/wavelet_controller.service ]]; then
		echo -e "Unit file already generated, moving on\n"
		:
	else
		echo -e "Unit file does not exist, generating..\n"
		# Generate userspace controller service
		/usr/local/bin/wavelet_etcd_interaction.sh generate_service "input_update" 0 0 "wavelet_controller"
		systemctl --user daemon-reload
		systemctl --user enable wavelet_controller.service --now
	fi
}

event_generate_reflectorreload(){
	if [[ -f ~/.config/systemd/user/wavelet_reflector_reload.service ]]; then
		echo -e "Unit file already generated, moving on\n"
		:
	else
		echo -e "Unit file does not exist, generating..\n"
		# Generate userspace reflector_reload service
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service "/decoderip/" 0 0 "wavelet_reflector_reload"
	systemctl --user daemon-reload
	systemctl --user enable wavelet_reflector_reload.service --now
	fi
}

event_generate_encoder_service(){
	if [[ -f ~/.config/systemd/user/wavelet_encoder.service ]]; then
		echo -e "Unit file already generated, moving on\n"
		:
	else
		echo -e "Unit file does not exist, generating..\n"
		# Generate userspace encoder service
		echo -e "[Unit]
Description=Wavelet Encoder service
After=network-online.target etcd-member.service
Wants=network-online.target

[Service]
ExecStart=/bin/bash -c "/usr/local/bin/wavelet_encoder.sh"

[Install]
WantedBy=default.target" > /var/home/wavelet/.config/systemd/user/wavelet_encoder.service
		systemctl --user daemon-reload
		systemctl --user enable wavelet_encoder.service
	fi
}

event_generate_run_ug(){
	# Generate userspace run_ug service
	echo -e "[Unit]
Description=Wavelet Encoder/Decoder runner
After=network-online.target etcd-member.service
Wants=network-online.target

[Service]
ExecStart=/bin/bash -c "/usr/local/bin/run_ug.sh"

[Install]
WantedBy=default.target" > /var/home/wavelet/.config/systemd/user/run_ug.service
	systemctl --user daemon-reload
}

event_generateHash(){
		# Can be modified from webUI, populates with hostname by default
		# arg is the device type I.E enc, dec, svr etc.
		hashType=${1}
		currentHostName=$(hostname)
		echo -e "device hostname is: ${currentHostName}"
		hostHash=$(cat /etc/machine-id | sha256sum | tr -d "[:space:]-")
		echo -e "generated device hash: ${hostHash} \n"
		# Check for pre-existing keys here
		KEYNAME="/hostHash/${hostHash}"; read_etcd_global; hashExists=${printvalue}
		if [[ -z "${hashExists}" || ${#hashExists} -le 1 ]] then
			echo -e "\nHostname value was set to ${hashExists}, which is null or less than 1 char, therefore it is not valid. \n"
			# Populate what will initially be used as the label variable from the webUI
			case ${1} in
				enc*)			KEYVALUE="enc";
				;;
				dec*)			KEYVALUE="dec";
				;;
				gateway*)		KEYVALUE="gtwy";
				;;
				svr*)			KEYVALUE="svr";
				;;
				*)				echo -e "host type is invalid, exiting."	;	exit 0
				;;
			esac
			KEYNAME="/hostLabel/${currentHostName}/type"; write_etcd_global
			# And the reverse lookups for the device
			KEYNAME="/hostHash/${currentHostName}/Hash"; KEYVALUE="${hostHash}"; write_etcd_global
			KEYNAME="/${currentHostName}/Hash"; write_etcd_global
			KEYNAME="/hostHash/${hostHash}"; KEYVALUE="${currentHostName}"; write_etcd_global
			KEYNAME="/hostHash/${currentHostName}/label"; write_etcd_global
		else
			echo -e "\nHash value exists as /hostHash/${hashExists}\n"
			echo -e "This means the device is already populated, or has not been removed cleanly. Checking to see if we've been relabeled.."
			KEYNAME="/${currentHostName}/RECENT_RELABEL"; read_etcd_global
			if [[ "${printvalue}" == "1" ]]; then
				echo -e "This device was recently relabeled!  Clearing hash and running this function again..\n"
				KEYNAME="${currentHostName}/RECENT_RELABEL"; KEYVALUE="0"; write_etcd_global
				KEYNAME="/hostHash/${hostHash}"; delete_etcd_key_global
				event_generateHash ${hashType}
			fi
		fi
}

event_device_redetect(){
	# Watches for a device redetection flag, then runs detectv4l.sh
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service "DEVICE_REDETECT" 0 0 "wavelet_detectv4l"
	systemctl --user daemon-reload
	systemctl --user enable wavelet_detectv4l.service --now
}

event_host_relabel_watcher(){
	# Watches for a device relabel flag, then runs wavelet_device_relabel.sh
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service /\"%H\"/RELABEL 0 0 "wavelet_device_relabel" \'relabel\'
	systemctl --user enable wavelet_device_relabel.service --now
}


#####
#
# Main
#
#####

# Check for pre-existing log file
# This is necessary because of system restarts, the log will get overwritten, and we need to see what it's doing across reboots.
logName=/var/home/wavelet/build_ug.log
if [[ -e $logName || -L $logName ]] ; then
	i=0
	while [[ -e $logName-$i || -L $logName-$i ]] ; do
		let i++
	done
	logName=$logName-$i
fi

#set -x
exec > "${logName}" 2>&1

detect_self