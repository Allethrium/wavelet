#!/bin/bash
# Builds UltraGrid systemD user unit files and configures other basic parameters during initial deployment
# This is launched in userspace.
# The service is called each logon from Sway, checks to see if already built, then calls other scripts as required.


# Check and define module paths

ETCDINTERACTIONHOOKS=""
if [[ -f "/var/wavelet_ramfs/etcd_interaction_hooks.sh" ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
	ETCDINTERACTIONHOOKS="/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source "/usr/local/bin/etcd_interaction_hooks.sh"
	ETCDINTERACTIONHOOKS="/usr/local/bin/etcd_interaction_hooks.sh"
fi

ETCDINTERACTIONMOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_etcd_interaction.sh" ]]; then
	ETCDINTERACTIONMOD="/var/wavelet_ramfs/wavelet_etcd_interaction.sh"
else
	ETCDINTERACTIONMOD="/usr/local/bin/wavelet_etcd_interaction.sh"
fi

ETCDMANAGEMENTMOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_etcd_management.sh" ]]; then
	ETCDMANAGEMENTMOD="/var/wavelet_ramfs/wavelet_etcd_management.sh"
else
	ETCDMANAGEMENTMOD="/usr/local/bin/wavelet_etcd_management.sh"
fi

WAVELET_PROVISION_MOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_provision.sh" ]]; then
	WAVELET_PROVISION_MOD="/var/wavelet_ramfs/wavelet_provision.sh"
else
	WAVELET_PROVISION_MOD="/usr/local/bin/wavelet_provision.sh"
fi

WAVELET_CLIENT_CONTROLLER_MOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_client_controller.sh" ]]; then
	WAVELET_CLIENT_CONTROLLER_MOD="/var/wavelet_ramfs/wavelet_client_controller.sh"
else
	WAVELET_CLIENT_CONTROLLER_MOD="/usr/local/bin/wavelet_client_controller.sh"
fi

WAVELET_DETECTV4L_MOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_detectv4l.sh" ]]; then
	WAVELET_DETECTV4L_MOD="/var/wavelet_ramfs/wavelet_detectv4l.sh"
else
	WAVELET_DETECTV4L_MOD="/usr/local/bin/wavelet_detectv4l.sh"
fi

ULTRAGRID_APPRUN=""
if [[ -f "/var/wavelet_ramfs/ultragrid/squashfs-root/AppRun" ]]; then
	ULTRAGRID_APPRUN="/var/wavelet_ramfs/ultragrid/squashfs-root/AppRun"
else
	ULTRAGRID_APPRUN="/usr/local/bin/ultragrid/squashfs-root/AppRun"
fi

WAVELET_SCREENCAST_MOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_screencast.sh" ]]; then
	WAVELET_SCREENCAST_MOD="/var/wavelet_ramfs/wavelet_screencast.sh"
else
	WAVELET_SCREENCAST_MOD="/usr/local/bin/wavelet_screencast.sh"
fi


# Export Modules

etcd_provision_watcher(){
	# wavelet user systemd service to get provision data back after processing from svr
	serverHostName="$(cat /var/home/wavelet/config/serverhostname.txt)"
	local provisionPass; provisionPass="$(cat /var/home/wavelet/config/provisionpw)"
	cat > "/var/home/wavelet/.config/systemd/user/wavelet_provision_watcher.service" <<-EOF
		[Unit]
		Description=Wavelet provision retrieval (UID 1337)
		After=network-online.target etcd-member.service
		Wants=network-online.target

		[Service]
		Environment=ETCDCTL_ENDPOINTS='https://$serverHostName:2379'
		ExecStart=/usr/bin/etcdctl --user PROV:$provisionPass watch /PROV/RESPONSE \
	-w simple -- /usr/bin/bash -c "$WAVELET_PROVISION_MOD '2'"
		StartLimitBurst=30

		[Install]
		WantedBy=default.target
		EOF
	until ping -c 1 "$serverHostName"; do
		sleep .1
	done
	systemctl --user daemon-reload && systemctl --user enable wavelet_provision_watcher.service	--now
}

etcd_provision_request(){
	# RunOnce for client ETCD provisioning, server handles request and returns a credential.
	# The client side runs as wavelet / 1337
	echo "Calling client provision.."
	"$ETCDMANAGEMENTMOD" "client_provision_request"
	sleep 1
	"$ETCDMANAGEMENTMOD" "client_provision_get_data"
	sleep 2
	# Wait for etcd_interaction to perform its task and write the done flag
	while [[ ! -f "/var/home/wavelet/config/provisioned.rq.complete" ]]; do
		sleep .1
		echo "waiting for provision process to complete.."
	done
	# Test etcd interaction via the wrapper process
	KEYNAME="PROV_TEST"; KEYVALUE="True"; write_etcd; sleep .5 ; read_etcd
	if [[ "$printvalue" = "True" ]]; then
		echo "Client provision request completed, client username has been generated and access to appropriate keys granted."
		touch /var/home/wavelet/config/provisioned.complete
		# We shred the etcd provision credential, as it's no longer needed
		shred /var/home/wavelet/config/provisionpw && rm -rf /var/home/wavelet/config/provisionpw
	else
		echo "Client provisioning has failed.  Key value is not accessible, or does not match!"
		exit 1
	fi
	rm -rf "/var/home/wavelet/.config/systemd/user/wavelet_provision_watcher.service" && systemctl --user daemon-reload
}

detect_self(){
	systemctl --user daemon-reload
	systemctl --user enable foot-server.socket --now
	if [[ -f "/var/home/wavelet/config/provisioned.complete" ]]; then
		echo "Provisioning completed, detecting self via etcd.."
		# We must get a ping from the server before continuing
		# since we are already provisioned, a wifi connection by default is available
		# If the no-wifi flag is set, ethernet should already be available
		serverHostName="$(cat /var/home/wavelet/config/serverhostname.txt)"
		if [[ ! -f /var/no.wifi ]]; then
			event_connectNetwork
		fi
		"$WAVELET_SCREENCAST_MOD" "capable"
		# Wait until etcd service is available on the server before proceeding
		until result=$("$ETCDINTERACTIONMOD" "check_status"); do
			if [[ $? -ne 0 ]]; then
				echo "		Command failed!"
			fi
			if [[ "$result" != "OK" ]]; then
				sleep .25
			else
				break
			fi
		done

		# Detect_self in this case relies on the etcd type key
		KEYNAME="/HOSTS/$hostNameSys/type"; read_etcd_global
		echo -e "Host type is: $printvalue\n"
		# test if i'm the server
		if [[ "$(hostname)" = *"svr"* ]]; then
			# This is fine because a server always has etcd rights
			echo -e "	I am a Server. Proceeding..."; event_server
		else
			# Handle encoder or decoder paths
			# This is fine because an encoder will have previously been a decoder, and have etcd rights.
			if [[ "$printvalue" = *"enc"* ]]; then
				echo "	I am an encoder"; event_encoder
			else
				# This is for anything NOT a svr or enc, including an unpopulated new device.
				# This COULD have etcd rights, or not and just "fail".  This is why it's not specific.
				echo "	I am a decoder"; event_decoder
			fi
		fi
	else
		echo "		Provisioning is NOT complete, detecting self via system hostname.."
		case "$(hostname)" in
			svr*)	echo "		Server detected"; event_server;;
			dec*)	echo "		Decoder detected"; event_decoder;;
		esac
	fi
}

# These codeblocks directly enable the appropriate service immediately.
# It was written before the need for this script became apparent.
# to run systemd as another user (IE from root) do systemctl --user -M wavelet@  service.service

