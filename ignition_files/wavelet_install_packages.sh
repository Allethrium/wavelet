#!/bin/bash
# Runs RPM-OStree overlay to install the package layer and extract/generate any wavelet-specific settings and files.
# Should be one of the first things to run on initial boot in place of a more commonly used direct systemd unit.
# All wavelet modules are deployed on all devices from the tarball

# If a server, we go on to wavelet_install_services
# If a client, we go on to wavelet_install_client

RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"

detect_self(){
	# This might be of use if we need some custom kernels or decide to start building addition ostree overlays
	# platform=$(dmidecode | grep "Manufacturer" | cut -d ':' -f 2 | head -n 1)
	echo "Hostname is $hostNameSys"
	case "$hostNameSys" in
		dec*)
			echo -e "I am a client \n" && echo -e "Provisioning system as a wavelet client.."
			event_decoder
			;;
		svr*)
			echo -e "I am a Server. Proceeding..."
			event_server
			;;
		*)
			echo -e "This device Hostname is not set appropriately, exiting \n" && exit 0
			;;
	esac
}

event_decoder(){
	# First we'd need to determine our architecture.
	event_clientHostName
	arch="$(uname -m)"
	case "$arch" in
		"x86_64")
			echo -e "AMD64 architecture, running base install..\n"
			rpm_overlay_install_client
			;;
		"aarch64")
			echo -e "aarch64 architecture, switching to ARM ostree.."
			rpm_ostree_ARM
			;;
		"riscv64")
			echo -e "RISC-V architecture, switching to RISCV ostree.."
			rpm_ostree_RISCV
			;;
		*)
			echo -e "Architecture unsupported, exiting..\n"
			;;
	esac
}

event_clientHostName(){
	if [[ "$(hostname)" == "decX.$(dnsdomainname)" ]]; then
		echo -e "	I am a Decoder, and my hostname needs to be randomized. \n"
	else
		echo -e "	This device Hostname is not set appropriately, exiting \n"
		exit 0
	fi
	echo "	Setting decoder hostname as well as 'Pretty' label to the same value."
	echo "	The Pretty label will be utilized on the webUI and may change."
	echo "	The stable hostname is for domain enrollment, and should remain stable after initial configuration."
	newhostname="dec$(tr -dc 'a-z0-9' < /dev/urandom | head -c 4).wavelet.allethrium"
	hostnamectl hostname "$newhostname"
	hostnamectl --pretty hostname "$newhostname"
}

set_ethernet_mtu(){
	# Jumbo packets for faster file transfer
	for interface in $(nmcli con show | grep ethernet | awk '{print $3}'); do
			nmcli con mod "$interface" mtu 9000
	done
}

