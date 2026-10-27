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
			echo -e "		AMD64 architecture, running base install..\n"
			rpm_overlay_install_client
			;;
		"aarch64")
			echo -e "		aarch64 architecture, switching to ARM ostree.."
			rpm_ostree_ARM
			;;
		"riscv64")
			echo -e "		RISC-V architecture, switching to RISCV ostree.."
			rpm_ostree_RISCV
			;;
		*)
			echo -e "		Architecture unsupported, exiting..\n"
			;;
	esac
}

event_clientHostName(){
	if [[ "$(hostname)" == "decX.$DOMAIN" ]]; then
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

full_iso_install(){
	# FULL_ISO_MODE=1 (wavelet.conf, full ISO builds only).  All provisioning
	# data lives on the install USB's "wavelet-offline" partition (appended
	# by build_full_iso.sh).  Mirrors the normal bootstrap flow exactly, but
	# every network source is replaced by the mounted media:
	logfile="/var/log/wavelet/offline_install.log"
	mkdir -p /var/log/wavelet
	(
		echo "===== full_iso_install START $(date -Is) host=$(hostname) DEVELOPER_MODE=${DEVELOPER_MODE:-unset} USE_BOOTC=${USE_BOOTC:-unset} ====="
		local FULL_ISO_MEDIA="/mnt/wavelet-offline"
		if [[ ! -e "/dev/disk/by-label/wavelet-offline" ]]; then
			echo "	ERROR: FULL_ISO_MODE set but no wavelet-offline partition found!"
			return 1
		fi
		mkdir -p "$FULL_ISO_MEDIA"
		if ! mount -o ro /dev/disk/by-label/wavelet-offline "$FULL_ISO_MEDIA"; then
			echo "	ERROR: mount of wavelet-offline partition failed!"
			return 1
		fi
		echo "	Mounted $FULL_ISO_MEDIA; contents:"
		ls -laR "$FULL_ISO_MEDIA"

	# Tarball: name must match DEVELOPER_MODE; install_packages() expects
	# it at /var/<name>.
	local packageTarball="master.tar.gz"
	if [[ "$DEVELOPER_MODE" -eq 1 ]]; then
		packageTarball="armelvil-working.tar.gz"
	fi
	if [[ -f "$FULL_ISO_MEDIA/wavelet.tar.gz" ]]; then
		echo "	Copying wavelet tarball from install media.."
		if ! cp -f "$FULL_ISO_MEDIA/wavelet.tar.gz" "/var/$packageTarball"; then
			echo "	ERROR: failed to copy wavelet tarball to /var/$packageTarball!"
			umount "$FULL_ISO_MEDIA"
			return 1
		fi
	else
		echo "	ERROR: $FULL_ISO_MEDIA/wavelet.tar.gz not found on install media!"
		umount "$FULL_ISO_MEDIA"
		return 1
	fi
	# AppImage + RPMs: copied to the paths the tarball/containerfiles expect.
	if [[ -f "$FULL_ISO_MEDIA/UltraGrid.AppImage" ]]; then
		echo "	Copying UltraGrid AppImage from install media.."
		cp "$FULL_ISO_MEDIA/UltraGrid.AppImage" "/usr/local/bin/UltraGrid.AppImage"
		chmod 0755 "/usr/local/bin/UltraGrid.AppImage"
	else
		echo "	WARNING: UltraGrid.AppImage not found on install media, skipping."
	fi
	if ls "$FULL_ISO_MEDIA"/rpms/*.rpm >/dev/null 2>&1; then
		mkdir -p "/var/home/wavelet/containerfiles/rpms"
		cp "$FULL_ISO_MEDIA"/rpms/*.rpm "/var/home/wavelet/containerfiles/rpms/" || true
		echo "	Copied RPMs from install media:"
		ls -l "/var/home/wavelet/containerfiles/rpms/"
	else
		echo "	WARNING: no RPMs found on install media (rpms/ dir)."
	fi
	local archive name
	for archive in "$FULL_ISO_MEDIA"/images/*.oci.tar; do
		[[ -f "$archive" ]] || continue
		name="$(basename "$archive" .oci.tar)"
		echo "	Loading $name from install media.."
		local retry=1
		while (( retry <= 3 )); do
			if podman load -i "$archive"; then
				echo "	Successfully loaded $name (attempt $retry)."
				break
			fi
			echo "	podman load attempt $retry failed for $name, retrying.."
			sleep 5
			retry=$((retry + 1))
		done
		if (( retry > 3 )); then
			echo "	ERROR: failed to load $name after 3 attempts!"
			umount "$FULL_ISO_MEDIA"
			return 1
		fi
	done
	echo "	Images loaded into local store:"
	podman images --format '{{.Repository}}:{{.Tag}}' | grep '^localhost/' || echo "	WARNING: no localhost/ images present after load!"
	umount "$FULL_ISO_MEDIA" && echo "	Unmounted $FULL_ISO_MEDIA." || echo "	ERROR: umount of $FULL_ISO_MEDIA failed (continuing)."
	echo "	Offline data installed; install USB may be removed now."
	FULL_ISO_ACTIVE=1

	# From here on, the flow is the NORMAL bootstrap in order, just with
	# every source being local.  See branch points in the functions above.
	echo "	Extracting wavelet packages.."
	if ! install_packages "$1"; then
		echo "	ERROR: install_packages failed!"
		return 1
	fi
	if ! chown -R wavelet:wavelet /var/home/wavelet; then
		echo "	ERROR: chown of /var/home/wavelet failed!"
		return 1
	fi
	echo "	Package extraction complete."

	# Server-side only: full ISO is server-only for now (hostname prefix
	# svr*).  generate_files was already run before the branch (Main).
	# Registry: local-only; pull_registry_images() branches on FULL_ISO_ACTIVE
	# to push the media-loaded localhost images instead of pulling remotely.
	if ! check_registry; then
		echo "	ERROR: check_registry failed!"
		return 1
	fi
	echo "	check_registry complete (oci_registry=$oci_registry externalReg=${externalReg:-unset})."
	if ! setup_registry_quadlet; then
		echo "	ERROR: setup_registry_quadlet failed!"
		return 1
	fi
	echo "	setup_registry_quadlet complete."
	if ! pull_registry_images; then
		echo "	ERROR: pull_registry_images failed!"
		return 1
	fi
	echo "	pull_registry_images complete."
	if ! pull_overlay "coreos_overlay_client${OVERLAY_SUFFIX}"; then
		echo "	ERROR: pull_overlay of coreos_overlay_client${OVERLAY_SUFFIX} failed!"
		return 1
	fi
	echo "	pull_overlay complete."
	if podman tag "coreos_overlay_client${OVERLAY_SUFFIX}:latest" "$hostNameSys/coreos_overlay_client${OVERLAY_SUFFIX}"; then
		echo "	Tagged overlay client image as $hostNameSys/coreos_overlay_client${OVERLAY_SUFFIX}."
	else
		echo "	ERROR: podman tag of coreos_overlay_client${OVERLAY_SUFFIX} failed!"
		return 1
	fi
	if podman push "$hostNameSys/coreos_overlay_client${OVERLAY_SUFFIX}" "$hostNameSys:5000/coreos_overlay_client${OVERLAY_SUFFIX}"; then
		echo "	Pushed $hostNameSys/coreos_overlay_client${OVERLAY_SUFFIX} to local registry."
	else
		echo "	ERROR: podman push of coreos_overlay_client${OVERLAY_SUFFIX} failed!"
		return 1
	fi
	# Nameserver karg cleanup (bootc-era: rpm-ostree kargs unavailable)
	if [[ "${USE_BOOTC:-0}" != "1" ]] && rpm-ostree kargs | grep -q 'nameserver'; then
		echo "	Removing nameserver karg.."
		rpm-ostree kargs --delete nameserver
	else
		echo "	No nameserver karg present (or bootc), skipping karg cleanup."
	fi
	if ! rpm_overlay_install_server; then
		echo "	ERROR: rpm_overlay_install_server failed!"
		return 1
	fi
	echo "	rpm_overlay_install_server complete."
	if systemctl enable wavelet_install_services.service; then
		echo "	Enabled wavelet_install_services.service."
	else
		echo "	ERROR: failed to enable wavelet_install_services.service!"
		return 1
	fi

	# Tarball copy to webserver + sha512 (mirrors the tail of event_server).
	local waveletFiles_sha512
	if ! cp "/var/$packageTarball" "/var/home/wavelet/http/ignition/wavelet_files.tar.gz"; then
		echo "	ERROR: failed to copy $packageTarball to webserver directory!"
		return 1
	fi
	if ! cp "/usr/local/bin/wavelet_install_packages.sh" "/var/home/wavelet/http/ignition/"; then
		echo "	ERROR: failed to copy wavelet_install_packages.sh to webserver directory!"
		return 1
	fi
	waveletFiles_sha512="$(sha512sum <"/var/home/wavelet/http/ignition/wavelet_files.tar.gz" | cut -d ' ' -f 1)"
	echo "	wavelet_files.tar.gz sha512: $waveletFiles_sha512"
	if ! echo "$waveletFiles_sha512" > "/var/secrets/waveletFiles_sha512.txt"; then
		echo "	ERROR: failed to write /var/secrets/waveletFiles_sha512.txt!"
		return 1
	fi
	chown -R root:wavelet-root "/var/secrets"
	chmod 0750 "/var/secrets"; chmod 0640 /var/secrets/*
	if set_ethernet_mtu; then
		echo "	set_ethernet_mtu complete."
	else
		echo "	WARNING: set_ethernet_mtu returned non-zero."
	fi
	return 0
	) 2>&1 | tee -a "$logfile"
	local rc=${PIPESTATUS[0]}
	if (( rc != 0 )); then
		echo "===== full_iso_install FAILED (rc=$rc) $(date -Is) — see $logfile =====" | tee -a "$logfile"
	else
		echo "===== full_iso_install COMPLETE $(date -Is) — see $logfile =====" | tee -a "$logfile"
	fi
	return "$rc"
}

event_server(){
	# generate proper RC files for root/wavelet-root which gives us aliases and powerline
	cd "/root" || return; rm .bashrc .bash_profile; cp /etc/skel/{.bashrc,.bash_profile} .
	cd "/var/home/wavelet-root" || return; rm .bashrc .bash_profile; cp /etc/skel/{.bashrc,.bash_profile} .
	# Server can only be x86.
	# I haven't had access to another platform with video hardware support + enough number crunching power to do the task.
	# Get, or generate RPM overlay
	# Set my pretty hostname
	hostnamectl set-hostname "$SVR_HOSTNAME" --pretty

	# Make etcd datadir and copy nonsecure yaml to conf file, and update with server IP address.
	mkdir -p "/var/lib/etcd-data"
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
	# RPM Ostree and container infra setup
	# We will check for an external registry first, and build local images only if it does not exist.
	echo "OCI Container image setup"
	# First we check and generate our registry value
	check_registry
	setup_registry_quadlet
	pull_registry_images
	# Pull these images in serial as they are heavy
	pull_overlay "coreos_overlay_client${OVERLAY_SUFFIX}"
	podman tag "coreos_overlay_client${OVERLAY_SUFFIX}:latest" "$hostNameSys/coreos_overlay_client${OVERLAY_SUFFIX}"
	podman push "$hostNameSys/coreos_overlay_client${OVERLAY_SUFFIX}" "$hostNameSys:5000/coreos_overlay_client${OVERLAY_SUFFIX}"
	# Remove nameserver karg if it exists
	# bootc-era: rpm-ostree kargs is unavailable on bootc systems
	if [[ "${USE_BOOTC:-0}" != "1" ]] && rpm-ostree kargs | grep -q 'nameserver'; then
	  rpm-ostree kargs --delete nameserver
	fi
	rpm_overlay_install_server
	# wavelet_pxe_install.service will complete the root portion of the server spinup
	systemctl enable wavelet_install_services.service
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
	echo "$waveletFiles_sha512" > "/var/secrets/waveletFiles_sha512.txt"
	# Ensure only root and wavelet-root can read the secrets dir
	chown -R root:wavelet-root "/var/secrets"
	chmod 0750 "/var/secrets"; chmod 0640 /var/secrets/*
	set_ethernet_mtu
#	# ── DIAGNOSTICS: final state check before reboot ──
#	echo "=== PRE-REBOOT DIAGNOSTIC: rpm-ostree status ==="
#	rpm-ostree status --json 2>&1
#	echo "=== PRE-REBOOT DIAGNOSTIC: ostree admin status ==="
#	ostree admin status 2>&1
#	echo "=== PRE-REBOOT DIAGNOSTIC: /boot/loader/entries ==="
#	cat /boot/loader/entries/*.conf 2>&1
#	echo "=== END PRE-REBOOT DIAGNOSTICS ==="
#	sync
#	echo "Installation completed, restarting server.."
	systemctl reboot
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
	mkdir -p "/var/containers/registry"
	systemctl daemon-reload && systemctl start registry.service
	sleep 5
	if curl -s "http://$SVR_HOSTNAME:5000/v2"; then
		echo "Registry running, continuing.."
	else
		echo "Registry down!  Cannot continue!"
		exit 1
	fi
}

check_registry(){
	# Do we have an external registry or no?
	# DEPLOYMENT_REGISTRY should be defined in the conf file
	# DEPLOYMENT_IP may be used as a backup
	# FULL_ISO install: media images are already podman-loaded locally by
	# full_iso_mode(); treat as local-only build regardless of conf.
	if [[ "${FULL_ISO_ACTIVE:-0}" == "1" ]]; then
		echo "	FULL_ISO install: images loaded from install media, local-only registry."
		oci_registry="svr.$DOMAIN"
		externalReg=0
		return 0
	fi
	if [[ -z "$DEPLOYMENT_IP" ]]; then
		echo "	Registry IP not set in config file, this is a local-only deployment."
		oci_registry="svr.$DOMAIN"
		externalReg=0
		podman pull "docker.io/library/registry"
		echo "Registry IP and server IP match, generating OCI images locally, oci_registry set to: $oci_registry"
		echo "Container images will be pulled from internet."
		count=0
		# Export implied in build function
		build_container_image "coreos_overlay_client${OVERLAY_SUFFIX}" "Containerfile.coreos.overlay.client"
		build_container_image "coreos_overlay_server${OVERLAY_SUFFIX}" "Containerfile.coreos.overlay.server"
	else
		echo "Deployment server is defined in wavelet.conf, utilizing external registry.."
		# Define the LAN registry conf
		cat > "/etc/containers/registries.conf.d/11-lan.conf" <<-EOF
			[[registry]]
			prefix = "lan.$DOMAIN"
			location = "${DEPLOYMENT_IP}:5000"
			insecure = false
		EOF
		# The server registry is "temporarily" insecure as it only works locally
		# We then utilize a domain certificate/CA once FreeIPA has spun up.
		cat > "/etc/containers/registries.conf.d/10-wavelet.conf" <<-EOF
			[[registry]]
			prefix = "svr.$DOMAIN"
			location = "$(hostname):5000"
			insecure = true
		EOF
		oci_registry="lan.$DOMAIN"
		externalReg=1
		# It is easier to perform the registry podman pull here to save us an if test
		# NOTE:  ca.crt must exist at: /etc/containers/certs.d/lan.wavelet.local/ca.crt
		podman pull "$oci_registry/registry"
		echo "Pulling OCI client image from external registry to local registry, oci_registry set to: $oci_registry"
		echo "Container images will be pulled from external registry"
	fi
}

pull_registry_images() {
  # Sets vars for appropriate package sources and places them in the wavelet server's local registry
  # In my lab environment, I setup a local registry that updates and tags everything with a cronjob
  # The process saves bandwidth and having to download gbs of container images every test
  # FULL_ISO install: images are already podman-loaded locally (full_iso_mode)
  # as localhost/<shortname>; just push them into the local registry.
  if [[ "${FULL_ISO_ACTIVE:-0}" == "1" ]]; then
    echo "FULL_ISO install: pushing media-loaded images into local registry.."
    local loaded
    for loaded in etcd coreos-installer fedora nginx php redis httpd registry freeipa-server \
                  coreos_overlay_client"${OVERLAY_SUFFIX}" coreos_overlay_server"${OVERLAY_SUFFIX}" \
                  tftpd tftpboot isc-kea radiusd php-fpm-redis; do
      if podman image exists "localhost/$loaded"; then
        echo "	Pushing localhost/$loaded -> $hostNameSys:5000/$loaded"
        podman push "localhost/$loaded" "$hostNameSys:5000/$loaded" || \
          echo "	ERROR: push of localhost/$loaded failed (may already exist in registry)."
      else
        echo "	WARNING: localhost/$loaded not in local store, skipping push."
      fi
    done
    return 0
  fi
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
    local tls=""
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
        if timeout $timeout podman pull "$source"; then
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
        if timeout $timeout podman push "$source" "$hostNameSys:5000/${shortSource%%:*}"; then
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
	if podman build --security-opt label=disable -t "localhost/$imageTarget" \
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
	registry_hostname=$SVR_HOSTNAME
	local registry_url="$registry_hostname:5000"
	echo -e "\n	Exporting $imageTarget to registry $registry_url"
	if podman push --format oci \
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
		if timeout 480 podman pull "$oci_registry/$image_name"; then
			echo "Successfully pulled $image_name from $oci_registry"
			return 0
		fi
		echo "Pull attempt $retry failed for $oci_registry/$image_name"
		# Try with IP address and explicit port as fallback
    	local registry_ip="${DEPLOYMENT_REGISTRY:-${REGISTRY}}"
    	if timeout 480 podman pull "$registry_ip:5000/$image_name"; then
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
	echo -e "\n	Current rpm-ostree status:"
	rpm-ostree status
	echo -e "\n	Current bootc status: "
	bootc status
	sel_context="$(cat /proc/self/attr/current)"
	echo "Running in SELinux context: $sel_context)"
	# We are not using GPG signing for our ostree commits, so we still use ostree-unverified-image in the refspec
	# Given even a deployment server here is largely ephemeral,
	# a GPG sig is "correct" but overkill, as we aren't doing mass deployments.
	if [[ "$externalReg" == "0" ]]; then
		echo "	Rebasing from local containers-storage..."
		if [[ "${USE_BOOTC:-0}" == "1" ]]; then
			echo "	Using bootc path.."
			setenforce 0
			bootc switch --transport containers-storage "localhost/coreos_overlay_server${OVERLAY_SUFFIX}:latest"
			setenforce 1
		else
			echo "	Using rpm-ostree path..."
			rpm-ostree rebase "ostree-unverified-image:containers-storage:localhost/coreos_overlay_server${OVERLAY_SUFFIX}:latest"
		fi
	else
		storage="$oci_registry"
		echo "	Rebasing from registry: $storage..."
		if [[ "${USE_BOOTC:-0}" == "1" ]]; then
			bootc switch --transport registry "$storage/coreos_overlay_server${OVERLAY_SUFFIX}:latest"
		else
			rpm-ostree rebase "ostree-unverified-image:registry:$storage/coreos_overlay_server${OVERLAY_SUFFIX}"
		fi
	fi
	if [[ "${USE_BOOTC:-0}" != "1" ]]; then
		# bootc-era: initramfs is baked into the overlay image itself
		# (Containerfile.bootc.coreos.overlay.client, 'bootc initramfs --enable')
		rpm-ostree initramfs enable
	fi
}

rpm_overlay_install_client(){
	# Pulls the client overlay and installs it.  For obvious reasons, client only.
	oci_registry="$SVR_IP:5000"
	echo "Installing via container and applying as ostree overlay.."
	until ping -c 1 "$SVR_HOSTNAME"; do
		sleep .1
	done
	# add the svr host entry for early DNS resolution
	echo "$SVR_IP $SVR_HOSTNAME" > /etc/hosts
	cat > /etc/containers/registries.conf.d/10-wavelet.conf <<- EOF
		[[registry]]
		prefix = "$SVR_HOSTNAME"
		location = "$SVR_HOSTNAME:5000"
	EOF
	# Ensure the ca.crt is added to the expected docker folder
	mkdir -p "/etc/containers/certs.d/$SVR_HOSTNAME:5000"
	cp "/var/home/wavelet/config/ca.crt" "/etc/containers/certs.d/$SVR_HOSTNAME:5000/ca.crt"
	chmod 0644 "/etc/containers/certs.d/$SVR_HOSTNAME:5000/ca.crt"
	echo "	Pulling from $REGISTRY/coreos_overlay_client${OVERLAY_SUFFIX}"
	if [[ "${USE_BOOTC:-0}" == "1" ]]; then
		bootc switch --transport registry "$SVR_HOSTNAME/coreos_overlay_client${OVERLAY_SUFFIX}:latest"
	else
		rpm-ostree rebase "ostree-unverified-image:registry:$SVR_HOSTNAME/coreos_overlay_client${OVERLAY_SUFFIX}"
	fi
	echo "RPM package updates completed, finishing installer task.."
	echo "Generating client install service systemd entry.."
	cat > "/etc/systemd/system/wavelet_install_client.service" <<-EOF
		[Unit]
		Description=Install Client Dependencies
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

	# SELinux haveged module
	/usr/bin/mkdir -p /var/lib/wavelet/selinux
	haveged_pp=$(/usr/bin/find /var/wavelet_root -name "my-haveged.pp" -type f | head -n 1)
	if [[ -n "$haveged_pp" ]]; then
		/usr/bin/cp -f "$haveged_pp" /var/lib/wavelet/selinux/my-haveged.pp
		/usr/sbin/semodule -i /var/lib/wavelet/selinux/my-haveged.pp
	fi

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
		export ETCDCTL_ENDPOINTS=https://$SVR_HOSTNAME:2379
		export ETCDCTL_CACERT=/etc/ipa/ca.crt
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


# Create directories for wavelet configuration
echo "Creating additional directories.."
mkdir -p /etc/wavelet
mkdir -p /var/log/wavelet
chown wavelet:wavelet /var/log/wavelet
echo "Getting available repository data.."
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
#USE_BOOTC
#FULL_ISO_MODE
# Overlay image suffix: bootc-era images are labeled distinctly so both
# generations coexist in the registry (docs/UPDATE_TO_BOOTC.md)
if [[ "${USE_BOOTC:-0}" == "1" ]]; then
	OVERLAY_SUFFIX="_bootc"
else
	OVERLAY_SUFFIX=""
fi

# FULL ISO MODE: all provisioning data lives on the install USB's
# "wavelet-offline" partition.
if [[ "${FULL_ISO_MODE:-0}" == "1" ]]; then
	echo "	FULL_ISO_MODE=1: running offline-first install path.."
	if ! full_iso_install "$1"; then
		echo "	FULL_ISO_MODE install failed!  See log above."
		exit 1
	fi
	echo "	FULL_ISO_MODE install complete."
	systemctl reboot
fi

# Set timezone correctly for locale
echo "Setting timezone to appropriate locale."
echo "Please ensure other devices (switch, AP, network video sources) are correctly set to either use NTP for the server."
timeZone="${TIME_ZONE:-America/New_York}"
timedatectl set-timezone "$timeZone"

# Generate remaining files from wavelet_keys.csv - note wavelet_keys differs in content if server bootstrap or client.
echo "Processing inline file generation.."
generate_files "$2"

# This is the LAN deployment registry (from config file)
registry="${DEPLOYMENT_REGISTRY:-${REGISTRY}}"

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