event_decoder(){
	echo -e "	Decoder startup routine started."
	KEYDATA=""
	local staticImagePath; local staticImageURL
	local staticHashPath; local staticHashURL; local groupHash
	local blankImagePath; local serverCheckSum; local localCheckSum
	# Provision request to etcd
	serverHostName="$(cat /var/home/wavelet/config/serverhostname.txt)"
	KEYNAME="/HOSTS/$hostNameSys/control/GROUP"; read_etcd_global
	if [[ -z "$printvalue" ]]; then
		KEYNAME="/GROUPS/$serverHostName"; read_etcd_global; groupHash="$printvalue"
	fi

	# Get group video source
	KEYNAME="/UI/GROUPS/$groupHash/control/sourceHash"; read_etcd_global
	sourceHash="$printvalue"
	if [[ -z "$sourceHash" ]] || ! [[ "$sourceHash" =~ ^[0-3]$ ]]; then
		# default to initial static splash image
		sourceHash=1
	fi
	channel="$sourceHash"
	streamMode="static"

	# Determine video source state keys (replicating run_decoder logic)
	if [[ "$sourceHash" =~ ^[0-3]$ ]]; then
		# Static image - no subscription needed
		videoSourceType="static"
		videoSourceActive="0"
		videoSourceSubType="static"
		videoSourceDirect="0"
	else
		# Defaulting to UltraGrid source
		videoSourceType="ug"
		videoSourceActive="1"
		videoSourceSubType="ug"
		videoSourceDirect="0"
	fi

	if [[ ! -f "/var/home/wavelet/config/provisioned.complete" ]]; then
		echo "	First run, sending provision request to server.."
		etcd_provision_watcher; sleep 2
		etcd_provision_request
		# Generate control keys under our host entry, if the mod key has been changed more than 0 times.
		# In the case of a client, the initial host key has already been generated
		# Get the primary group
		KEYDATA="mod(\"/HOSTS/$hostNameSys\") > \"0\"

put /HOSTS/$hostNameSys/control/label \"$hostNamePretty\"
put /HOSTS/$hostNameSys/control/rebootStatus \"0\"
put /HOSTS/$hostNameSys/control/resetStatus \"0\"
put /HOSTS/$hostNameSys/control/revealStatus \"0\"
put /HOSTS/$hostNameSys/control/healthStatus \"0\"
put /HOSTS/$hostNameSys/type \"dec\"
put /HOSTS/$hostNameSys/control/videoSourceType \"$videoSourceType\"
put /HOSTS/$hostNameSys/control/videoSourceActive \"$videoSourceActive\"
put /HOSTS/$hostNameSys/control/videoSourceSubType \"$videoSourceSubType\"
put /HOSTS/$hostNameSys/control/videoSourceDirect \"$videoSourceDirect\"
put /HOSTS/$hostNameSys/control/previousVideoSourceKey \"$sourceHash\"
put /HOSTS/$hostNameSys/control/previousVideoSourceType \"$streamMode\"
put /HOSTS/$hostNameSys/control/channel-Source \"$channel-$sourceHash\"
put /HOSTS/$hostNameSys/wavelet_build_completed \"1\"

put /HOSTS/$hostNameSys/control/label \"$hostNamePretty\"
put /HOSTS/$hostNameSys/control/rebootStatus \"0\"
put /HOSTS/$hostNameSys/control/resetStatus \"0\"
put /HOSTS/$hostNameSys/control/revealStatus \"0\"
put /HOSTS/$hostNameSys/control/healthStatus \"0\"
put /HOSTS/$hostNameSys/type \"dec\"
put /HOSTS/$hostNameSys/control/videoSourceType \"$videoSourceType\"
put /HOSTS/$hostNameSys/control/videoSourceActive \"$videoSourceActive\"
put /HOSTS/$hostNameSys/control/videoSourceSubType \"$videoSourceSubType\"
put /HOSTS/$hostNameSys/control/videoSourceDirect \"$videoSourceDirect\"
put /HOSTS/$hostNameSys/control/previousVideoSourceKey \"$sourceHash\"
put /HOSTS/$hostNameSys/control/previousVideoSourceType \"$streamMode\"
put /HOSTS/$hostNameSys/control/channel-Source \"$channel-$sourceHash\"
put /HOSTS/$hostNameSys/wavelet_build_completed \"1\"

"
		touch /var/home/wavelet/config/provisioned.complete
	else
		# Write any data which may have been updated on the system side
		# Note IP address is set already
		# blankStatus shouldn't change on reboot
		KEYDATA="mod(\"/HOSTS/$hostNameSys\") > \"0\"

put /HOSTS/$hostNameSys/control/label \"$hostNamePretty\"
put /HOSTS/$hostNameSys/control/rebootStatus \"0\"
put /HOSTS/$hostNameSys/control/resetStatus \"0\"
put /HOSTS/$hostNameSys/control/revealStatus \"0\"
put /HOSTS/$hostNameSys/control/healthStatus \"0\"
put /HOSTS/$hostNameSys/type \"dec\"
put /HOSTS/$hostNameSys/control/videoSourceType \"$videoSourceType\"
put /HOSTS/$hostNameSys/control/videoSourceActive \"$videoSourceActive\"
put /HOSTS/$hostNameSys/control/videoSourceSubType \"$videoSourceSubType\"
put /HOSTS/$hostNameSys/control/videoSourceDirect \"$videoSourceDirect\"
put /HOSTS/$hostNameSys/control/previousVideoSourceKey \"$sourceHash\"
put /HOSTS/$hostNameSys/control/previousVideoSourceType \"$streamMode\"
put /HOSTS/$hostNameSys/control/channel-Source \"$channel-$sourceHash\"

put /HOSTS/$hostNameSys/control/label \"$hostNamePretty\"
put /HOSTS/$hostNameSys/control/rebootStatus \"0\"
put /HOSTS/$hostNameSys/control/resetStatus \"0\"
put /HOSTS/$hostNameSys/control/revealStatus \"0\"
put /HOSTS/$hostNameSys/control/healthStatus \"0\"
put /HOSTS/$hostNameSys/type \"dec\"
put /HOSTS/$hostNameSys/control/videoSourceType \"$videoSourceType\"
put /HOSTS/$hostNameSys/control/videoSourceActive \"$videoSourceActive\"
put /HOSTS/$hostNameSys/control/videoSourceSubType \"$videoSourceSubType\"
put /HOSTS/$hostNameSys/control/videoSourceDirect \"$videoSourceDirect\"
put /HOSTS/$hostNameSys/control/previousVideoSourceKey \"$sourceHash\"
put /HOSTS/$hostNameSys/control/previousVideoSourceType \"$streamMode\"
put /HOSTS/$hostNameSys/control/channel-Source \"$channel-$sourceHash\"

"
	fi
	sleep 2
	KEYNAME="/HOSTS/$hostNameSys"; read_etcd_global; hostHash="$printvalue"
	if [[ -z "$hostHash" ]]; then
		echo "	We do not have a valid host hash, which indicates something went wrong with the client provision process!"
		echo "	TBD: reprovision attempt call"
		exit 1
	fi
	echo "$hostHash" > /var/home/wavelet/config/hosthash.conf
	event_client_control
	write_etcd_txn "$KEYDATA"
	check_clientGroupMemberShip
	systemctl --user daemon-reload
	systemctl --user --no-block enable wavelet_client_controller --now

	staticImagePath="/var/home/wavelet/config/staticImage.mp4"
	blankImagePath="/var/home/wavelet/config/blankImage.bmp"

	# Generate the decoder blank image
	if [[ ! -f "$blankImagePath" ]]; then
  		echo "	Blank display image source isn't available, generating prototype.."
  		color="rgb(.2, .2, .2, 0)"
  		backGroundColor="rgb(.2, .2, .2, 0)"
  		magick -size 1920x1080 -pointsize 50 -background "$color" -bordercolor "$backGroundColor" \
  			-gravity Center -fill white label:'This screen is intentionally blank.' \
  			-colorspace RGB "$blankImagePath"
  	fi
  	# Generate the decoder static image if it doesn't exist or has changed
  	KEYNAME="/UI/GROUPS/$groupHash/control/staticImage"; read_etcd_global
  	if [[ -z "$printvalue" ]]; then
  		# We use the default Wavelet image
  		printvalue="https://$serverHostName/images/init_staticImage.mp4"
  	fi
  	staticImageURL="$printvalue"

	if [[ ! -f "$staticImagePath" ]]; then
  		echo "	Static display image file isn't on this client, downloading from server.."
  		# this is a URL reference to the appropriate group staticImage on the server
  		# init_staticImage.mp4 for factory default, or staticImage_$groupHash.mp4 for a custom image.
  		# a sha256 hash should also be generated so that we can test data integrity.
  		# it always overwrites staticImage.mp4 LOCALLY
  		echo "	Getting static image for Group hash: $printvalue"
  		wget -O "$staticImagePath" "$staticImageURL"
  	else
  		# Hash our current staticImage against the server's checksum
  		staticHashURL="${printvalue%*.mp4}.sha256"
  		staticHashPath="/var/home/wavelet/config/${staticHashURL##*/}.sha256"
  		wget -O "$staticHashPath" "$staticHashURL"
  		serverCheckSum="$(cat "$staticHashPath")"
		localCheckSum=$(sha256sum "$staticImagePath" | cut -d' ' -f1)
  		if [[ "$localCheckSum" != "$serverCheckSum" ]]; then
  			echo "	Static image file contents have changed!  Regenerating the video file.."
  			wget -O "$staticImagePath" "$staticImageURL"
  		fi
	fi
	event_connectNetwork
	echo "	CONFIGURATION COMPLETED."
	echo "		Launching client_controller in firstrun mode.."
	"$WAVELET_CLIENT_CONTROLLER_MOD" "RUN"
}
event_encoder(){
	# This may be obsolete with client_controller now handling much of the runtime logic.
	# An encoder started life as a decoder, so we don't need to call much of the initial generation logic.
	echo "   Encoder routine started.."
    event_generate_hotplug
    event_connectNetwork
	systemctl --user daemon-reload
	# Generate Systemd notifier services for encoders
	systemctl --user enable wavelet_client_control --now
	# Populate encoder state keys, if the mod key has been changed more than 0 times.
	KEYDATA="mod(\"/HOSTS/$hostNameSys\") > \"0\"

put /HOSTS/$hostNameSys/control/blankStatus \"0\"
put /HOSTS/$hostNameSys/control/label \"$hostNameSys\"
put /HOSTS/$hostNameSys/control/rebootStatus \"0\"
put /HOSTS/$hostNameSys/control/resetStatus \"0\"
put /HOSTS/$hostNameSys/control/revealStatus \"0\"
put /HOSTS/$hostNameSys/control/healthStatus \"0\"
put /HOSTS/$hostNameSys/type \"enc\"
put /HOSTS/$hostNameSys/wavelet_build_completed \"1\"

"
	write_etcd_txn "$KEYDATA"
	if [[ ! -f "/var/home/wavelet/config/enc_blankImage.bmp" ]]; then
		echo "Blank display isn't available, generating.."
			color="rgb(.2, .2, .2, 0)"
			backgroundcolor="rgb(.2, .2, .2, 0)"
		magick -size 1920x1080 -pointsize 50 -background "$color" -bordercolor "$backgroundcolor" \
		-gravity Center -fill white label:'TRANSMITTING AS ENCODER.\nThis screen is intentionally blank.' \
		-colorspace RGB /var/home/wavelet/config/enc_blankImage.bmp
	fi
	# Tag device redetect
	echo "  Encoder process complete.."
    KEYNAME="/HOSTS/$hostNameSys/wavelet_build_completed"; KEYVALUE="1"; write_etcd_global &
    "$WAVELET_CLIENT_CONTROLLER_MOD" "RUN"
    "$WAVELET_DETECTV4L_MOD" "redetect"
}