event_server(){
	# generate proper RC files for root/wavelet-root which gives us aliases and powerline
	cd "/root" || return; rm .bashrc .bash_profile; cp /etc/skel/{.bashrc,.bash_profile} .
	cd "/var/home/wavelet-root" || return; rm .bashrc .bash_profile; cp /etc/skel/{.bashrc,.bash_profile} .
	# Server can only be x86.
	# I haven't had access to another platform with video hardware support + enough number crunching power to do the task.
	# Get, or generate RPM overlay
	# Set my pretty hostname
	hostnamectl set-hostname "$(hostname)" --pretty

	# Make etcd datadir and copy nonsecure yaml to conf file, and update with server IP address.
	mkdir -p "/var/lib/etcd-data"
	# Enable config
	echo "${SVR_IP:-$(hostname -I | xargs)}" > "/var/home/wavelet/config/etcd_ip"
	# Generate and enable systemd units
	# Therefore, they will start on next boot, run, and disable themselves
	cat > "/etc/systemd/system/wavelet_install_services.service" <<-EOF
		[Unit]
		Description=Install Server additional services
		After=multi-user.target

		[Service]
		Type=oneshot
		ExecStart=/usr/bin/bash -c '/usr/local/bin/wavelet_install_services.sh'
		ExecStartPost=systemctl disable wavelet_install_services.service

		[Install]
		WantedBy=multi-user.target
	EOF
		echo -e "Generating systemd unit for security layer.."
	cat > "/etc/systemd/system/wavelet_install_hardening.service" <<-EOF
		[Unit]
		Description=Install Security Layer
		After=multi-user.target

		[Service]
		Type=oneshot
		ExecStart=/usr/bin/bash -c '/usr/local/bin/wavelet_install_hardening.sh'
		ExecStartPost=systemctl disable wavelet_install_hardening.service

		[Install]
		WantedBy=multi-user.target
	EOF
	# RPM Ostree and container infra setup
	# We will check for an external registry first, and build local images only if it does not exist.
	echo "OCI Container image setup"
	# First we check and generate our registry value
	check_registry
	setup_registry_quadlet
	pull_registry_images
	# Pull these images in serial as they are heavy
	pull_overlay "coreos_overlay_client" --tls-verify=false
	podman tag coreos_overlay_client:latest "$hostNameSys/coreos_overlay_client"
	podman push --tls-verify=false "$hostNameSys/coreos_overlay_client" "$hostNameSys:5000/coreos_overlay_client"
	rpm_overlay_install_server
	# wavelet_pxe_install.service will complete the root portion of the server spinup
	systemctl enable wavelet_install_services.service
	# Remove nameserver karg if it exists
	if rpm-ostree kargs | grep -q 'nameserver'; then
	  rpm-ostree kargs --delete nameserver
	fi
	local waveletFiles_sha512
	# Perform some other server-specific tasks:
	# Copy wavelet_files to the webserver and generate the expected sha512 hash value.
	# Determine tarball filename from git branch
	local packageTarball
	if [[ "$DEVELOPER_MODE" -eq 1 ]]; then
		packageTarball="armelvil-working.tar.gz"
	else
		packageTarball="master.tar.gz"
	fi
	# Destination is always wavelet_files.tar.gz
	cp "/var/$packageTarball" "/var/home/wavelet/http/ignition/wavelet_files.tar.gz"
	cp "/usr/local/bin/wavelet_install_packages.sh" "/var/home/wavelet/http/ignition/"
	waveletFiles_sha512="$(sha512sum <"/var/home/wavelet/http/ignition/wavelet_files.tar.gz" | cut -d ' ' -f 1)"
	echo "$waveletFiles_sha512" > /var/secrets/waveletFiles_sha512.txt
	# Ensure only root and wavelet-root can read the secrets dir
	chown -R root:wavelet-root /var/secrets
	chmod 0750 /var/secrets; chmod 0640 /var/secrets/*
	set_ethernet_mtu
	echo "Installation completed, restarting server.."
	systemctl reboot -f
}

setup_registry_quadlet(){
	# This sets up our local wavelet server registry
	cat > "/etc/containers/systemd/registry.container" <<-EOF
		[Unit]
        Description=Wavelet container registry
		After=network-online.target
		Wants=network-online.target

		[Container]
		ContainerName=registry
		Image=registry
		AutoUpdate=local
		Network=host
		Environment=REGISTRY_LOG_LEVEL=info
		Environment=OTEL_TRACES_EXPORTER=none
		Volume=/var/containers/registry:/var/lib/registry/:z

		[Service]
		Restart=always

		[Install]
		WantedBy=multi-user.target
	EOF
	mkdir -p /var/containers/registry
	systemctl daemon-reload && systemctl start registry.service
	sleep 5
	if curl -s "http://$(hostname):5000/v2"; then
		echo "Registry running, continuing.."
	else
		echo "Registry down!  Cannot continue!"
		exit 1
	fi
}

check_registry(){
	# Do we have an external registry or no?
	# Note we are not using a secured registry until IPA is configured!
	# Registry IP comes from the conf file (DEPLOYMENT_REGISTRY or REGISTRY)
	registry="${DEPLOYMENT_REGISTRY:-${REGISTRY}}"
	if [[ -z "$registry" ]]; then
		echo "ERROR: Registry IP not set in config file!"
		exit 1
	fi
	if [[ "$registry" != "$(hostname -i)" ]]; then
		echo "Registry IP and server IP does not match!"
		# We can now use bootc, defining the lan or server registries.
		cat > /etc/containers/registries.conf.d/11-lan.conf <<- EOF
			[[registry]]
			prefix = "lan.$(dnsdomainname)"
			location = "${registry}:5000"
			gpg-verify = false
			insecure = true
		EOF
		cat > /etc/containers/registries.conf.d/10-wavelet.conf <<- EOF
			[[registry]]
			prefix = "svr.$(dnsdomainname)"
			location = "${registry}:5000"
			insecure = true
		EOF
		oci_registry="lan.$(dnsdomainname)"
		externalReg=1
		# It is easier to perform the registry podman pull here to save us an if test
		podman pull --tls-verify=false "$oci_registry/registry"
		echo "Pulling OCI client image from external registry to local registry, oci_registry set to: $oci_registry"
		echo "Container images will be pulled from external registry"
	else
		oci_registry="svr.$(dnsdomainname)"
		externalReg=0
		podman pull "docker.io/library/registry"
		echo "Registry IP and server IP match, generating OCI images locally, oci_registry set to: $oci_registry"
		echo "Container images will be pulled from internet."
		count=0
		DKMS_KERNEL_VERSION=$(uname -r)
		# Export implied in build function
		build_container_image "coreos_overlay_client" "Containerfile.coreos.overlay.client"
		build_container_image "coreos_overlay_server" "Containerfile.coreos.overlay.server"
	fi
}

pull_registry_images() {
  # Sets vars for appropriate package sources and places them in the wavelet server's local registry
  # In my lab environment, I setup a local registry that updates and tags everything with a cronjob
  # The process saves bandwidth and having to download gbs of container images every test
  local max_parallel=4
  local counter=0
  local timeout=180  # 3 minute timeout for each operation
  local max_retries=2  # 1 retry before failing
  local sourceList=()
  if [[ "$externalReg" == "0" ]]; then
    echo "Pulling container images from internet sources.."
    local tls=""
    sourceList+=("quay.io/coreos/etcd:v3.6.4")
    sourceList+=("quay.io/coreos/coreos-installer:release")
    sourceList+=("registry.fedoraproject.org/fedora:latest")
    sourceList+=("docker.io/library/nginx:alpine")
    sourceList+=("docker.io/library/php:fpm")
    sourceList+=("docker.io/library/redis:latest")
    sourceList+=("docker.io/library/httpd")
    sourceList+=("quay.io/freeipa/freeipa-server:almalinux-10")
    sourceList+=("registry.fedoraproject.org/fedora:42")
  else
    echo "An external registry is configured! Pulling sources from: $oci_registry"
    local tls="--tls-verify=false"
    sourceList+=("${oci_registry}/etcd:latest")
    sourceList+=("${oci_registry}/coreos-installer:latest")
    sourceList+=("${oci_registry}/fedora:latest")
    sourceList+=("${oci_registry}/nginx:latest")
    sourceList+=("${oci_registry}/php-fpm-redis:latest") # PHP-FPM customized with redis package
    sourceList+=("${oci_registry}/redis:latest")
    sourceList+=("${oci_registry}/httpd:latest")
    sourceList+=("${oci_registry}/tftpboot")
    sourceList+=("${oci_registry}/isc-kea")
    sourceList+=("${oci_registry}/tftpd")
    sourceList+=("${oci_registry}/freeipa-server")
    sourceList+=("${oci_registry}/radiusd")
  fi

  for source in "${sourceList[@]}"; do
    (
      echo "Starting pull for $source"
      local retry=1
      while (( retry <= max_retries )); do
        if timeout $timeout podman pull "$tls" "$source"; then
          break
        fi
        echo "Pull attempt $retry failed for $source. Retrying in 5 seconds..."
        sleep 5
        retry=$((retry + 1))
      done
      if (( retry > max_retries )); then
        echo "ERROR: Failed to pull $source after $max_retries attempts"
        exit 1
      fi
      shortSource="${source##*/}"
      echo "Pushing container $source to $hostNameSys:5000/${shortSource%%:*}"
      retry=1
      while (( retry <= max_retries )); do
        if timeout $timeout podman push --tls-verify=false "$source" "$hostNameSys:5000/${shortSource%%:*}"; then
          break
        fi
        echo "Push attempt $retry failed for $hostNameSys/${shortSource%%:*}. Retrying in 5 seconds..."
        sleep 5
        retry=$((retry + 1))
      done
      if (( retry > max_retries )); then
        echo "ERROR: Failed to push $source after $max_retries attempts"
        exit 1
      fi
    ) &
    counter=$((counter + 1))
    if (( counter % max_parallel == 0 )); then
      wait
    fi
  done
  wait
}

