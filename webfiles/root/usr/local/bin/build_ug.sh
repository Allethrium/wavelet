#!/bin/bash
# Builds UltraGrid systemD user unit files and configures other basic parameters during initial deployment
# This is launched in userspace.  
# The service is called each logon from Sway, checks to see if already built, then calls other scripts as required.
# it launches run_ug if hostname/config flag are set.


# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
read_etcd(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd" ${KEYNAME})
	echo -e "Key Name: {$KEYNAME} read from etcd for value: $printvalue for host: ${hostNameSys}\n"
}
read_etcd_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}") 
	echo -e "Key Name: {$KEYNAME} read from etcd for Global Value: $printvalue\n"
}
read_etcd_prefix(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_prefix" "${KEYNAME}")
	echo -e "Key Name: {$KEYNAME} read from etcd for value $printvalue for host: ${hostNameSys}\n"
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
	echo -e "Key Name: ${KEYNAME} set to ${KEYVALUE} under /${hostNameSys}/\n"
}
write_etcd_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name: ${KEYNAME} set to: ${KEYVALUE} for Global value\n"
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
delete_etcd_key_prefix(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key_prefix" "${KEYNAME}"
}
generate_service(){
	# Can be called with more args with "generate_service" ${keyToWatch} 0 0 "${serviceName}"
	/usr/local/bin/wavelet_etcd_interaction.sh "generate_service" "${serviceName}"
}
etcd_provision_request(){
	# RunOnce for client provisioning, server handles request from there.
	/usr/local/bin/wavelet_etcd_interaction.sh "client_provision_request"
	sleep .5
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "client_provision_response")
	echo "${printvalue}" > ~/.ssh/secrets/etcd_client_pw.secure
	# Perform a test here to ensure everything is good and the client can write its own keys.
	echo "Client provision request completed, client username has been generated and access to appropriate keys granted."
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
	systemctl --user enable foot-server.socket --now
	# Detect_self in this case relies on the etcd type key
	KEYNAME="/hostLabel/${hostNameSys}/type"; read_etcd_global
	echo -e "Host type is: ${printvalue}\n"
	# test if i'm the server
	if [[ $(hostname) = *"svr"* ]]; then
		echo -e "I am a Server. Proceeding..."; event_server
	else
		# Handle encoder or decoder paths
		if [[ ${printvalue} = *"enc"* ]]; then
			echo "I am an encoder"; event_encoder
		else
			# This is for anything NOT a svr or enc, including an unpopulated new device.
			echo "I am a decoder"; event_decoder
		fi
	fi
}

# These codeblocks directly enable the appropriate service immediately.
# run_ug.sh will perform its own autodetection logic, this might seem redundant and probably is.
# It was written before the need for this script became apparent.
# to run systemd as another user (IE from root) do systemctl --user -M wavelet@  service.service