event_server(){
	# Responsible for generating the wavelet-specific userspace services that form the appliance core
	if [[ -f "/var/pxe.complete" ]]; then
		echo "	PXE service up and running, continuing.."
	else
		echo "	PXE boot service has not completed setup.  Please check logs."
		exit 1
	fi
	if [[ -f "/var/home/wavelet/server_bootstrap_completed" ]]; then
		echo "	Server bootstrap completed, continuing"
	else
		echo "	Server bootstrap not completed"
		server_bootstrap
	fi
	# Source conf file
	source "/var/home/wavelet/config/$(hostname).conf"
	# Tag device redetect
	echo -e "\n	System services and configuration keys generated, starting services now.."
	systemctl --user daemon-reload
	# Orchestrator should already be active
	systemctl --user start http-php-pod.service
	systemctl --user enable \
		wavelet_reflector \
		wavelet_init \
		wavelet_client_controller \
		wavelet_network_device --now --no-block
	touch /var/home/wavelet/config/provisioned.complete
	# Always update our group to the server primary group on run
	KEYNAME="/HOSTS/$hostNameSys/control/GROUP"; KEYVALUE="$PRIMARY_GROUPHASH"; write_etcd_global &
	echo "	Running initial device detection.."
	sleep 2
	/bin/bash -c "$WAVELET_DETECTV4L_MOD 'redetect'"
}