build_container_image(){
	local imageTarget="$1"
	local containerFile="$2"
	local env="$3"
	echo -e "\n	Building container: $imageTarget"
	# Build
	count=$((count + 1 ))
	if podman build -t "localhost/$imageTarget" \
		${env:+--env "$env"} \
		-v="/var/home/wavelet/containerfiles:/mount:z" \
		-f "/var/home/wavelet/containerfiles/${containerFile}" \
		>> "./build_registry.log" 2>&1; then
		echo -e "${GREEN}Built $imageTarget successfully${NC}"
		# Export to registry
		if [[ "$imageTarget" == *"server"* ]];then
		  echo "    Built coreos_overlay_server OCI layer locally, leaving in local containers_storage.."
		else
		  export_container_image "$imageTarget"
		fi
		return $?
	else
		echo -e "${RED}		Failed to build $imageTarget${NC}"
		return 1
	fi
}

export_container_image(){
	local imageTarget="$1"
	local registry_hostname
	registry_hostname=$(hostname -f)
	local registry_url="$registry_hostname:5000"
	echo -e "\n	Exporting $imageTarget to registry $registry_url"
	if podman push --format oci --tls-verify=false \
	    "localhost/$imageTarget" \
	    "$registry_url/$imageTarget:latest"; then
		echo -e "${GREEN}Successfully pushed $imageTarget${NC}"
		podman image prune -f >/dev/null 2>&1
		return 0
	else
		echo -e "${RED}Failed to push $imageTarget${NC}"
		return 1
	fi
}