event_decoder(){
	echo -e "Decoder routine started."
	event_connectwifi
	# Provision request to etcd
	etcd_provision_request
	sleep .5
	echo -e "Setting up systemd services to be a decoder, moving to run_ug"
	event_generateHash dec
	event_blankhost
	event_reveal
	event_reset
	event_system_reboot
	event_host_relabel_watcher
	event_promote
	systemctl --user daemon-reload
	systemctl --user enable \
		wavelet_decoder_reboot \
		wavelet_decoder_reset \
		wavelet_decoder_blank \
		wavelet_decoder_reveal \
		wavelet_reboot \
		wavelet_reset \
		wavelet_deprovision \
		wavelet_device_relabel \
		wavelet_promote --now
	# Notifies the server to provision the client machine and give it a role for its own key range
	# Might work terribly, will have to test.
	KEYNAME="/PROV/REQUEST"; KEYVALUE="${hostNameSys}"; write_etcd_global
	sleep .33
	# if fails, we have a security rights issue or the etcd_interaction module failed somehow.
	KEYNAME="wavelet_build_completed"; KEYVALUE="1"; write_etcd
	# Set Type keys to "dec" for system, /hostLabel/ and also for UI
	KEYVALUE="dec";	KEYNAME="/${hostNameSys}/type"; write_etcd_global
	KEYNAME="/UI/hosts/${hostNameSys}/type"; write_etcd_global
	KEYNAME="/UI/hostlist/${hostNameSys}"; write_etcd_global
	KEYNAME="/${hostNameSys}/hostNamePretty"; KEYVALUE=${hostNamePretty}; write_etcd_global
	# Executes run_ug in order to start the video streaming window
	systemctl --user start run_ug.service
}
event_encoder(){
	echo -e "Encoder routine started.."
	if [[ -f /var/no.wifi ]]; then
		echo "wifi disabled on this host.."
		:
	else
		event_connectwifi
	fi
    event_encoder_reboot
    event_system_reboot
    event_reset
    event_device_redetect
    event_host_relabel_watcher
    event_generate_wavelet_encoder_query
    event_promote
	systemctl --user daemon-reload
	# Generate Systemd notifier services for encoders
	systemctl --user enable \
		wavelet_decoder_reboot \
		wavelet_decoder_reset \
		wavelet_decoder_blank \
		wavelet_decoder_reveal \
		wavelet_reboot \
		wavelet_reset \
		wavelet_deprovision \
		wavelet_device_relabel \
		wavelet_promote \
		wavelet_encoder_query --now
	# We do not perform run_ug for the encoder as that is enabled if it receives an encoderflag change.  It will be idle until then.
	# Run detectv4l here
	/usr/local/bin/wavelet_detectv4l.sh
	# Set Type keys to "enc"
	KEYVALUE="enc";	KEYNAME="/${hostNameSys}/type"; write_etcd_global
	KEYNAME="/UI/hosts/$hostNameSys/type"; write_etcd_global
	KEYNAME="/UI/hostlist/${hostNameSys}"; write_etcd_global
	KEYNAME="/${hostNameSys}/hostNamePretty"; KEYVALUE=${hostNamePretty}; write_etcd_global
}