setup_httpd_quadlet(){
	echo -e "Generating Apache Podman container and systemd service file"
	mkdir -p "/var/home/wavelet/.config/containers/systemd/"
	# ref https://hub.docker.com/_/httpd
	cat > /var/home/wavelet/.config/containers/systemd/httpd.container <<-EOF
		[Unit]
		Description=HTTPD Quadlet
		After=local-fs.target

		[Container]
		ContainerName=httpd
		Image=%H/httpd:latest
		PublishPort=8080:80
		PublishPort=8443:443
		Volume=/home/wavelet/http:/usr/local/apache2/htdocs:z
		Volume=/home/wavelet/config/httpd.conf:/usr/local/apache2/conf/httpd.conf:Z
		Volume=/etc/ipa/ca.crt:/etc/ipa/ca.crt:ro
		Volume=/var/home/wavelet/config/certs/httpd.crt:/usr/local/apache2/certs/httpd.crt:ro,z
		Volume=/var/home/wavelet/config/certs/httpd.key:/usr/local/apache2/certs/httpd.key:ro,z
		Tmpfs=/run
		Tmpfs=/tmp
		Exec=httpd-foreground

		[Service]
		Restart=always
		RestartSec=5

		[Install]
		# Start by default on boot
		WantedBy=default.target
	EOF
	"$ETCDINTERACTIONHOOKS" "write_etcd_global" "SERVER_HTTP_BOOTSTRAP_COMPLETED" "1"
	# populate necessary files for decoder spinup, which are required to be directly accessible for the client ignition to succeed.
	cp /usr/local/bin/{UltraGrid.AppImage,wavelet_install_client.sh,connectwifi.sh,wavelet_install_packages.sh} /var/home/wavelet/http/ignition/
	cp /home/wavelet/.bashrc /home/wavelet/http/ignition/skel_bashrc.txt
	cp /home/wavelet/.bash_profile /home/wavelet/http/ignition/skel_profile.txt
	cp /usr/local/backgrounds/sway/wavelet_test.png /var/home/wavelet/http/ignition/
	chown -R wavelet:wavelet /home/wavelet/http
	chmod +x /home/wavelet/http
	# Note daemon-reload and service start handled in calling function
}
nginx_quadlets(){
	echo "Setting up NGINX + PHP-FPM quadlet.."
	cat > "/var/home/wavelet/.config/containers/systemd/php-fpm.container" <<-EOF
		[Unit]
		Description=PHP:FPM

		[Container]
		Image=%H/php-fpm-redis:latest
		Environment=HOST_MACHINE_HOSTNAME=%H
		Exec=/bin/bash -c '/usr/local/bin/entrypoint.sh'
		AutoUpdate=registry
		Secret=webui-key
		Secret=webui-enc
		Secret=redispw
		Pod=http-php.pod
	EOF
	cat > "/var/home/wavelet/.config/containers/systemd/nginx.container" <<-EOF
		[Unit]
		Description=NGINX

		[Container]
		Image=%H/nginx:latest
		Environment=HOST_MACHINE_HOSTNAME=%H
		AutoUpdate=registry
		Pod=http-php.pod
	EOF
	cat > "/var/home/wavelet/.config/containers/systemd/redis.container" <<-EOF
		[Unit]
		Description=REDIS

		[Container]
		Image=%H/redis:latest
		Exec=redis-server /usr/local/etc/redis/redis.conf
		Environment=HOST_MACHINE_HOSTNAME=%H
		AutoUpdate=registry
		Secret=redispw
		Pod=http-php.pod
	EOF
	mkdir -p "/var/home/wavelet/http-php/log"
	# Generate the webui key as a podman secret, and then shred the password
	podman secret create webui-key /var/home/wavelet/.ssh/secrets/.webui.key
	podman secret create webui-enc /var/home/wavelet/config/.webui.enc
	# Generate a random password for redis
	local redisPW="$(cat '/proc/sys/kernel/random/uuid' | sha256sum | tr -d ' -')"
	# SED the redis.conf file with generated password
	sed -i "s/my-redis-password/$redisPW/g" "/var/home/wavelet/config/redis.conf"
	echo "$redisPW" | podman secret create redispw -
	rm -rf "/var/home/wavelet/.ssh/secrets/.webui.key"; rm -rf "/var/home/wavelet/config/.webui.enc"
	# Move our crypt to an accessible volume
	# Required:
	# httpd TLS cert (used by HTTPD/Ignition server, Registry container service AND Nginx)
	# webUI factors for auth to etcd cluster
	cat > "/var/home/wavelet/.config/containers/systemd/http-php.pod" <<-EOF
		[Pod]
		PublishPort=9080:80
		PublishPort=443:443
		Volume=/var/home/wavelet/config/certs/httpd.crt:/etc/pki/tls/certs/httpd.crt:z
		Volume=/var/home/wavelet/config/certs/httpd.key:/etc/pki/tls/private/httpd.key:z
		Volume=/var/home/wavelet/config/php/php-fpm.d/www.conf:/usr/local/etc/php-fpm.d/www.conf:z
		Volume=/var/home/wavelet/config/php/php.ini:/etc/php.ini:z
		Volume=/var/home/wavelet/config/php/php-fpm.conf:/usr/local/etc/php-fpm.conf:z
		Volume=/var/home/wavelet/config/redis.conf:/usr/local/etc/redis/redis.conf:z
		Volume=/etc/ipa/ca.crt:/usr/local/share/ca-certificates/ca.crt
		Volume=/var/home/wavelet/http-php/log:/var/log/nginx:Z
		Volume=/var/home/wavelet/http-php/html:/var/www/html:Z
		Volume=/var/home/wavelet/http-php/nginx:/etc/nginx/conf.d/:z

		[Install]
		WantedBy=multi-user.target
	EOF
	echo -e "	The control service should be available via web browser on:\n		http://$(cat /var/home/wavelet/config/serverhostname.txt)\n"
	hostNameSys="$(hostname)"
	sed -i "s/localhost/$hostNameSys/g" "/var/home/wavelet/http-php/nginx/nginx.conf"
}

server_bootstrap(){
# Bootstraps the server processes including Apache HTTP server for distribution files, and the web interface NGINX/PHP pod
	until [[ -f "/var/ug_depends.complete" ]]; do
		sleep .1
	done
	if [[ -f "/var/home/wavelet/server_bootstrap_completed" ]]; then
		echo -e "	Server bootstrap has already been completed, exiting..\n"
		return 0
	fi
	bootstrap_http(){
		# Generate http and nginx-pod containers
		# Formerly build_http.sh
		echo "	Generating HTTPD server and copying/compressing wavelet files to server directory.."
        USER=wavelet
        setup_httpd_quadlet
        nginx_quadlets
	}
	# Generate basic ETCD roles and key permissions
	test_etcd_auth() {
		if [[ ! -f "/var/home/wavelet/config/etcd_auth.enabled" ]]; then
			sleep .1
			test_etcd_auth
		else
			echo "	Auth flag present, continuing!"
		fi
	}
	test_etcd_auth
	mkdir -p ~/.ssh/secrets
	bootstrap_http
	touch /var/home/wavelet/server_bootstrap_completed
	# Test the local environment for available codecs
	event_generate_codecEntries
	echo "	Server software configuration is now complete, generating initial server host data.."
	# Server generates host hash and userspace systemd services here
	hostHash="$(sha256sum <<<"$(cat /proc/sys/kernel/random/uuid)" | tr -d ' -')"
	echo "	Generating systemd units.."
	event_clear_devicemap
	event_generate_reflector
	event_client_control_server
	event_generate_hotplug
	event_generate_cluster_uuid
	event_orchestrator
	event_generate_network_device
	event_generate_host_monitor
	systemctl --user daemon-reload
	echo "	Starting systemd units.."
	systemctl --user start \
		http-php-pod.service \
		httpd.service
	systemctl --user start wavelet_host_monitor.timer
	# Populate server state keys, the mod condition check specifies the root key revision at 0
	# Therefore, nothing must write to the HOSTS/svr hostname key prior to this step.
	# N.B server default settings:
	# blankStatus = 1 (won't show a decoder window due to performance)
	# UIEnable = 1 (shows UI by default, this should probably be disabled by the installation engineer later to avoid chewing up a PHP worker process)
    event_checkGroups
	KEYNAME="/GROUPS/$hostNameSys"; read_etcd_global; groupHash="$printvalue"
	sleep 1
	currentVersion=0
	local newVersion=$((currentVersion + 1))
	serverIPAddress="$(<"/var/home/wavelet/config/etcd_ip")"
	# Build our initial server.conf file
	local configContent="/var/home/wavelet/config/$hostNameSys.conf"
	echo "Generating svr config file.."
	cat <<-EOF > "$configContent"
		export CLUSTER_ID="$clusterID"
		export PRIMARY_GROUPHASH="$groupHash"
		export SERVER_HOSTNAME="$hostNameSys"
		export SERVER_HOSTHASH="$hostHash"
		export CLIENT_HOSTHASH="$hostHash"
		export GROUP_HASH="$groupHash"
		export HOST_TYPE="svr"
		export HOST_IP="$serverIPAddress"
		export INPUT_DEVICE_PRESENT="0"
		export MOD_REVISION="$newVersion"
	EOF
	echo -e "Generated config:\n$(cat $configContent)"
	# export vars for utilization
	source "$configContent"
	# Calculate checksum
	local checksum=$(sha256sum <"$configContent" | tr -d ' \t\n-')
	# Encode to base64
	local encodedConfig=$(base64 -w 0 <"$configContent")
	# Atomic transaction to update config, checksum, and version
	# on the client side, the client_controller will activate on confHash being written and pull the new config
	KEYDATA="mod(\"/UI/HOSTS/$hostHash/conf\") = \"0\"

put /UI/HOSTS/$hostHash/conf \"$encodedConfig\"
put /UI/HOSTS/$hostHash/confHash \"$checksum\"

put /UI/HOSTS/$hostHash/conf \"$encodedConfig\"
put /UI/HOSTS/$hostHash/confHash \"$checksum\"

"
	write_etcd_txn "$KEYDATA" &
	KEYDATA="mod(\"/HOSTS/$hostNameSys\") = \"0\"

put /HOSTS/$hostNameSys \"$hostHash\"
put /HOSTS/$hostNameSys/control/label \"$hostNamePretty\"
put /HOSTS/$hostNameSys/control/blankStatus \"1\"
put /HOSTS/$hostNameSys/control/UIEnable \"1\"
put /HOSTS/$hostNameSys/control/rebootStatus \"0\"
put /HOSTS/$hostNameSys/control/healthStatus \"0\"
put /HOSTS/$hostNameSys/control/GROUP \"$groupHash\"
put /HOSTS/$hostNameSys/IP \"$serverIPAddress\"
put /HOSTS/$hostNameSys/type \"svr\"

"
	write_etcd_txn "$KEYDATA"
	echo "	System services and configuration keys generated, starting services now.."
	event_server
	# re-order the orchestrator so that it only starts after the server keys are fully populated.
	systemctl --user enable wavelet_orchestrator --now
	sleep 2
	KEYNAME="/HOSTS/$hostNameSys/wavelet_build_completed"; KEYVALUE="1"; write_etcd_global
	# Ensure we hit the group videoSource key once to force a videoSourceConfig refresh
	KEYNAME="/GROUPS/$groupHash/control/sourceHash"; KEYNAME="1"; write_etcd_global &
}