rpm_ostree_ARM(){
	echo "not yet implemented"
	exit 0
}

rpm_ostree_RISCV(){
	echo "not yet implemented"
	exit 0
}

pull_overlay(){
	# This is required because the initial pull often fails
	local image_name="$1"
	local retry=1
	local max_retries=5
	  echo "Attempting to pull overlay image: $image_name"
	while (( retry <= max_retries )); do
		# Try with registry hostname first
		if timeout 480 podman pull --tls-verify=false "$oci_registry/$image_name"; then
			echo "Successfully pulled $image_name from $oci_registry"
			return 0
		fi
		echo "Pull attempt $retry failed for $oci_registry/$image_name"
		# Try with IP address and explicit port as fallback
    	local registry_ip="${DEPLOYMENT_REGISTRY:-${REGISTRY}}"
    	if timeout 480 podman pull --tls-verify=false "$registry_ip:5000/$image_name"; then
			echo "Successfully pulled $image_name using IP fallback: $registry_ip:5000"
			return 0
		fi
		if (( retry < max_retries )); then
			echo "Pull failed. Retrying in $retry seconds... (attempt $retry of $max_retries)"
			sleep "$retry"
		fi
		retry=$((retry + 1))
	done
	echo "ERROR: Failed to pull $image_name after $max_retries attempts"
	return 1
}

rpm_overlay_install_server(){
	echo "Rebasing server to OCI container image"
	echo "	Current rpm-ostree status:"
	rpm-ostree status
	echo "	Current bootc status: "
	bootc status
	# Bug note - as of FCOS 20260621, bootc switch performs correctly and ostree rebase appears depreciated
	if [[ "$externalReg" == "0" ]]; then
		echo "	Rebasing from local containers-storage..."
		bootc switch --transport registry "$storage/coreos_overlay_server:latest"
#		rpm-ostree rebase --experimental "ostree-unverified-image:containers-storage:localhost/coreos_overlay_server:latest"
	else
		storage="$oci_registry"
		echo "	Rebasing from registry: $storage..."
		bootc switch --transport registry "$storage/coreos_overlay_server:latest"
#		rpm-ostree rebase --experimental "ostree-unverified-image:registry:$storage/coreos_overlay_server"
	fi
}