event_generate_wavelet_encoder_query(){
	KEYNAME="wavelet_build_completed"; KEYVALUE="1"; write_etcd
	# We need to add this switch here to ensure if we're a server we don't populate ourselves to the encoders DOM in the webUI..
	if [[ ${hostNamePretty} == *"enc"* ]]; then
		event_generateHash enc
	else
		# generateHash was already called from the server event function.
		:
	fi
	# Can be called directly, remember to escape quotes if we want to preserve them as per bash standards.
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service "ENCODER_QUERY" 0 0 "wavelet_encoder_query"
}
event_server(){
	if [[ -f /var/pxe.complete ]]; then
		echo -e "\nPXE service up and running, continuing..\n"
	else
		echo -e "\nPXE service has not completed setup, exiting until the next reboot..\n"
		exit 0
	fi

	if [[ -f /var/home/wavelet/server_bootstrap_completed ]]; then
		echo -e "Server bootstrap completed, continuing"
		systemctl --user enable run_ug.service --now
		systemctl --user enable wavelet_init.service --now
	else
		echo -e "Server bootstrap not completed\n"
		server_bootstrap
	fi
	# The server runs a superset of most of the client machines units, however it shouldn't support renaming.
	svr_pw=$(cat /var/home/wavelet/.ssh/secrets/etcd_svr_pw.secure)
	event_generate_wavelet_encoder_query
	event_generate_wavelet_ui_service
	event_clear_devicemap
	event_generate_reflector
	event_generate_controller
	event_generate_reflectorreload
	event_system_reboot 
	event_reset
	event_device_redetect
	event_audio_toggle
	event_audio_bluetooth_connect
	event_generateHash svr
	systemctl --user daemon-reload
	systemctl --user start \
		wavelet_reflector \
		wavelet_audio_toggle \
		wavelet_controller \
		wavelet_decoder_reboot \
		wavelet_decoder_reset \
		wavelet_device_redetect \
		wavelet_encoder_query \
		wavelet_reboot \
		wavelet_reflector_reload \
		wavelet_reset \
		wavelet_set_bluetooth_connect \
		wavelet_ui --now
	echo "System services generated, starting services now.."
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
	# Generate basic ETCD roles and key permissions
	mkdir -p ~/.ssh/secrets
	bootstrap_http
	bootstrap_nginx_php
	#bootstrap_nodejs		#	WAY in the future for UI stuff.
	#bootstrap_livestream 	#	Probably not necessary to spin up a whole container for this..
	bootstrap_dnsmasq_watcher_service
	touch /var/home/wavelet/server_bootstrap_completed
	echo -e "Enabling server notification services"
	event_generate_controller
	event_generate_provision
	event_generate_reflectorreload
	event_generate_watch_provision
	event_generate_run_ug
	systemctl --user enable wavelet_controller.service --now
	systemctl --user enable wavelet_reflector.service --now
	# uncomment a firefox exec command into sway config, this will bring up the management console on the server in a new sway window, as a backup control surface.
	# - note we need to work on a firefox policy/autoconfig which FF will actually respect
	sed -i 's|#exec /usr/local/bin/wavelet_start_UI.sh|exec /usr/local/bin/wavelet_start_UI.sh|g' /var/home/wavelet/.config/sway/config
	# Next, we build the reflector prune function.  This is necessary for removing streams for old decoders and maintaining the long term health of the system
		# Get decoderIP list
		# Ping each decoder on list
		# If dead, ping more intensively for 30s
		# If still dead, remove from reflector subscription
	# Add server type ID into etcd (note the webUI could change the server's type from the UI side but would be prevented from changing the server SYSTEM type)
	KEYVALUE="svr";	KEYNAME="/${hostNameSys}/type"; write_etcd_global
	KEYNAME="/UI/hosts/$hostNameSys/type"; write_etcd_global
	KEYNAME="/UI/hostlist/${hostNameSys}"; write_etcd_global
	KEYNAME="/${hostNameSys}/hostNamePretty"; KEYVALUE=${hostNamePretty}; write_etcd_global
	# Add a service to prune dead FUSE mountpoints.  Every time the UltraGrid AppImage is restarted, it leaves stale mountpoints.  This timed task will help keep everything clean.
		# Get "alive mountpoints"
		# Prune anything !=alive
	echo -e "Server configuration is now complete, bringing services up.."
	event_server
}