# This generates a wrapper and etcd watch service, defined by:
# generate_service keyToWatch moduleToRun
# Short explanation
# KEYNAME
#	This is the keyname as defined in the context of the wrapper script called by the systemd unit
#	Hence we define hostname not by systemd var %H but by the hostnamsys var in the context of system spinup
event_client_control(){
	# This multifunction module handles parsing data from the UI to the local machine
	# Relabel, blank, promote, reveal, restart, reset etc.
	"$ETCDINTERACTIONMOD" \
		generate_service \
		-key="/UI/HOSTS/$hostHash/control" \
		-module="wavelet_client_controller" \
		-additional="HOST"
}
event_client_control_server(){
	# Runs the client controller but for the entire UI prefix.
	# Because we monitor the whole UI, we can run as a superset of the client controller on the server
	"$ETCDINTERACTIONMOD" \
		generate_service \
		-key="/UI/" \
		-module="wavelet_client_controller" \
		-additional="SVR"
}
event_generate_codecEntries(){
    echo "  Determining platform capabilities and enabling codecs"
    local test_video="/var/home/wavelet/config/test_input.mp4"
    local results_file="/var/home/wavelet/config/codec_scores.csv"
    echo "Generating test video..."
    echo "Codec,Status,LogFile" > "$results_file"
    generate_test_video "$test_video"
    declare -a codecsArray=(
#        "libavcodec:encoder=ffv1" # A true lossless FFMPEG codec - can generate up to 400mb stream!
#        "libavcodec:encoder=prores_ks" # Apple's "perceptually lossless" codec
#        "libavcodec:encoder=liboapv" # Samsung's "perceptually lossless" codec, default setting "medium"
        "libavcodec:encoder=mjpeg:huffman=1:q=10:safe" # Motion JPEG (CPU)
        "libavcodec:encoder=mjpeg_qsv:safe" # Motion JPEG (GPU)
        "libavcodec:encoder=h264_qsv:gop=6:bitrate=20M" # MPEG4 (CPU)
        "libavcodec:encoder=libx265:preset=ultrafast:threads=0:safe" # HEVC fast (CPU)
        "libavcodec:encoder=libx265:preset=superfast:crf=40:threads=0:safe" # HEVC quality (CPU)
        "libavcodec:encoder=libsvt_hevc:preset=7:thread_count=0:safe" # HEVC via libSVT (CPU)
        "libavcodec:encoder=libsvt_hevc:preset=6:pred_struct=0:safe" # HEVC via libSVT (CPU)
        "libavcodec:encoder=hevc_qsv:async_depth=4:safe" # HEVC (GPU) via QuickSync
        "libavcodec:encoder=hevc_vaapi:low_power=1:safe" # HEVC (GPU) via VA-API
        "libavcodec:encoder=libvpx-vp9:safe" # Google VP9 (CPU)
        "libavcodec:encoder=vp9_qsv:safe" # Google VP9 (GPU) via QuickSync
        "libavcodec:encoder=av1_qsv:safe" # AV1 (GPU) via QuickSync
        "libavcodec:encoder=libaom-av1:usage=realtime:cpu-used=8:safe" # AV1 via libaom (CPU) default
        "libavcodec:encoder=libsvtav1:preset=12" # AV1 (CPU) via libSVT
    )

    LOG_DIR="codec_logs"
    mkdir -p "$LOG_DIR"
    for codecCmd in "${codecsArray[@]}"; do
    	local codec_name; local encoded_video; local bitrate; local fps; local status; local log_file
        # Kill any pre-existing UltraGrid processes
        pkill uv
        codec_name=$(echo "$codecCmd" | cut -d'=' -f2 | cut -d':' -f1)
        encoded_video="/var/home/wavelet/config/${codec_name}_output.mp4"
        bitrate="N/A"
        fps="N/A"
        status="FAILED"
        echo -e "\nTesting codec: $codec_name"
        if output=$(test_with_ug "$test_video" "$codecCmd" "$encoded_video" "$codec_name"); then
            fps=$(echo "$output" | cut -d',' -f1 | cut -d':' -f2)
            bitrate=$(echo "$output" | cut -d',' -f2 | cut -d':' -f2)
            status="SUCCESS"
            case "$codec_name" in
#                "ffv1")           	KEYVALUE="$codecCmd;FFMPEG FFV1.  High bandwidth, high quality, lossless";;
                "prores")         	KEYVALUE="$codecCmd;Apple prores. High bandwidth, high quality, lossy.  Supports 4444+ colorspace";;
                "apv")            	KEYVALUE="$codecCmd;Samsung APV. High bandwidth, high quality, 'Perceptually Lossless'";;
                "mjpeg" )           KEYVALUE="$codecCmd;MPEG2 Motion-JPEG High bandwidth, high quality (DVD)";;
                "mjpeg_qsv:safe")   KEYVALUE="$codecCmd;MPEG2 Motion-JPEG HW Accelerated High bandwidth, high quality (DVD), compatibility may be an issue";;
                "h264_qsv")         KEYVALUE="$codecCmd;H.264 MPEG4, Low bandwidth, high compatibility, low quality (slightly worse than Youtube)";;
                "libx265")          KEYVALUE="$codecCmd;H.265 'HEVC', Low bandwidth, Good quality, hard on host.  CPU encoding";;
                "libsvt_hevc")      KEYVALUE="$codecCmd;H.265 'HEVC' via libSVT, Low bandwidth, Good quality, hard on host.  CPU encoding via Intel's libSVT";;
                "hevc_qsv")         KEYVALUE="$codecCmd;H.265 'HEVC', Low bandwidth, Good quality, hard on host.  HW Accelerated encoding via Intel QuickSync, compatibility may be an issue";;
                "hevc_vaapi")       KEYVALUE="$codecCmd;H.265 'HEVC', Low bandwidth, Good quality, hard on host.  HW Accelerated encoding via Intel VA-API, compatibility may be an issue";;
                "libvpx-vp9")       KEYVALUE="$codecCmd;Google VP9, Low bandwidth, Good quality, hard on host. Youtube quality.";;
                "vp9_qsv")          KEYVALUE="$codecCmd;Google VP9, Low bandwidth, Good quality, hard on host. Youtube quality via Intel QuickSync, compatibility may be an issue";;
                "av1_qsv")          KEYVALUE="$codecCmd;Alliance for Open Media AV1, Low bandwidth, High quality, very hard on host. Superior to VP9 and HEVC in most respects.  HW Accelerated encoding via Intel QuickSync";;
                "libaom-av1")       KEYVALUE="$codecCmd;Alliance for Open Media AV1, Low bandwidth, High quality, very hard on host. Superior to VP9 and HEVC in most respects.  CPU encoding via libAOM";;
                "libsvtav1")        KEYVALUE="$codecCmd;Alliance for Open Media AV1, Low bandwidth, High quality, very hard on host. Superior to VP9 and HEVC in most respects.  CPU encoding via Intel's libSVT";;
            esac
            KEYNAME="/UI/GLOBALS/CODECS/$codec_name"; write_etcd_global &
            # We might not use this but I am going to add it here for quick reference
            KEYNAME="/SYS/$codec_name"; KEYVALUE="$codecCmd"; write_etcd_global
        else
            echo "Failed to encode with $codecCmd"
            echo "OUTPUT LOG:"
            echo "$output"
            status="FAILED"
        fi
        log_file="$LOG_DIR/${codec_name}_log.txt"
        echo "$output" > "$log_file"
		echo "$codecCmd,$status,$log_file,$ssim_score,$vmaf_score" >> "$results_file"
    done
    echo "Codec testing complete. Results in $results_file"
}
generate_test_video() {
    local output="$1"
    echo "Running: ffmpeg -f lavfi -i testsrc=size=1920x1080:rate=60 -t 5 -c:v png -pix_fmt rgb24 $output"
    ffmpeg -y -f lavfi -i testsrc=size=1920x1080:rate=60 -t 5 -c:v png -pix_fmt rgb24 "$output"
}