rpm_overlay_install_client(){
	# Pulls the client overlay and installs it.  For obvious reasons, client only.
	serverHostName="$(grep -E '^DOMAIN=' /etc/wavelet/wavelet.conf 2>/dev/null | cut -d'=' -f2 | sed 's/^/svr./' || echo "svr.$DOMAIN")"
	serverIPAddress="$(grep -E '^SVR_IP=' /etc/wavelet/wavelet.conf 2>/dev/null | cut -d'=' -f2)"
	oci_registry="$serverIPAddress:5000"
	echo "Installing via container and applying as ostree overlay.."
	until ping -c 1 "$serverHostName"; do
		sleep .1
	done
	# add the svr host entry for early DNS resolution
	echo "$serverIPAddress $serverHostName" > /etc/hosts
	cat > /etc/containers/registries.conf.d/10-wavelet.conf <<- EOF
		[[registry]]
		prefix = "svr.$(dnsdomainname)"
		location = "${oci_registry}"
		insecure = true
	EOF
	echo "	Pulling from $serverHostName/coreos_overlay_client"
#	bootc switch --transport registry "$serverHostName/coreos_overlay_client"
	rpm-ostree rebase --experimental "ostree-unverified-image:registry:$serverHostName/coreos_overlay_client"
	echo "RPM package updates completed, finishing installer task.."
	echo "Generating client install service systemd entry.."
	cat > "/etc/systemd/system/wavelet_install_client.service" <<-EOF
		[Unit]
		Description=Install Client Dependencies
		ConditionPathExists=/var/rpm-ostree-overlay.rpmfusion.pkgs.complete
		ConditionPathExists=/var/firstboot.complete.target
		ConditionPathExists=!/var/client_install.complete
		Wants=network-online.target
		After=multi-user.target network-online.target

		[Service]
		Type=oneshot
		ExecStartPre=/usr/bin/bash -c 'sleep 3'
		ExecStart=/usr/bin/bash -c '/usr/local/bin/wavelet_install_client.sh'

		[Install]
		WantedBy=multi-user.target
	EOF
	echo -e "Client install service will run on next reboot to populate wavelet modules and configure networking."
	systemctl daemon-reload
	systemctl enable wavelet_install_client.service
	# Final step in the FIRST boot.
	# remember to reset permissions or we get root logfiles
	chown wavelet:wavelet -R "/var/home/wavelet"
	# We need to now reboot so our OCI layer becomes active
	systemctl reboot
}