### "/UI/hosts/$hostNameSys/control/$function"
event_system_reboot(){
	# Everything should watch the system reboot flag for a hard reset
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service SYSTEM_REBOOT 0 0 "wavelet_reboot"
	# and the same for the host reboot
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service /UI/hosts/\"%H\"/control/DECODER_REBOOT 0 0 "wavelet_decoder_reboot"
}
event_reset(){
	# Everything should watch the system reboot flag for a task reset
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service SYSTEM_RESET 0 0 "wavelet_reset"
	# and the same for the host reset
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service /UI/hosts/\"%H\"/control/DECODER_RESET 0 0 "wavelet_decoder_reset"
}
event_reveal(){
	# Tells specific host to display SMPTE bars on screen, useful for finding which is what and where
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service /UI/hosts/\"%H\"/control/DECODER_REVEAL 0 0 "wavelet_decoder_reveal"
}
event_blankhost(){
	# Tells specific host to display a black testcard on the screen, use this for privacy modes as necessary.
	# Host Blank is necessary for the UI to load properly, so we always set it here
	KEYNAME="/UI/hosts/${hostNameSys}/control/BLANK"; KEYVALUE="0"; write_etcd_global
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service /UI/hosts/\"%H\"/control/DECODER_BLANK 0 0 "wavelet_decoder_blank"
}
event_promote(){
	# This flag watches the hostname to instruct the machine to (pro/de)mote the (en/de)coder as appropriate.
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service /UI/hosts/\"%H\"/control/PROMOTE 0 0 "wavelet_promote"
}
event_audio_toggle(){
	if [[ -f ~/.config/systemd/user/wavelet_audio_toggle.service ]]; then
		echo -e "Unit file already generated, moving on\n"
		:
	else
		echo -e "Unit file does not exist, generating..\n"
		# Generate userspace run_ug service
		# Toggles audio functionality on and off
		/usr/local/bin/wavelet_etcd_interaction.sh generate_service "/UI/audio" 0 0 "wavelet_audio_toggle"
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
		/usr/local/bin/wavelet_etcd_interaction.sh generate_service "/UI/audio/audio_interface_bluetooth_mac" 0 0 "wavelet_set_bluetooth_connect"
		echo -e "Generating Reboot SystemdD unit in /.config/systemd/user.."
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
	fi
}
event_generate_controller(){
	if [[ -f ~/.config/systemd/user/wavelet_controller.service ]]; then
		echo -e "Unit file already generated, moving on\n"
		:
	else
		echo -e "Unit file does not exist, generating..\n"
		# Generate userspace controller service
		/usr/local/bin/wavelet_etcd_interaction.sh generate_service "/UI/INPUT_UPDATE" 0 0 "wavelet_controller"
	fi
}
event_generate_provision(){
	if [[ -f ~/.config/systemd/user/wavelet_provision.service ]]; then
		echo -e "Unit file already generated, moving on\n"
		:
	else
		echo -e "Unit file does not exist, generating..\n"
		# Generate userspace provision service
		/usr/local/bin/wavelet_etcd_interaction.sh generate_service "/PROV/REQUEST" 0 0 "wavelet_provision"
	fi
}
event_generate_reflectorreload(){
	if [[ -f ~/.config/systemd/user/wavelet_reflector_reload.service ]]; then
		echo -e "Unit file already generated, moving on."
		:
	else
		echo -e "Unit file does not exist, generating..\n"
		# Generate userspace reflector_reload service
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service "/DECODERIP/ --prefix" 0 0 "wavelet_reflector_reload"
	fi
}
event_generate_wavelet_ui_service(){
	# Final step of the server spinup, and starts the web interface on the server console.
	if [[ -f /var/home/wavelet/.config/systemd/user/wavelet_ui.service ]]; then
		echo -e "Unit file already generated, moving on."
		:
	else
		echo -e '[Unit]
Description=Wavelet UI service
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStartPre=/bin/sleep 8
ExecStart=/bin/bash -c "/usr/local/bin/wavelet_start_UI.sh"
[Install]
WantedBy=default.target' > /var/home/wavelet/.config/systemd/user/wavelet_ui.service
	fi
}
event_generate_encoder_service(){
	if [[ -f ~/.config/systemd/user/wavelet_encoder.service ]]; then
		echo -e "Unit file already generated, moving on."
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
StartLimitBurst=30

[Install]
WantedBy=default.target" > /var/home/wavelet/.config/systemd/user/run_ug.service
	systemctl --user daemon-reload
}
event_generateHash(){
		# arg is the device type I.E enc, dec, svr etc.
		hashType=${1}
		echo -e "device label/pretty hostname is: ${hostNamePretty}"
		echo -e "device persistent hostname is: ${hostNameSys}"
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
			# Populate UI data
			KEYNAME="/UI/hosts/${hostNameSys}/type"; write_etcd_global
			KEYNAME="/UI/hosts/${hostNameSys}/hash"; KEYVALUE="${hostHash}"; write_etcd_global
			KEYNAME="/UI/hosts/${hostNameSys}/control/label"; KEYVALUE="${hostNamePretty}"; write_etcd_global
			# Populate SYSTEM values
			KEYNAME="/${hostNameSys}/Hash"; write_etcd_global
			KEYNAME="/hostHash/${hostHash}"; KEYVALUE="${hostNameSys}"; write_etcd_global
			KEYNAME="/hostHash/${hostNameSys}/label"; KEYVALUE="${hostNamePretty}"; write_etcd_global
			KEYNAME="/${hostNameSys}/hostNamePretty"; KEYVALUE=${hostNamePretty}; write_etcd_global
		else
			echo -e "Hash value exists as /hostHash/${hashExists}"
			echo -e "Device already populated, taking no further action."
		fi
}
event_device_redetect(){
	# Watches for a device redetection flag, then runs detectv4l.sh
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service "DEVICE_REDETECT" 0 0 "wavelet_device_redetect"
}
event_host_relabel_watcher(){
	# Watches for a device relabel flag, then runs wavelet_device_relabel.sh
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service /UI/hosts/%H/control/RELABEL 0 0 "wavelet_device_relabel" \"relabel\"
}
event_generate_watch_provision(){
	# Watches for device provision requests
	/usr/local/bin/wavelet_etcd_interaction.sh generate_service "PROV_RQ" 0 0 "wavelet_device_provision"
}
event_clear_devicemap(){
	# Clears the device map file so it will be regenerated.  Since the paths under v4l2 aren't stable, 
	# we need to do this to avoid the channel indexing becoming incorrect
	rm -rf /var/home/wavelet/device_map_entries_verity
	echo -e "Device map file removed, will be regenerated on input device selection."
}
event_connectwifi(){
	# Does not configure wifi, but attempts to list and connect a wavelet WiFi connection
	# Assumes valid polkit rules allowing wavelet user to manage network connections
	nmcli r wifi on
	if [[ ${hostNameSys} = *"svr"* ]]; then
		echo -e "If you want to run the server via a WiFi connection, this should be configured and enabled manually via nmtui or nmcli."
		echo -e "Performance will likely suffer as a result."
	fi

	if [[ -f /var/no.wifi ]]; then
		echo -e "The /var/no.wifi flag is set.  Please remove this file if this host should utilize wireless connectivity."
		KEYNAME="/${hostNameSys}/WIFI"; KEYVALUE="0"; write_etcd_global
	fi
	files=$(find /var/home/wavelet/config -maxdepth 1 -name "wifi.*.key")
	if [[ ${#files[@]} -gt 0 ]]; then
		echo "Network configuration file found, continuing and getting UUID for connection.."
	else
		echo "No file found for network configuration, connectwifi has failed, there is no available wireless connection.  setting troubleshooting flag and rebooting.."
		touch /var/home/wavelet/config/wifi_issue.flag
		systemctl reboot -i
	fi
	networkUUID=$(cat /var/home/wavelet/config/wifi.*.key)
	# Set autoconnection again and ensure wifi is up
	# Attempt to connect to the configured wifi before proceeding
	if nmcli con up $(cat /var/home/wavelet/config/wifi_ssid); then
		echo "Configured connection established, continuing."
		# We'll use this flag for future UI improvements to help determine if a host is wired or wireless
		KEYNAME="/${hostNameSys}/WIFI"; KEYVALUE="1"; write_etcd_global
	fi
}


#####
#
# Main
#
#####


hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
# Check for pre-existing log file
# This is necessary because of system restarts, the log will get overwritten, and we need to see what it's doing across reboots.
logName=/var/home/wavelet/logs/build_ug.log
if [[ -e $logName || -L $logName ]] ; then
	i=0
	while [[ -e $logName-$i || -L $logName-$i ]] ; do
		let i++
	done
	logName=$logName-$i
fi

#set -x
exec > "${logName}" 2>&1

time=0
event_connectwifi

until [[ $(/usr/local/bin/wavelet_etcd_interaction.sh "check_status" | awk '{print $6}') = "true," ]]; do
	echo -e "Etcd still down.. waiting a second.."
	sleep 1
	time=$(( ${time} + 1 ))
	if [[ $time -eq "60" ]]; then
		echo "We have been waiting sixty seconds, there is likely a network issue."
		echo "Running the wifi connection script.."
		until /usr/local/bin/connectwifi.sh; do
			sleep .5
		done
	fi
done


detect_self