test_with_ug() {
	local input; local codec_config; local output_file; local codec_name; local temp_log;
	local command; local ug_pid; local qualityResult; local timeout; local start_time
    input="$1"
    codec_config="$2"
    output_file="$3"
    codec_name="$4"
    temp_log=$(mktemp)
    command="$ULTRAGRID_APPRUN --tool uv -t file:$input -c $codec_config -d file:name=$output_file localhost"
    echo "	Running: $command"
    $command > "$temp_log" 2>&1 &
    ug_pid=$!
    UG_PIDS+=("$ug_pid")
    qualityResult=0
    timeout=15
    start_time=$(date +%s)
    while kill -0 $ug_pid 2>/dev/null; do
    	local elapsed
        sleep .5
        elapsed=$(($(date +%s) - start_time))
        if [ $elapsed -ge $timeout ]; then
            echo "	Timeout reached, killing UltraGrid process"
            kill -9 $ug_pid
            wait $ug_pid 2>/dev/null
            echo "	UltraGrid timed out (300 Frames, 15 Seconds = 20FPS, too slow for our purposes)"
            return 1
        fi
        if grep -q "Playback ended." "$temp_log"; then
        	echo "	UG Task reached end of playback"
        	kill -9 $ug_pid 2>/dev/null
        fi
    done
    wait $ug_pid 2>/dev/null
    # Check for FATAL errors only
    if grep -q "Could not open codec for pixel format" "$temp_log" ||
       grep -q "Requested parameters not supported" "$temp_log" ||
       grep -q "Warning: requested encoder" "$temp_log" ||
       grep -q "Unable to initialize" "$temp_log"; then
        echo "UltraGrid encountered fatal errors"
        cat "$temp_log"
        return 1
    fi
    # Check if playback completed AND output file exists
    if grep -q "Playback ended." "$temp_log" && [[ -f "$output_file" && -s "$output_file" ]]; then
    	local fps; local bitrate
        fps=$(grep "frames in" "$temp_log" | tail -1 | sed -E 's/.* ([0-9.]+) FPS.*/\1/' || echo "N/A")
        bitrate=$(grep "Setting bitrate" "$temp_log" | sed -E 's/.* ([0-9.]+) Mbps.*/\1/' || echo "N/A")
        echo "FPS:$fps,Bitrate:$bitrate"
        cat "$temp_log"
        # Run quality tests
        if [[ "$vmafTesting" == 1 ]]; then
		  vmaf_score="N/A"
          vmaf_score=$(runVMAFtest "$input" "$output_file")
        fi
        if [[ "$ssimTesting" == 1 ]]; then
          ssim_score="N/A"
          ssim_score=$(runSSIMtest "$input" "$output_file")
        fi
        if [[ $qualityResult == 0 ]]; then
          return 0
        else
          echo "  SSIM or VMAF testing for this codec failed the required quality threshold. Disqualifying codec."
          return 1
        fi
    else
        echo "UltraGrid failed to complete or produce output"
        cat "$temp_log"
        return 1
    fi
}
runSSIMtest(){
	local test_video; local encoded_video; local ssim_log
	test_video="$1"
	encoded_video="$2"
	ssim_log="$(mktemp)"
	echo "Testing SSIM: ffmpeg -y -i $test_video -i $encoded_video -filter_complex \"[0:v][1:v]ssim=stats_file=$ssim_log\" -f null /dev/null"
	ffmpeg -y -i "$test_video" -i "$encoded_video" -filter_complex "[0:v][1:v]ssim=stats_file=$ssim_log" -f null - 2>&1 | tee "${ssim_log}.ffmpeg.log"
	if [ "${PIPESTATUS[0]}" -eq 0 ]; then
    	# SSIM outputs per-frame data; extract the All value from the last line
    	ssim_avg=$(tail -n 1 "$ssim_log" | awk '{print $(NF-1)}' | cut -d':' -f2 | tr -d ' ()')
	if [ -z "$ssim_avg" ]; then
		echo "SSIM average not found in log file. Checking ffmpeg output..."
		# Try to extract from ffmpeg stderr output instead
		ssim_avg=$(grep -i "All:" "${ssim_log}.ffmpeg.log" | tail -n 1 | awk '{print $(NF-1)}')
    fi
	if [ -z "$ssim_avg" ] || [ "$ssim_avg" = "inf" ]; then
		echo "SSIM average not found or invalid. Marking as failed."
		status="FAILED"
	else
		echo "SSIM average: $ssim_avg"
		if (( $(echo "$ssim_avg < 0.90" | bc -l) )); then
			echo "SSIM average ($ssim_avg) below threshold (0.90). Marking as VISUAL_FAILED."
        	status="VISUAL_FAILED"
		fi
	fi
	if [[ $status == *"FAILED"* ]]; then
      qualityResult=1
    fi
  else
    echo "SSIM computation failed!"
    qualityResult=1
  fi
  rm -f "${ssim_log}.ffmpeg.log"
  echo "$ssim_avg"
}
runVMAFtest(){
	local test_video; local encoded_video; local vmaf_log
	test_video="$1"
	encoded_video="$2"
	vmaf_log="$(mktemp --suffix=.json)"
	# for VMAF testing, the distorted or encoded video must be input first!
	echo "Testing VMAF: ffmpeg -y -i $encoded_video -i $test_video -filter_complex \"[0:v]setpts=PTS-STARTPTS[dist];[1:v]setpts=PTS-STARTPTS[ref];[dist][ref]libvmaf=log_path=$vmaf_log:log_fmt=json\" -f null /dev/null"
	ffmpeg -y -i "$encoded_video" -i "$test_video" -filter_complex "[0:v]setpts=PTS-STARTPTS[dist];[1:v]setpts=PTS-STARTPTS[ref];[dist][ref]libvmaf=log_path=$vmaf_log:log_fmt=json" -f null - 2>&1 | tee "${vmaf_log}.ffmpeg.log"
	if [ "${PIPESTATUS[0]}" -eq 0 ]; then
    	# VMAF outputs JSON format, extract the mean score
    	if command -v jq &> /dev/null; then
			vmaf_avg=$(jq -r '.pooled_metrics.vmaf.mean' "$vmaf_log" 2>/dev/null)
    	else
			# Fallback without jq
			vmaf_avg=$(grep -oP '"mean":\s*\K[0-9.]+' "$vmaf_log" | head -n 1)
		fi
		if [ -z "$vmaf_avg" ] || [ "$vmaf_avg" = "null" ]; then
			echo "VMAF average not found. Marking as failed."
			status="FAILED"
		else
			echo "VMAF average: $vmaf_avg"
			if (( $(echo "$vmaf_avg < 85" | bc -l) )); then
				echo "VMAF average ($vmaf_avg) below threshold (85). Marking as VISUAL_FAILED."
				status="VISUAL_FAILED"
			fi
		fi
		if [[ $status == *"FAILED"* ]]; then
			qualityResult=1
		fi
	else
    	echo "VMAF computation failed!"
    	cat "${vmaf_log}.ffmpeg.log"
    	qualityResult=1
	fi
	rm -f "${vmaf_log}.ffmpeg.log"
	echo "$vmaf_avg"
}
event_audio_bluetooth_connect(){
	# Server only
	if [[ -f "/var/home/wavelet/.config/systemd/user/wavelet_bluetooth_audio.service" ]]; then
		echo "	Unit file already generated, moving on"
		:
	else
		echo "	Unit file does not exist, generating.."
		# Monitors the bluetooth MAC value and updates the system if there's a change
		"$ETCDINTERACTIONMOD" \
			generate_service \
			-key="/UI/audio/audio_interface_bluetooth_mac" \
			-module="wavelet_set_bluetooth_connect"
		echo -e "	Generating Reboot SystemdD unit in /.config/systemd/user.."
	fi
}
event_orchestrator(){
	# The orchestrator watches host keys and updates the UI with state changes
	# Server only
	# Note this will fire for every host key state change!
	"$ETCDINTERACTIONMOD" \
		generate_service \
		-key="/HOSTS/" \
		-module="wavelet_orchestrator"
}
event_generate_reflector(){
	if [[ -f "/var/home/wavelet/.config/systemd/wavelet_reflector.service" ]]; then
		echo "	Unit file already generated, moving on"
		:
	else
		echo "	Unit file does not exist, generating.."
		# Generate userspace reflector service
		"$ETCDINTERACTIONMOD" \
			generate_service \
			-key="/HOSTS/$hostNameSys/DECODER_SUB_LIST" \
			-module="wavelet_reflector"
	fi
}
event_generate_hotplug(){
	# Templates for UDEV usb hotplug service.
	# Calls detectv4l from root (saves a lot of effort compared to old method)
	cat > "/var/home/wavelet/.config/systemd/user/wavelet_detectv4l@.service" <<-EOF
		[Unit]
		Description=USB Detection for %i

		[Service]
		RemainAfterExit=yes
		Type=oneshot
		TimeoutStartSec=5
		ExecStart=${WAVELET_DETECTV4L_MOD} add %I
		EOF
	# Called after udev has invoked detectv4l directly via machinectl from root
	# runs in the wavelet userland
	cat > "/var/home/wavelet/.config/systemd/user/wavelet_v4l_delete@.service" <<-EOF
		[Unit]
		Description=USB Removal for %i

		[Service]
		RemainAfterExit=no
		Type=oneshot
		TimeoutStartSec=5
		ExecStart=${WAVELET_DETECTV4L_MOD} delete %I

		[Install]
		WantedBy=default.target
		EOF
}
event_generate_host_monitor(){
	# Templates for Device health monitoring.  Each host gets one.
	if [[ -f "/var/home/wavelet/.config/systemd/user/wavelet_host_monitor.service" ]]; then
		echo "	Unit file already generated, moving on."
	else
		local targetFile
		if [[ -f "/var/wavelet_ramfs/wavelet_host_monitor.sh" ]]; then
        	targetFile="/var/wavelet_ramfs/wavelet_host_monitor.sh"
        else
        	targetFile="/usr/local/bin/wavelet_host_monitor.sh"
        fi
		cat > "/var/home/wavelet/.config/systemd/user/wavelet_host_monitor.service" <<-EOF
			[Unit]
			Description=Runs a sweep of available hosts for network health

			[Service]
			RemainAfterExit=no
			Type=oneshot
			TimeoutStartSec=20
			ExecStart=${targetFile}

			[Install]
			WantedBy=default.target
			EOF
		cat > "/var/home/wavelet/.config/systemd/user/wavelet_host_monitor.timer" <<-EOF
			[Unit]
			Description=Timer for ping monitor

			[Timer]
			OnCalendar=*:0/10
			Persistent=true

			[Install]
			WantedBy=timers.target
			EOF
	fi

}
event_generate_network_device(){
	# Process DHCP key writes from the Kea container
	if [[ -f "/var/home/wavelet/.config/systemd/user/wavelet_network_device.service" ]]; then
		echo "	Unit file already generated, moving on."
	else
		echo "	Unit file does not exist, generating.."
        # Generate the actual network_device.service, which utilizes the same module as referenced above
		"$ETCDINTERACTIONMOD" generate_service -key="/DHCP" -module="wavelet_network_device"
	fi
}
event_generate_cluster_uuid() {
	# Generates a cluster UUID and ensures this cluster knows the server hostname
	KEYNAME="CLUSTERID"; KEYVALUE="$(cat /proc/sys/kernel/random/uuid)"; write_etcd_global &
	clusterID="$KEYVALUE"
	KEYNAME="/UI/GLOBALS/control/CLUSTERID"; write_etcd_global &
	KEYNAME="SVR"; KEYVALUE="$(hostname)"; write_etcd_global &
}
event_clear_devicemap(){
	# Clears the device map file so it will be regenerated.  Since the paths under v4l2 aren't stable,
	# we need to do this to avoid the channel indexing becoming incorrect
	rm -rf "/var/home/wavelet/device_map"
	echo "	Device map file removed, will be regenerated on input device selection."
}
event_checkGroups(){
	# Launched only from the server upon initial bootrap
	# Provides a key in /GROUPS/$hostNameSys for clients to find the primary group.
	echo "	Executing etcd txn.  This will only work if a group does not already exist."
	# Generate a new group with basic settings and server group as source.
	# A Group typically associates an encoder or a server with a group of decoders, allowing for multiple sources and clients to run simultaneously
	# Groups also contain organization-level toggles
	# /GROUPS/$hash/reflectorTarget                     =	the reflector hostname/IP of that host (controller assigns this)
	# /UI/GROUPS/$hash 		                            =	the UI entry for the group
	# /UI/GROUPS/groupControl/$groupHash/control/       =	the control keys for this group;
	#   /audioStatus                                    =   controls audio on/off for that group
	#   /bannerStatus                                   =   controls the generation of a transparent banner on that encoder
	#	/blankStatus		                            =	the blank status of all clients + encoders
	#   /livestreamStatu                                =   controls whether the encoder will send an RTP stream to specified URL
	#   /inputPersist                                   =   controls the input persistence across reboots
	#   /isPrimary                                      =   tells us this is the primary group and cannot be deleted.
	#	/reboot			                                =	cold restart on every host in the group
	#	/reboot			                                =	resets all heavy processes on the group hosts without cold reboot
	#	/reveal			                                =	the reveal status of all clients + encoder
	#   /sourceHash    		                            =	the group's active video source (can be another group WITH a video source)
	#   /activeCodec   		                            =	the group's active video codec
	#   /bannercontent                                  =	text content for the banner
	#	If activated, they overwrite the group member control settings to their value.
	# Populate server state keys if /UI/GROUPS has never had a write event.
	groupHash="$(sha256sum <<<"$hostNameSys" | tr -d ' \t\n-')"
	BASEKEYNAME="/UI/GROUPS/$groupHash"
	KEYDATA="mod(\"/UI/GROUPS/\") = \"0\"

put $BASEKEYNAME/control/audioStatus \"0\"
put $BASEKEYNAME/control/activeCodec \"libaom-av1\"
put $BASEKEYNAME/control/bannerStatus \"0\"
put $BASEKEYNAME/control/blankStatus \"0\"
put $BASEKEYNAME/control/chainedToGroup \"\"
put $BASEKEYNAME/control/isPrimary \"1\"
put $BASEKEYNAME/control/label \"SVR (Primary group)\"
put $BASEKEYNAME/control/reboot \"0\"
put $BASEKEYNAME/control/reset \"0\"
put $BASEKEYNAME/control/revealStatus \"0\"
put $BASEKEYNAME/control/sourceHash \"0\"
put $BASEKEYNAME/control/sourceCapable \"1\"
put $BASEKEYNAME/control/livestreamStatus \"0\"
put $BASEKEYNAME/control/inputPersist \"0\"
put /GROUPS/$hostNameSys \"$groupHash\"
put /HOSTS/$hostNameSys/control/GROUP \"$groupHash\"
put /UI/GLOBALS/control/lowInformationMode \"0\"

"
	echo "	Data: "
	echo "$KEYDATA"
	write_etcd_txn "$KEYDATA"
}
check_clientGroupMemberShip(){
	# Clients only
	# Checks for group memberships and adds self to server group if nothing is available.
	echo "	Determining client's group membership.."
	KEYNAME="/HOSTS/$hostNameSys/control/GROUP"; read_etcd_global
	KEYVALUE=""
	local groups=()
	if [[ -z "$printvalue" ]]; then
		echo "	Group membership is empty, locating primary group hash.."
		# Get the server's group hash by detecting /control/isPrimary -- 1
		KEYNAME="/UI/GROUPS/"
		read_etcd_prefix_keys
		while IFS= read -r line; do
			if [[ $line == *"/control/isPrimary" ]]; then
				groupEntry="$line"
				groups+=("$groupEntry")
			fi
		done <<<"$printvalue"
		# Look for isPrimary key and value of 1
		for groupEntry in "${groups[@]}"; do
			KEYNAME="$groupEntry"; read_etcd_global
			if [[ "$printvalue" == "1" ]]; then
				groupHash="${groupEntry#*/UI/GROUPS/}"
				groupHash="${groupHash%%/*}"
				KEYVALUE="$groupHash"
			else
				echo "	ERROR:  Cannot successfully determine the primary group!"
				exit 1
			fi
		done
	else
		echo "	Host grouphash is not null, value is: $printvalue"
		groupHash="$printvalue" # should be available further along in the calling function
		KEYVALUE="$printvalue"
	fi
	# Either way, we write our group membership update key
	if [[ -z "$KEYVALUE" ]]; then
		echo "	Group hash is still null, exiting with failure"
		exit 1
	fi
	echo "	Writing found primary group hash: $KEYVALUE"
	KEYNAME="/HOSTS/$hostNameSys/control/GROUP"; write_etcd_global &
	# Orchestrator should take it from here, and register us in /GROUPS/ and /UI/group/ etc.
}
ping_server(){
	if ping -c 1 -w 1 "$(cat /var/home/wavelet/config/etcd_ip)"; then
		connected=true
	else
		(( attempts++ ))
		connected=false
		echo "Ping to server failed, attempting to bring up connection again, attempt: $attempts"
		nmcli con up "$wifiSSID"
	fi
}
event_connectNetwork(){
	ethernetCIDRValue=""; wirelessCIDRValue=""; ipValue=""
	while read -r line; do
		case "$line" in
			*802-3-ethernet*)
				ethernetCIDRValue="$(nmcli -g IP4.ADDRESS con show "${line%%:*}")"
				ethernetUUID="${line##*:}"
				ipValue="${ethernetCIDRValue%/*}"
				;;
			*802-11-wireless*)
				wirelessCIDRValue="$(nmcli -g IP4.ADDRESS con show "${line%%:*}")"
				wirelessUUID="${line##*:}"
				ipValue="${wirelessCIDRValue%/*}"
				;;
		esac
	done < <(nmcli -t -f NAME,TYPE,UUID con show --active)
	# Attempts to list and connect a wavelet Wi-Fi connection
	# Note that the wavelet user has NetworkManager permissions via configured polkit rules
	if [[ -f "/var/no.wifi" ]]; then
		echo "	Wi-FI has been disabled for this host.  Remove /var/no.wifi to enable this feature."
		return 0
	else
		# Disable ethernet
		echo "	Disabling ethernet connectivity: "
		nmcli con show "$ethernetUUID"
		nmcli con down "$ethernetUUID"
		nmcli con mod "$ethernetUUID" connection.autoconnect no
		echo "	The primary ethernet connection with UUID $ethernetUUID has been disabled."
		echo -e "  To re-enable, you can use:\nnmcli con up $ethernetUUID\nOr:\nnmtui\nFor a gui interface."
		nmcli devi wifi rescan
		if [[ "$hostNameSys" = *"svr."* ]]; then
			echo -e "	If you want to run the server via a WiFi connection, this should be configured and enabled manually via nmtui or nmcli."
			echo -e "	Performance will likely suffer as a result."
			exit 0
		fi
	fi

	wifiSSID="$(cat /var/home/wavelet/config/wifi_ssid)"
	if [[ -n "$wirelessUUID" ]]; then
		echo "	Found WiFi connection, proceeding.."
	else
		echo "	Missing WiFi connection!  connectwifi.sh should have configured this on client bootstrap."
		exit 0
	fi

	# Check if we already have an active Wi-Fi connection (avoid unnecessary cycling)
	nmcli con up "$wirelessUUID"
	attempts=0
	until [[ attempts -gt 128 ]]; do
		ping_server
		if [[ "$connected" == true ]]; then
			break
		fi
	done
	if [[ "$connected" == false ]]; then
		echo "	ERROR: Enterprise connection failed after 128 attempts, rebooting client."
		systemctl -i reboot
	fi
	echo "	WiFi connection established successfully."
	# We should now have a single, stable connection available for this client
    if valid_ipv4 "$ipValue"; then
    	echo -e "			IP Address is valid: $ipValue, continuing.."
    	KEYNAME="/HOSTS/$hostNameSys/IP"; KEYVALUE="$ipValue"; write_etcd_global &
    else
    	echo -e "			IP Address '$ipValue' is not valid, retrying...\n"
    	sleep .25
    fi
}


#####
#
# Main
#
#####


# Set these flags to disable codec quality tests
# This can save some time on spinup if we are familiar with the deployment hw

vmafTesting=0
ssimTesting=0

start_timer
trap 'stop_timer "$timer_id_out"; echo "Total: ${timer_duration}s" >&2' EXIT

hostNameSys="$(hostname)"
hostNamePretty="$(hostnamectl --pretty)"
# Check for pre-existing log file
logName=/var/home/wavelet/logs/wavelet_build.log
#if [[ -e $logName || -L $logName ]] ; then
#	i=0
#	while [[ -e $logName-$i || -L $logName-$i ]] ; do
#		(( i++ ))
#	done
#	logName=$logName-$i
#fi

exec >> "${logName}" 2>&1

detect_self