install_packages(){
	# Decompresses wavelet .tar.gz to appropriate dirs
	# Arg is always the name of the wavelet archive, set from ignition systemd declaration
	echo -e "Installing packages and additional files.."
	/usr/bin/mkdir -p /var/wavelet_root
	if [[ ! -f "/var/$1" ]]; then
		echo "ERROR:  File /var/$1 does not exist!"
		exit 1
	fi

	/usr/bin/tar -xf "/var/$1" --strip-components=3 -C /var/wavelet_root --overwrite
	/usr/bin/cp -r /var/wavelet_root/etc/* /etc/
	/usr/bin/cp -r /var/wavelet_root/usr/local/bin/* /usr/local/bin/
	/usr/bin/cp -r /var/wavelet_root/home/* /var/home/

	# BashRC
	/usr/bin/cp -r /var/wavelet_root/etc/skel/.* /var/home/wavelet/
	/usr/bin/cp -r /var/wavelet_root/etc/skel/.* /var/home/wavelet-root/
	/usr/bin/cp -r /var/wavelet_root/etc/skel/.* /var/roothome/

	# Polkit rules
	# Note we want to preserve the tabs in the polkit rules for readability
	if [[ "$1" == *"decoder" ]]; then
		echo "	Adding client-specific rules.."
		cat > "/etc/polkit-1/rules.d/1339-wavelet-hostname.rules" <<EOF
polkit.addRule(function(action, subject) {
	if ((action.id == \"org.freedesktop.systemd1.manage-units\" &&
	subject.user == \"wavelet\")) {
		polkit.log(\"action=\" + action)
		polkit.log(\"subject=\" + subject)
		polkit.log(\"unit=\"+action.lookup(\"unit\"))
		polkit.log(\"verb=\"+action.lookup(\"verb\"))
		if (action.lookup(\"unit\") == \"decoderhostname.service\") {
			var verb = action.lookup(\"verb\");
			if (verb == \"start\" || verb == \"stop\" || verb == \"restart\" || verb == \"enable\" || verb == \"disable\") {
				polkit.log(\"returning YES\")
				return polkit.Result.YES;
			}
		}
	}
});
EOF
		chmod 0644 "/etc/polkit-1/rules.d/1339-wavelet-hostname.rules"
		cat > "/etc/polkit-1/rules.d/1340-wavelet-screencast.rules" <<EOF
polkit.addRule(function(action, subject) {
	if ((action.id == "org.freedesktop.systemd1.manage-units" &&
	subject.user == "wavelet")) {
		var unit = action.lookup("unit");
		if (unit && (unit.indexOf("wavelet-wpa@") == 0 ||
		             unit.indexOf("wavelet-sinkctl@") == 0)) {
			var verb = action.lookup("verb");
			if (verb == "start" || verb == "stop" || verb == "restart") {
				return polkit.Result.YES;
			}
		}
	}
});
EOF
		chmod 0644 "/etc/polkit-1/rules.d/1340-wavelet-screencast.rules"
		cat > "/etc/polkit-1/rules.d/49-wavelet-hostnamectl.rules" << EOF
polkit.addRule(function(action, subject) {
	if (action.id == \"org.freedesktop.hostname1.set-static-hostname\") {
		if (subject.user == \"wavelet\") {
			return polkit.Result.YES;
		}
	}
	polkit.log(\"returning NO\")
});
EOF
		chmod 0644 "/etc/polkit-1/rules.d/49-wavelet-hostnamectl.rules"
		cat > "/etc/polkit-1/rules.d/1336-systemd-getty.rules" << EOF
polkit.addRule(function(action, subject) {
	if ((action.id == "org.freedesktop.systemd1.manage-units" &&
	subject.user == "wavelet")) {
		polkit.log("action=" + action)
		polkit.log("subject=" + subject)
		polkit.log("unit="+action.lookup("unit"))
		polkit.log("verb="+action.lookup("verb"))
		if (action.lookup("unit") == "getty@tty1.service") {
			var verb = action.lookup("verb");
			if (verb == "restart") {
				polkit.log("returning YES")
				return polkit.Result.YES;
			}
		}
	}
});
EOF
		chmod 0644 "/etc/polkit-1/rules.d/1336-systemd-getty.rules"
		echo -e "	Client-specific rules generated.."
	fi

	# Common rules and polkit files
	cat > "/etc/polkit-1/rules.d/9337-wavelet.rules" << EOF
polkit.addRule(function(action, subject) {
	if ((action.id == "org.freedesktop.systemd1.manage-units" &&
		subject.user == "wavelet-root")) {
			polkit.log("action=" + action)
			polkit.log("subject=" + subject)
			polkit.log("unit="+action.lookup("unit"))
			polkit.log("verb="+action.lookup("verb"))
			if (action.lookup("unit") == "etcd-quadlet.service") {
				var verb = action.lookup("verb");
				if (verb == "start" || verb == "stop" || verb == "restart" || verb == "enable" || verb == "disable") {
					polkit.log("returning YES")
					return polkit.Result.YES;
				}
			}
	}
});
EOF
	chmod 0644 "/etc/polkit-1/rules.d/9337-wavelet.rules"

	cat > "/etc/polkit-1/rules.d/1338-wavelet-wifi.rules" << EOF
polkit.addRule(function(action, subject) {
  if (( action.id == "org.freedesktop.NetworkManager.wifi.scan" ||
	action.id == "org.freedesktop.NetworkManager.settings.modify.hostname" ||
	action.id == "org.freedesktop.NetworkManager.settings.modify.own" ||
	action.id == "org.freedesktop.NetworkManager.settings.modify.system" ||
	action.id == "org.freedesktop.NetworkManager.network-control" ||
	action.id == "org.freedesktop.NetworkManager.reload" ||
	action.id == "org.freedesktop.NetworkManager.Settings.ReloadConnections" ||
	action.id == "org.freedesktop.NetworkManager.Settings.modify" ||
	action.id == "org.freedesktop.NetworkManager.enable-disable-wifi" ||
	action.id == "org.freedesktop.NetworkManager.enable-disable-network" ) &&
	(subject.user == "wavelet" || subject.user == "wavelet-root"))
	{
	  return polkit.Result.YES;
	}
});
EOF
	chmod 0644 "/etc/polkit-1/rules.d/1338-wavelet-wifi.rules"
	cat > "/etc/polkit-1/rules.d/51-systemd-resolved.rules" <<EOF
polkit.addRule(function(action, subject) {
  if ((action.id == "org.freedesktop.resolve1") &&
	subject.user == "wavelet") {
	  return polkit.Result.YES;
	}
});
EOF
	chmod 0644 "/etc/polkit-1/rules.d/51-systemd-resolved.rules"
	cat > "/etc/polkit-1/rules.d/51-reboot.rules" <<EOF
polkit.addRule(function(action, subject) {
  if ((action.id == "org.freedesktop.reboot" &&
	subject.user == "wavelet")) {
	  return polkit.Result.YES;
	}
});
EOF
	chmod 0644 "/etc/polkit-1/rules.d/51-reboot.rules"
	# USB detection rule
	cat > "/etc/udev/rules.d/80-wavelet-encoder.rules" << EOF
ACTION=="add", SUBSYSTEM=="usb", ENV{ID_USB_INTERFACES}==":0e*:*", \
    TAG+="systemd", ENV{UDEV_DB_RAN_ALREADY}!="1", \
    ENV{SYSTEMD_USER_WANTS}+="wavelet_detectv4l@%E{DEVNAME}.service", ENV{UDEV_DB_RAN_ALREADY}="1"

ACTION=="remove", SUBSYSTEM=="video4linux", ENV{DEVNAME}=="/dev/video*", \
    RUN+="/usr/local/bin/wavelet_detectv4l.sh remove %E{DEVNAME}"
EOF
	chmod 0644 "/etc/udev/rules.d/80-wavelet-encoder.rules"
	# Other files
	mkdir -p /var/home/wavelet/http/
	cat > "/var/home/wavelet/http/.htaccess" <<-EOF
		Options +Indexes
		<Limit GET POST>
		order deny,allow
		deny from all
		allow from 192.168.1.0/24
		</Limit>
		IndexIgnore tabele_remote.php
		IndexIgnore demo.txt
		IndexIgnore functions.php
		IndexIgnore config.php
	EOF
	chmod 0664 "/var/home/wavelet/http/.htaccess"
	mkdir -p /etc/ssh/sshd_config.d/
	cat > "/etc/ssh/sshd_config.d/30-ed25519-only.conf" <<-EOF
		PubkeyAcceptedKeyTypes ssh-ed25519-cert-v01@openssh.com,ssh-ed25519
	EOF
	chmod 0644 "/etc/ssh/sshd_config.d/30-ed25519-only.conf"
	cat > "/etc/ssh/sshd_config.d/20-enable-passwords.conf" <<-EOF
		# Fedora CoreOS disables SSH password login by default.
		# Enable it.
		# This file must sort before 40-disable-passwords.conf
		PasswordAuthentication yes
	EOF
	echo "" > "/etc/modprobe.d/i915.conf"
	chmod 0644 "/etc/modprobe.d/i915.conf"
	cat > "/etc/sysctl.d/90-sysrq.conf" <<-EOF
		# As per UG Team
		# Increase the read-buffer space allocatable
		net.ipv4.tcp_mem = 1000000 2000000 83886080
		net.ipv4.tcp_rmem = 8192 4194394 83886080
		net.ipv4.udp_mem = 8388608 12582912 83886080
		net.core.rmem_default = 83886080
		net.core.rmem_max = 83886080
		net.core.netdev_max_backlog = 2000
		net.ipv4.ip_unprivileged_port_start=53
		net.ipv4.tcp_congestion_control = bbr
		net.core.netdev_max_backlog = 5000
		net.ipv4.tcp_mtu_probing = 1
		# Increase the write-buffer-space allocatable
		net.ipv4.tcp_wmem = 8192 4194394 83886080
		# does not exist?
		# net.ipv4.udp_wmem = 8388608 12582912 83886080
		net.core.wmem_default = 83886080
		net.core.wmem_max = 83886080
		# NUMA Balancing
		kernel.numa_balancing=0
		# Reduce network latency
		net.core.somaxconn = 65535
		net.ipv4.tcp_low_latency = 1
		net.ipv4.tcp_max_syn_backlog = 65535
		net.ipv4.tcp_sack = 1
		net.ipv4.tcp_fack = 1
		net.ipv4.tcp_window_scaling = 1
		net.ipv4.tcp_timestamps = 1
		net.ipv4.tcp_fastopen = 3
		# intel gpu
		dev.i915.perf_stream_paranoid=0
		kernel.sysrq = 0
		# Memory management for high throughput
		vm.swappiness = 1
		vm.dirty_ratio = 15
		vm.dirty_background_ratio = 5
		vm.vfs_cache_pressure = 50
		# Filesystem openfiles
		fs.file-max = 1048576
		fs.nr_open = 1048576
		# Paging
		vm.page-cluster = 0
		vm.dirty_writeback_centisecs = 1500
		vm.dirty_expire_centisecs = 1500
	EOF
	# This makes using etcdctl for troubleshooting somewhat less painful
	cat > "/etc/profile.d/etcdctl.sh" <<-EOF
		#!/bin/bash
		export ETCDCTL_ENDPOINTS=\"https://$(hostname):2379\"
		export ETCDCTL_CACERT=\"/etc/ipa/ca.crt\"
	EOF
	chmod 0644 "/etc/profile.d/etcdctl.sh"
	chmod 0644 "/etc/sysctl.d/90-sysrq.conf"
	chmod 0644 "/etc/ssh/sshd_config.d/20-enable-passwords.conf"
	mkdir -p /usr/local/backgrounds/sway/
	/usr/bin/cp "/var/wavelet_root/usr/local/backgrounds/sway/wavelet_test.png" "/usr/local/backgrounds/sway/"
	chmod 0644 "/usr/local/backgrounds/sway/wavelet_test.png"
	/usr/bin/chmod 0755 "/usr/local/bin"
	/usr/bin/chown wavelet:wavelet "/var/home/wavelet"
	/usr/bin/chown wavelet-root:wavelet-root "/var/home/wavelet-root"
	# Add empty rdma files to suppress startup warnings
	touch /etc/rdma/modules/{infiniband.conf,rdma.conf,roce.conf}
}

generate_files(){
	# Smaller files can be generated from wavelet_keys
	while IFS=',' read -r type path mode overwrite owner group content; do
		[[ "$type" == "type" ]] && continue  # Skip header
			# Create parent directories
			mkdir -p "$(dirname "$path")" 2>/dev/null
			# Test for file or dir and create them.
		if [[ "$type" == "file" ]]; then
			echo -e "$content" > "$path"
			[[ "$mode" != "" ]] && chmod "$mode" "$path"
				[[ "$overwrite" == "true" ]] && echo "Overwritten: $path"
		elif [[ "$type" == "dir" ]]; then
			mkdir -p "$path"
			[[ "$mode" != "" ]] && chmod "$mode" "$path"
		fi
		# Set ownership (skip if empty or root)
		[[ "$owner" != "" && "$owner" != "root" ]] && chown "$owner:$group" "$path" 2>/dev/null
	done < "$1"
}


#####
#
# Main
#
#####


mkdir -p /var/home/wavelet/logs
exec >/var/home/wavelet/logs/installer.log 2>&1
systemctl disable zincati.service --now
hostNameSys="$(hostname)"
# Sources the following:
source "/etc/wavelet.conf"
#DOMAIN
#SVR_IP
#SVR_GW
#SVR_DNS
#SVR_HOSTNAME
#TIME_ZONE
#DEVELOPER_MODE
#ENABLE_WIFI
#WIFI_SSID
#WIFI_BSSID
#DEPLOYMENT_REGISTRY
#REGISTRY
#UG_BUILD_TYPE
# Set timezone correctly for locale
echo "Setting timezone to appropriate locale."
echo "Please ensure other devices (switch, AP, network video sources) are correctly set to either use NTP for the server."
timeZone="${TIME_ZONE:-America/New_York}"
timedatectl set-timezone "$timeZone"

# Generate remaining files from wavelet_keys.csv - note wavelet_keys differs in content if server bootstrap or client.
echo "Processing inline file generation.."
generate_files "$2"

# Create directories for wavelet configuration
echo "Creating additional directories.."
mkdir -p /etc/wavelet
mkdir -p /var/log/wavelet
chown wavelet:wavelet /var/log/wavelet
echo "Getting available repository data.."
# This is the LAN deployment registry (from config file)
registry="${DEPLOYMENT_REGISTRY:-${REGISTRY}}"
# This is the LOCAL registry on THIS server
local_registry="${SVR_HOSTNAME}"

rpm-ostree initramfs --enable
# Systemd early unit to set plymouth theme next boot
# This is failable so it won't generate error messages and is guaranteed to only try once.
cat > "/etc/systemd/system/set-plymouth-theme.service" <<-EOF
	[Unit]
	Description=Set Plymouth Boot Theme
	Before=plymouth-start.service
	DefaultDependencies=no
	Conflicts=shutdown.target
	After=local-fs.target

	[Service]
	Type=oneshot
	ExecStart=-/usr/bin/plymouth-set-default-theme -R tribar
	RemainAfterExit=yes
	ExecStartPost=/bin/systemctl disable set-plymouth-theme.service

	[Install]
	WantedBy=sysinit.target
EOF

systemctl daemon-reload
systemctl enable set-plymouth-theme.service

# Defines the git tarball we use to populate /usr/local/bin with our modules
# Extract wavelet files from the included tar
echo "Extracting wavelet packages.."
install_packages "$1"
chown -R wavelet:wavelet /var/home/wavelet

detect_self