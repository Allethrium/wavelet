#!/bin/bash
# This script bootstraps your initial wavelet server based upon the provided conf file, or input variables.

RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"

print_help(){
	echo -e "Initial wavelet install help prompts:"
	echo -e "Developer Mode: -d, --dev\nPulls from development branch on git."
	echo -e "-p=, --pass=,--password=\nSets the wavelet-root password"
	echo -e "--enablewifi\nEnable WiFi mode (required before using any -ws, -wb, -wip, -wp, -wap, -wau options)"
	echo -e "-ws=, --wifissid=\nSets the preconfigured WiFi SSID (requires --enablewifi)"
	echo -e "-wb=, --wifibssid=\nSets the preconfigured WiFi BSSID (WiFi Access Point's MAC address) (requires --enablewifi)"
	echo -e "-wip=, --wifiapip=\nSets the preconfigured WiFi IP (WiFi Access Point's IP address) (requires --enablewifi)"
	echo -e "-wp=, --wifipass=\nSets the preconfigured WiFi PSK for use in WPA2/WPA networks.  Legacy argument. (requires --enablewifi)"
	echo -e "-ip=, --serverip=\nDefines the server static IP4 address (I.E 192.168.0.2)"
	echo -e "-g=, --servergateway=\nDefines the server static IP4 gateway (I.E 192.168.0.1)"
	echo -e "-dns=, --serverdns=\nDefines the server DNS forwarder (I.E 192.168.0.53)"
	echo -e "-c=, --config=\nDefines a configuration file instead of commandline parameters (see wavelet_example.conf)"
	echo -e "--full\nBuild FULL offline install media (stages all images/tarballs onto the USB; no internet required at the install site)"
	exit 0
}

validate_ip_port(){
	# The registry is the IP address ONLY.
	local input="$1"
	local ip_part="${input%%:*}"
	local registry_port="$ip_part:5000"
	# Check for exactly one colon
	if ! ping -q -c 3 "$ip_part" > /dev/null; then
  		echo "		Issue pinging container registry! Aborting!"
  		return 1
	fi
	if curl -sk -s "https://$registry_port/v2" > /dev/null; then
		echo -e "${GREEN}	Registry running and responding to curl!${NC}"
	else
		echo -e "${RED}	Registry not responding, please verify your settings..${NC}"
		return 1
	fi
}

get_publicinterface(){
	# Tries to get the active network interface, may sometimes get it wrong.
	iface_route="$(ip -4 route show default | sort -nk1,1 | head -n1)"
	if [[ -z "$iface_route" ]]; then
		echo "	No default IPv4 route found. Cannot determine public interface."
		return 1
	fi
	iface=$(echo "$iface_route" | awk '{print $5}')
	ip="$(nmcli -t -f IP4.ADDRESS dev show $iface | awk -F: '{print $2}' |cut -d'/' -f1 )"
	echo "	Main interface IP Address: $ip"
}

download_wavelet_git(){
	# Runs for LAN or Full ISO deployment modes
	if [[ "${developerMode}" -eq "1" ]]; then
    	GH_BRANCH="armelvil-working"
	else
    	GH_BRANCH="master"
	fi
	# Fetch the commit SHA for the branch from GitHub API
	local branchInfo
	branchInfo=$(curl -s -L --max-time 30 "https://api.github.com/repos/Allethrium/wavelet/branches/$GH_BRANCH")
	local commitSha
	commitSha=$(echo "$branchInfo" | grep -oP '"sha":\s*"\K[0-9a-f]{40}' | head -1)
	if [[ -z "$commitSha" ]]; then
		echo "	Error: Could not fetch commit SHA for branch $GH_BRANCH from GitHub API!"
	fi
	echo "	Branch $GH_BRANCH commit SHA: $commitSha"
	# Check if we have a cached tarball with matching SHA
	local cached_tarball="$HOME/.config/var/www/wavelet_files_cached.tar.gz"
	local cached_sha_file="$HOME/.config/var/www/wavelet_files_cached_sha256.txt"
	if [[ -f "$cached_tarball" ]] && [[ -f "$cached_sha_file" ]]; then
		cached_sha=$(cat "$cached_sha_file")
		if [[ "$cached_sha" == "$commitSha" ]]; then
			# Validate the cached tarball is a valid tar.gz archive
			if tar -tzf "$cached_tarball" > /dev/null 2>&1; then
				echo "	Using cached wavelet tarball with matching commit SHA: $commitSha"
				cp "$cached_tarball" "$HOME/.config/var/www/wavelet_files.tar.gz"
				echo "	Acquired wavelet tarball from cache, proceeding.."
				return 0
			else
				echo "	Warning: Cached tarball is not a valid tar.gz archive, re-downloading..."
			fi
		fi
	fi
	# Download from GitHub
	local download_url="https://github.com/Allethrium/wavelet/archive/refs/heads/$GH_BRANCH.tar.gz"
	if curl -s -f -L -o "$HOME/.config/var/www/$GH_BRANCH.tar.gz" "$download_url"; then
		echo "	Acquired wavelet tarball, proceeding.."
	else
		echo "	Error downloading wavelet tarball!  aborting!"
		echo "	Please check this user's write permissions to ~/.config/var/www"
		return 1
	fi
	# Validate the downloaded file is a valid tar.gz archive
	if ! tar -tzf "$HOME/.config/var/www/$GH_BRANCH.tar.gz" > /dev/null 2>&1; then
		echo "	Error: Downloaded file is not a valid tar.gz archive!"
		echo "	File size: $(wc -c < "$HOME/.config/var/www/$GH_BRANCH.tar.gz") bytes"
		echo "	First 200 bytes:"
		head -c 200 "$HOME/.config/var/www/$GH_BRANCH.tar.gz" | cat -v
		rm -f "$HOME/.config/var/www/$GH_BRANCH.tar.gz"
		return 1
	fi
	# Compute SHA256 of the downloaded tarball and move to wavelet_files.tar.gz
	local tarballSha256
	mv "$HOME/.config/var/www/$GH_BRANCH.tar.gz" "$HOME/.config/var/www/wavelet_files.tar.gz"
	tarballSha256=$(sha256sum "$HOME/.config/var/www/wavelet_files.tar.gz" | cut -d' ' -f1)
	echo "	Tarball SHA256: $tarballSha256"
	# Cache the tarball and its commit SHA
	cp "$HOME/.config/var/www/wavelet_files.tar.gz" "$cached_tarball"
	echo "$commitSha" > "$cached_sha_file"
}

check_and_update_ultragrid_continuous(){
	# Checks the UltraGrid continuous build checksum against a cached local copy.
	# Downloads and overwrites the local file if the local checksum differs or file is missing.
	local ug_release_repo="${UG_RELEASE_REPO:-armelvil/UltraGrid}"
	local ug_download_url="https://github.com/${ug_release_repo}/releases/download/continuous/UltraGrid-continuous-x86_64.AppImage"
	local ug_cached_checksum="$HOME/.config/var/www/ultragrid_continuous.sha256"
	local ug_local_file="$HOME/.config/var/www/UltraGrid-continuous-x86_64.AppImage"
	local local_sha256=""
	# Check if the local file exists and compute its checksum
	if [[ ! -f "$ug_local_file" ]]; then
		echo -e "${GREEN}	UltraGrid continuous build not found locally. Downloading...${NC}"
		mkdir -p "$(dirname "$ug_local_file")"
		if ! curl -sL --max-time 120 -o "$ug_local_file" "$ug_download_url"; then
			echo -e "${RED}	Error downloading UltraGrid continuous build! Aborting.${NC}"
			return 1
		fi
		chmod +x "$ug_local_file"
		local_sha256=$(sha256sum "$ug_local_file" | cut -d' ' -f1)
		echo "$local_sha256" > "$ug_cached_checksum"
		echo -e "${GREEN}	UltraGrid continuous build downloaded and cached with checksum: ${local_sha256}${NC}"
		return 0
	fi
	# Compute local checksum and compare with cached checksum
	local_sha256=$(sha256sum "$ug_local_file" | cut -d' ' -f1)
	if [[ -f "$ug_cached_checksum" ]]; then
		cached_sha256=$(cat "$ug_cached_checksum")
		echo -e "	Local checksum:  ${local_sha256}"
		echo -e "	Cached checksum: ${cached_sha256}"
		if [[ "$local_sha256" == "$cached_sha256" ]]; then
			echo -e "${GREEN}	UltraGrid continuous build is verified and up to date.${NC}"
			return 0
		fi
	fi
	echo -e "${RED}	UltraGrid checksum mismatch or no cached checksum! New version available. Downloading...${NC}"


	if ! curl -sL --max-time 120 -o "$ug_local_file" "$ug_download_url"; then
		echo -e "	${RED}	Error downloading UltraGrid continuous build! Aborting.${NC}"
		return 1
	fi
	chmod +x "$ug_local_file"
	local_sha256=$(sha256sum "$ug_local_file" | cut -d' ' -f1)
	echo "$local_sha256" > "$ug_cached_checksum"
	echo -e "${GREEN}	UltraGrid continuous build updated successfully with new checksum: ${local_sha256}${NC}"
}

parse_config_file() {
	local config_file="$1"
	if [[ ! -f "$config_file" ]]; then
		echo -e "${RED}Error: Config file $config_file not found.${NC}"
		return 1
	fi
	echo "	Parsing configuration from $config_file..."
	while IFS='=' read -r key value; do
		[[ "$key" =~ ^[[:space:]]*# ]] && continue
		[[ -z "$key" ]] && continue
		key=$(echo "$key" | xargs)
		value=$(echo "$value" | xargs)
		value="${value#\"}"
		value="${value%\"}"
		value="${value#\'}"
		value="${value%\'}"
		echo "		Parsing Key: $key -- $value"
		case "$key" in
			DEPLOYMENT_MODE) DEPLOYMENT_MODE="$value" ;;
			ROOT_PASSWORD) ROOT_PASSWORD="$value" ;;
			WAVELET_PASSWORD) WAVELET_PASSWORD="$value" ;;
			DOMAIN) domain="$value" ;;
			SVR_IP|SERVER_IP) svr_ip="$value" ;;
			SVR_GW|SERVER_GATEWAY) svr_gw="$value" ;;
			SVR_DNS|SERVER_DNS) svr_dns="$value" ;;
			TIME_ZONE|TIMEZONE) timeZone="$value" ;;
			DEVELOPER_MODE|DEV_MODE) developerMode="$value" ;;
			ENABLE_WIFI) enableWifi="$value" ;;
			WIFI_SSID) wifi_ssid="$value" ;;
			WIFI_BSSID) wifi_bssid="$value" ;;
			WIFI_PASSWORD) wifi_password="$value" ;;
			WIFI_DEVICE_USER) wifi_deviceUser="$value" ;;
			WIFI_DEVICE_PASSWORD) wifi_devicePassword="$value" ;;
			WIFI_IP_ADDR) wifi_ipAddr="$value" ;;
			DEPLOYMENT_REGISTRY) DEPLOYMENT_REGISTRY="$value" ;;
			DEPLOYMENT_IP) DEPLOYMENT_IP="$value" ;;
			PATCH_MODE) patchMode="$value" ;;
			UG_BUILD_TYPE|UGDEV) dev_flag="DEV" ;;
			USE_BOOTC) USE_BOOTC="$value" ;;
		esac
	done < "$config_file"
}


#
## USB install media (see docs/CONF_FIRST_USB_INSTALL_MEDIA.md)
#
# Windows only mounts the first partition of removable media, therefore CONF partition must be physical partition 1.
#
#	Schema:
#   1 CONF (FAT32, 64MiB)  - Windows-editable config
#   2 ESP  (FAT32, 128MiB) - Microsoft-signed shim + signed GRUB + grub.cfg
#   3 LIVE (ISO9660)       - the customized live ISO (install env baked in)
#   4 OFFLINE (ext4)       - FULL mode only, labelled "wavelet-offline" (Optional, full ISO mode only)
#
# The ESP does nothing but chain into the LIVE ISO partition (hardcoded (hd0,gpt3))

cleanup(){
    # WORKDIR holds the staged offline tree plus every partition image, which
    # for a FULL build is several times the size of the final media.  The
    # deliverable is written to ~/Downloads, so this is always safe to drop.
    [[ -n "$WORKDIR" && -d "$WORKDIR" ]] && rm -rf "$WORKDIR"
}
trap cleanup EXIT

populate_conf(){
	# Create the 64MiB FAT32 CONF partition image (Microsoft basic data, so
	# Windows treats it as an ordinary, editable data partition).
	local conf_img="$1"
	rm -f "$conf_img"
	if ! mkfs.vfat -F 32 -n CONF -C "$conf_img" 65536 2>&1 | tail -n 3; then
		echo -e "${RED}	mkfs.vfat failed for CONF partition. Aborting.${NC}"
		return 1
	fi
	# Manifest must match what configure_ignition() reads out of /mnt/conf:
	# the yaml templates at the root, and bin/{butane,mkpasswd,
	# automated_coreos_deployment.sh,wavelet_install_packages.sh}.
	mmd -i "$conf_img" ::/bin
	mcopy -i "$conf_img" -s "./ignition_files/ignition_server.yml" ::/
	mcopy -i "$conf_img" -s "./ignition_files/ignition_decoder.yml" ::/
	mcopy -i "$conf_img" -s "./ignition_files/automated_client_installer.yml" ::/
	mcopy -i "$conf_img" -s "./ignition_files/automated_coreos_deployment.sh" ::/bin/
	mcopy -i "$conf_img" -s "./ignition_files/wavelet_install_packages.sh" ::/bin/
	# Copies in the transpiled coreos installer from earlier
	mcopy -i "$conf_img" -s "./ignition_files/installer.ign" ::/bin/
	mcopy -i "$conf_img" -s "/usr/bin/butane" ::/bin/
	mcopy -i "$conf_img" -s "/usr/bin/mkpasswd" ::/bin/
	if [[ "$DEPLOYMENT_MODE" == "FULL" ]]; then
		mcopy -i "$conf_img" -s "./ignition_files/server_full.yml" ::/
	fi
	if [[ -f "$configFile" ]]; then
		mcopy -i "$conf_img" -s "$configFile" ::/
	else
		echo "	No .conf file provided; place one on the CONF partition before install."
	fi
	# The CA must land at the root of CONF: automated_coreos_deployment.sh
	# copies /mnt/conf/ca.crt into the butane scratch dir for the LAN registry
	# trust anchors, so a subdirectory here silently breaks registry TLS.
	if [[ -f "$CAcert" ]]; then
		mcopy -i "$conf_img" -s "$CAcert" ::/
	fi
	return 0
}

populate_esp(){
	# Create the 128MiB FAT32 ESP with the Fedora Microsoft-signed shim to avoid secure boot issues
	local esp_img="$1"
	local live_iso="$2"
	local efi_dir="$(dirname "$esp_img")/efi"
	rm -f "$esp_img"
	rm -rf "$efi_dir"; mkdir -p "$efi_dir"
	# Extract the hybrid ESP image (contains BOOTX64.EFI/GRUBX64.EFI/MMX64.EFI).
	if ! xorriso -osirrox on -indev "$live_iso" \
			-extract /images/efiboot.img "$efi_dir/efiboot.img" >/dev/null 2>&1; then
		echo -e "${RED}	Failed to extract /images/efiboot.img from $live_iso. Aborting.${NC}"
		return 1
	fi
	if ! mkfs.vfat -F 32 -n "Wavelet" -C "$esp_img" 131072 2>&1 | tail -n 3; then
		echo -e "${RED}	mkfs.vfat failed for ESP partition. Aborting.${NC}"
		return 1
	fi
	mmd -i "$esp_img" ::/EFI ::/EFI/boot
	# The EFI binaries live inside efiboot.img's FAT tree; copy them out by
	# treating it as a filesystem with mcopy.
	local efiboot="$efi_dir/efiboot.img"
	mcopy -i "$efiboot" ::/EFI/BOOT/BOOTX64.EFI "$efi_dir/BOOTX64.EFI"
	mcopy -i "$efiboot" ::/EFI/BOOT/GRUBX64.EFI "$efi_dir/GRUBX64.EFI"
	mcopy -i "$efiboot" ::/EFI/BOOT/MMX64.EFI   "$efi_dir/MMX64.EFI"
	# bootx64.efi must be the Microsoft-signed shim.
	mcopy -i "$esp_img" "$efi_dir/BOOTX64.EFI" ::/EFI/boot/bootx64.efi
	mcopy -i "$esp_img" "$efi_dir/GRUBX64.EFI" ::/EFI/boot/grubx64.efi
	mcopy -i "$esp_img" "$efi_dir/MMX64.EFI"   ::/EFI/boot/mmx64.efi
	return 0
}

write_grub_cfg(){
	# Add a grub cfg to chainload the fedora coreos liveISO partition
	local live_iso="$1"
	local live_part="${2:-gpt3}"
	local live_karg="${3:-}"
	local live_label
	live_label="$(blkid -o value -s LABEL "$live_iso" 2>/dev/null || true)"
	if [[ -z "$live_label" ]]; then
		echo -e "${RED}	Could not determine ISO9660 label of $live_iso (required for coreos.liveiso=). Aborting.${NC}"
		return 1
	fi
	local cfg="$WORKDIR/grub.cfg"
	cat > "$cfg" <<EOF
set timeout=5
set default=0

menuentry "Wavelet CoreOS Live Installer" --id wavelet-live {
    linuxefi (hd0,$live_part)/images/pxeboot/vmlinuz \\
        mitigations=auto,nosmt \\
        ignition.firstboot \\
        ignition.platform.id=metal \\
        coreos.liveiso=$live_label${live_karg:+ $live_karg}
    initrdefi (hd0,$live_part)/images/pxeboot/initrd.img (hd0,$live_part)/images/ignition.img
}
EOF
	LIVE_ISO_LABEL="$live_label"
	return 0
}

#
## FULL mode: offline artifact staging
#
# These build the "wavelet-offline" filesystem (ext4) that holds everything a
# target machine needs to provision with no network at all:
#  CoreOS base images
#  Container images as OCI archives
#  wavelet tarball
#  UltraGrid AppImage
#  FFmpeg RPMs
#
#  on the target it is found by label via /dev/disk/by-label/wavelet-offline

save_iso_images(){
	# Save the newest coreos installer image set (.iso/.img + .sig) to the offline layer.
	mkdir -p "$WORKDIR/offline/iso"
	# Download the Fedora signing key once, stage it on the offline media so the
	# next boot phase (no internet) can import it, then import it here too.
	# Fail hard if the download or import is incomplete - an empty keyring would
	# silently disable signature verification on the target.
	local keyfile="$WORKDIR/offline/iso/fedora.gpg"
	if ! curl -fsSL https://fedoraproject.org/fedora.gpg -o "$keyfile"; then
		echo "	ERROR: failed to download Fedora GPG signing key to $keyfile" >&2
		return 1
	fi
	if ! gpg --import "$keyfile"; then
		echo "	ERROR: failed to import Fedora GPG signing key from $keyfile" >&2
		return 1
	fi
	local newest_ver=""
	# Determine the newest base version across cached coreos images.
	for file in ~/.config/var/www/fedora-coreos-*; do
		[[ -f "$file" ]] || continue
		[[ "$file" == *.sig ]] && continue
		local ver
		ver="$(basename "$file" | sed -n 's/^fedora-coreos-\([0-9.]*\)\..*/\1/p')"
		[[ -n "$ver" ]] || continue
		# version-sort comparison keeps only the highest cached version.
		if [[ -z "$newest_ver" ]] || [[ "$(printf '%s\n%s\n' "$ver" "$newest_ver" | sort -V | tail -n1)" == "$ver" ]]; then
			newest_ver="$ver"
		fi
	done
	[[ -n "$newest_ver" ]] || { echo -e "${RED}	No cached fedora-coreos image found in ~/.config/var/www.${NC}"; return 1; }
	echo "	Copying newest cached CoreOS image set (version $newest_ver).."
	for file in ~/.config/var/www/fedora-coreos-${newest_ver}.*; do
		[[ -f "$file" ]] || continue
		case "$file" in
			*.img|*.iso)
				if [[ ! -f "${file}.sig" ]]; then
					echo "	ERROR: no .sig file provided with this img, cannot verify file integrity!"
					return 1
				fi
				if ! gpg --verify "$file.sig" "$file" >/dev/null 2>&1; then
					echo "ERROR: Signature verification failed" >&2
					return 1
				fi
				cp "$file" "$WORKDIR/offline/iso"; cp "${file}.sig" "$WORKDIR/offline/iso"
				;;
		esac
	done
}

save_registry_images(){
    # Save every image the server will need into $WORKDIR/offline/images/
    # Naming: images/<name>.oci.tar  (loaded later with 'podman load')
    local dest="$1"
    mkdir -p "$dest"
    # Base images the server pushes into its local registry (match
    # build_registry.sh pull_registry_images and install_packages.sh sourceList)
    local images=(
        "quay.io/coreos/etcd:v3.6.4"
        "quay.io/coreos/coreos-installer:release"
        "registry.fedoraproject.org/fedora:latest"
        "docker.io/library/nginx:alpine"
        "docker.io/library/php:fpm"
        "docker.io/redis:latest"
        "docker.io/library/httpd:latest"
        "docker.io/library/registry:latest"
        "quay.io/freeipa/freeipa-server:almalinux-10"
    )
    # Locally built images (exist as localhost/<name> after build_registry.sh)
    # Bootc pathway (FCOS >=45 / USE_BOOTC=1) builds the overlays with a
    # _bootc suffix (docs/UPDATE_TO_BOOTC.md).
    local overlay_suffix=""
    if [[ "${USE_BOOTC:-0}" == "1" ]]; then
        overlay_suffix="_bootc"
    fi
    local built_images=(
        "coreos_overlay_client${overlay_suffix}"
        "coreos_overlay_server${overlay_suffix}"
        "tftpd"
        "tftpboot"
        "isc-kea"
        "radiusd"
        "php-fpm-redis"
    )
    local failed=0
    echo "	Saving base images as OCI archives.."
    for img in "${images[@]}"; do
        # Prefer the localhost/<shortname> tag build_registry.sh created, so the
        # archive round-trips with the tag the server expects; fall back to source ref.
        local short="${img##*/}"
        short="${short%%:*}"
        local ref="localhost/$short"
        podman image exists "$ref" || ref="$img"
        if ! podman image exists "$ref"; then
            echo -e "${RED}	Image $img not present in local podman store (run build_registry.sh first).${NC}"
            failed=1
            continue
        fi
        echo "	  -> $ref  =>  $short.oci.tar"
        if ! podman save --format oci-archive -o "$dest/$short.oci.tar" "$ref"; then
            echo -e "${RED}	  FAILED to save $ref => $short.oci.tar (see error above)${NC}"
            rm -f "$dest/$short.oci.tar"
            failed=1
        fi
    done
    echo "	Saving built overlay/service images as OCI archives.."
    for name in "${built_images[@]}"; do
        if podman image exists "localhost/$name"; then
            echo "	  -> localhost/$name  =>  $name.oci.tar"
            # oci-archive keeps the gzip-compressed layer blobs small for the USB.
            if ! podman save --format oci-archive -o "$dest/$name.oci.tar" "localhost/$name"; then
                echo -e "${RED}	  FAILED to save localhost/$name => $name.oci.tar (see error above)${NC}"
                rm -f "$dest/$name.oci.tar"
                failed=1
            fi
        else
            echo -e "${RED}	Image localhost/$name not present (run build_registry.sh first).${NC}"
            failed=1
        fi
    done
    return $failed
}

download_offline_artifacts(){
    # Fetch the wavelet tarball and UltraGrid AppImage from their internet sources
    local conf="${configFile}"
    local branch="master"
    if [[ -f "$conf" ]] && grep -q '^DEVELOPER_MODE=1' "$conf"; then
        branch="armelvil-working"
    fi
    mkdir -p "$HOME/.config/var/www"
    # Wavelet tarball (reuse a valid cached copy if present)
    local tarball="$HOME/.config/var/www/$branch.tar.gz"
    if [[ -f "$tarball" ]] && tar -tzf "$tarball" >/dev/null 2>&1; then
        echo "	Using cached wavelet tarball for branch $branch.."
    else
        local download_url="https://github.com/Allethrium/wavelet/archive/refs/heads/$branch.tar.gz"
        echo "	Downloading wavelet tarball (branch $branch) from GitHub.."
        if ! curl -s -f -L -o "$tarball" "$download_url"; then
            echo -e "${RED}	Error downloading wavelet tarball! Aborting.${NC}"
            return 1
        fi
        if ! tar -tzf "$tarball" >/dev/null 2>&1; then
            echo -e "${RED}	Downloaded wavelet tarball is not a valid archive! Aborting.${NC}"
            rm -f "$tarball"
            return 1
        fi
    fi
    # UltraGrid continuous AppImage
    if [[ -n "$UGCHECK" ]]; then
    	echo "	Skipping UltraGrid checksum!"
    	return 0
    else
		local ug_repo="${UG_RELEASE_REPO:-armelvil/UltraGrid}"
		local ug_url="https://github.com/${ug_repo}/releases/download/continuous/UltraGrid-continuous-x86_64.AppImage"
		local ug_file="$HOME/.config/var/www/UltraGrid-continuous-x86_64.AppImage"
		if [[ -f "$ug_file" ]]; then
			echo "	Using cached UltraGrid AppImage.."
		else
			echo "	Downloading UltraGrid continuous build from GitHub ($ug_repo).."
			if ! curl -sL --max-time 120 -o "$ug_file" "$ug_url"; then
				echo -e "${RED}	Error downloading UltraGrid continuous build! Aborting.${NC}"
				rm -f "$ug_file"
				return 1
			fi
			chmod +x "$ug_file"
		fi
		return 0
	fi
}

stage_offline_artifacts(){
    local src_dir="$1"
    local dest="$2"
    mkdir -p "$dest/rpms"
    local branch="master"
    local conf="${configFile}"
    if [[ -f "$conf" ]] && grep -q '^DEVELOPER_MODE=1' "$conf"; then
        branch="armelvil-working"
    fi
    local tarball="$HOME/.config/var/www/$branch.tar.gz"
    if [[ ! -f "$tarball" ]]; then
        echo -e "${RED}	Wavelet tarball missing at $tarball (download step failed?).${NC}"
        return 1
    fi
    echo "	Staging $(basename "$tarball").."
    cp "$tarball" "$dest/wavelet_files.tar.gz"
    # UltraGrid AppImage - downloaded by download_offline_artifacts() above.
    local appimage="$HOME/.config/var/www/UltraGrid-continuous-x86_64.AppImage"
    # TODO ensure AppImage size is healthy - >150mb
    if [[ ! -f "$appimage" ]]; then
        echo -e "${RED}	UltraGrid AppImage missing at $appimage (download step failed?).${NC}"
        return 1
    fi
    echo "	Staging $(basename "$appimage").."
    cp "$appimage" "$dest/UltraGrid.AppImage"
    # FFmpeg RPMs
    if ls "$HOME/.config/var/www"/rpms/*.rpm >/dev/null 2>&1; then
        echo "	Staging FFmpeg RPMs.."
        cp "$HOME/.config/var/www"/rpms/*.rpm "$dest/rpms/" || return 1
    else
        echo -e "${RED}	No FFmpeg RPMs found in ~/.config/var/www/rpms.${NC}"
        return 1
    fi
    return 0
}

build_offline_partition(){
    # Stage the full offline tree and materialise it as a single ext4 partition
    # image labelled "wavelet-offline" (the label the target mounts by).  Returns
    # the image size in MiB via the global OFFLINE_MIB.
    mkdir -p "$WORKDIR/offline"
    save_iso_images || return 1
    if ! download_offline_artifacts; then
        echo -e "${RED}	Failed to download offline artifacts (tarball/AppImage). Aborting.${NC}"
        return 1
    fi
    if ! save_registry_images "$WORKDIR/offline/images"; then
        echo -e "${RED}	One or more images could not be saved, media would be incomplete. Aborting.${NC}"
        return 1
    fi
    if ! stage_offline_artifacts "$waveletdir" "$WORKDIR/offline"; then
        echo -e "${RED}	Failed to stage offline artifacts. Aborting.${NC}"
        return 1
    fi
    # Size: the offline tree + 10% margin, rounded up to whole MiB.
    local offline_bytes part_img
    offline_bytes="$(du -sb "$WORKDIR/offline" | cut -f1)"
    OFFLINE_MIB=$(( (offline_bytes + offline_bytes / 10) / 1024 / 1024 + 1 ))
    part_img="$WORKDIR/offline.img"
    rm -f "$part_img"
    echo "	Creating ${OFFLINE_MIB}MiB ext4 partition image for offline data.."
    if ! mkfs.ext4 -L wavelet-offline -F -d "$WORKDIR/offline" "$part_img" "${OFFLINE_MIB}M" 2>&1 | tail -n 3; then
        echo -e "${RED}	mkfs.ext4 failed for offline partition image. Aborting.${NC}"
        rm -f "$part_img"
        return 1
    fi
    [[ -f "$part_img" ]]
}

build_image(){
	# All filesystems are built as standalone images, then dd-ed into a master image at whole-MiB offsets
	#
	# Layout:
	#   1 CONF (FAT32, 64MiB)  - Windows-editable config
	#   2 ESP  (FAT32, 128MiB) - shim + grub + grub.cfg (extracted from ISO)
	#   3 LIVE (ISO9660)       - the customized live ISO, booted as if whole
	#	**OPTIONAL**
	#   4 OFFLINE (ext4)       - FULL mode only: all provisioning data, labelled "wavelet-offline"
	#
	echo -e "\n **	Building GPT USB install image (${DEPLOYMENT_MODE}) **\n"
	local base_iso="${1:-}"
	if [[ -z "$base_iso" ]]; then
		base_iso="$(find_base_isos)" ## FIX THIS
		if [[ -z "$base_iso" ]]; then
			echo -e "${RED}	No valid CoreOS live ISO found for build. Aborting.${NC}"
			return 1
		fi
	fi
	echo "	Using base ISO: $base_iso"
	# Generate the bootstrap ignition from the Butane source.
	butane --pretty --files-dir "./ignition_files/" \
		"./ignition_files/bootstrap_installer.yml" \
		--output "./ignition_files/installer.ign" || return 1
	WORKDIR="/var/tmp/wavelet_conf_first"
	rm -rf "$WORKDIR"; mkdir -p "$WORKDIR"
	local conf_img="$WORKDIR/conf.img"
	local esp_img="$WORKDIR/esp.img"
	local live_img="$WORKDIR/live.iso"
	# FULL mode has no network at the install site, so everything must be
	# staged up-front.  Do this before laying out the image so we know its size,
	# and fail early (this is the slow, bandwidth-heavy part).
	OFFLINE_MIB=0
	local offline_img=""
	if [[ "$DEPLOYMENT_MODE" == "FULL" ]]; then
		local src_bytes
		src_bytes="$(stat -c%s "$base_iso")"
		# Only a hint - mkfs sizes the real thing.  The offline tree dominates.
		src_bytes=$(( src_bytes * 3 ))
		local out_dir
		out_dir="$(dirname "$WORKDIR")"
		local avail_bytes out_fs
		avail_bytes="$(df -B1 --output=avail "$out_dir" | tail -n1)"
		out_fs="$(df --output=target "$out_dir" | tail -n1)"
		if (( avail_bytes < src_bytes )); then
			echo -e "${RED}	Probably not enough free space on ${out_fs} for a FULL build"
			echo "	(need a few GiB for the offline tree; $(( avail_bytes / 1024 / 1024 / 1024 ))GiB available).${NC}"
			echo "	Free up space, or run the build with TMPDIR pointing at a larger filesystem."
			return 1
		fi
		echo "	Staging offline artifacts for FULL mode (no internet needed at install site).."
		build_offline_partition || return 1
		offline_img="$WORKDIR/offline.img"
	fi
	# The live install environment is baked into the ISO itself by
	# coreos-installer, so the LIVE partition is a customized copy of the ISO
	# with the bootstrap ignition merged in - no separate kernel/initrd needed.
	echo "	Customizing live ISO with bootstrap ignition.."
	if ! coreos-installer iso customize \
			--live-ignition "./ignition_files/installer.ign" \
			-o "$live_img" "$base_iso"; then
		echo -e "${RED}	coreos-installer iso customize failed. Aborting.${NC}"
		return 1
	fi
	echo "	Building CONF partition.."
	populate_conf "$conf_img" || return 1
	echo "	Building ESP partition (extracted from ISO).."
	populate_esp "$esp_img" "$base_iso" || return 1
	# LIVE is always gpt3 (CONF=1, ESP=2, LIVE=3, OFFLINE=4) - a build-time constant.
	# STANDALONE provisions on an isolated network with no DHCP server, so pin a
	# static IP in the live env rather than timing out on DHCP.  This must go in
	# grub.cfg: it is what supplies the live kargs.
	local live_karg=""
	if [[ "$DEPLOYMENT_MODE" == "STANDALONE" ]]; then
		live_karg="ip=192.168.1.32::192.168.1.1:255.255.255.0:svr::none"
	fi
	write_grub_cfg "$live_img" "gpt3" "$live_karg" || return 1
	# Overwrite the stub grub.cfg with our custom one.
	mcopy -o -i "$esp_img" "$WORKDIR/grub.cfg" ::/EFI/boot/grub.cfg
	# Compute partition geometry (whole MiB) and master image size.
	local iso_bytes
	iso_bytes="$(stat -c%s "$live_img")"
	# P1 @1MiB(64M), P2 @65MiB(128M), P3 (LIVE) after ESP, P4 (OFFLINE) after LIVE.
	local conf_mib=64 esp_mib=128
	local live_mib=$(( (iso_bytes + 1048575) / 1048576 ))
	local p3_start=$(( 1 + conf_mib + esp_mib ))
	local p4_start=$(( p3_start + live_mib ))
	local total_mib=$(( p3_start + live_mib + OFFLINE_MIB + 1 ))
	local out_name="wavelet_installer"
	case "$DEPLOYMENT_MODE" in
		FULL) out_name="wavelet_installer_full" ;;
		LAN) out_name="wavelet_installer_lan" ;;
		STANDALONE) out_name="wavelet_installer_standalone" ;;
	esac
	local master="$HOME/Downloads/${out_name}.img"
	rm -f "$master"
	echo "	Creating master image (${total_mib}MiB) with GPT table.."
	dd if=/dev/zero of="$master" bs=1M count="$total_mib" status=none || return 1
	# Build the sfdisk script; the OFFLINE partition is only present in FULL mode.
	local sfdisk_script="label: gpt
1MiB, ${conf_mib}MiB, EBD0A0A2-B9E5-4433-87C0-68B6B72699C7
, ${esp_mib}MiB, uefi
, ${live_mib}MiB, linux
"
	[[ -n "$offline_img" ]] && sfdisk_script+=", ${OFFLINE_MIB}MiB, linux"
	sfdisk -X gpt --wipe=always "$master" <<<"$sfdisk_script" || return 1
	# Name the ESP partition (2) so firmware that reads the GPT partition name
	# shows a recognizable boot entry instead of the raw USB product string.
	sgdisk --change-name=2:"Wavelet Installer" "$master" || return 1
	echo "	Writing partition images at their assigned MiB offsets.."
	dd if="$conf_img" of="$master" bs=1M seek=1 conv=notrunc status=none
	dd if="$esp_img" of="$master" bs=1M seek=$((1 + conf_mib)) conv=notrunc status=none
	dd if="$live_img" of="$master" bs=1M seek="$p3_start" conv=notrunc status=none
	if [[ -n "$offline_img" ]]; then
		echo "	Writing offline partition (${OFFLINE_MIB}MiB).."
		dd if="$offline_img" of="$master" bs=1M seek="$p4_start" conv=notrunc status=none
	fi
	echo "	Final partition table:"
	sfdisk -l "$master"
	local size_gib=$(( $(stat -c%s "$master") / 1024 / 1024 / 1024 ))
	echo -e "\n${GREEN}	USB image generated: $master (${size_gib}GiB)${NC}"
	echo "	LIVE ISO label: $LIVE_ISO_LABEL"
	echo "
	Deployment instructions:
	  1. Flash $master to USB (dd or Rufus in raw mode).
	  2. On Windows, edit the .conf file on the CONF partition (drive letter appears immediately).
	  3. Boot the target from the USB and LEAVE THE USB PLUGGED IN.
	  4. First boot customizes the ignition from the .conf file and installs${offline_img:+ fully offline}.
	  5. After provisioning completes, the USB may be removed."
	return 0
}

check_required_tools(){
    local missing=()
    # mkfs.ext4/gpg are only exercised by FULL mode, but failing up-front beats
    # discovering it after an hour of pulling container images.
    for cmd in podman sfdisk sgdisk butane coreos-installer dd xorriso mkfs.vfat \
               mkfs.ext4 blkid mcopy mmd gpg file curl; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Missing required tools: ${missing[*]}${NC}"
        echo -e "${GREEN}Fedora/RHEL: sudo dnf install podman util-linux gdisk butane coreos-installer xorriso dosfstools e2fsprogs mtools gnupg file curl${NC}"
        echo -e "${GREEN}Debian/Ubuntu: sudo apt install podman fdisk gdisk butane coreos-installer xorriso dosfstools e2fsprogs mtools gnupg file curl${NC}"
        return 1
    fi
}

iso_is_valid(){
	# Ensure the CoreOS ISO is valid
	[[ -f "$1" ]] || return 1
	file -b "$1" | grep -q "ISO 9660"
}

find_base_isos(){
	# Checks for ISO file corruption
	local d f ver sig paired=()
	for d in "$@"; do
		[[ -d "$d" ]] || continue
		for f in "$d"/fedora-coreos-*-live-iso.x86_64.iso; do
			[[ -f "$f" ]] || continue
			sig="${f}.sig"
			if [[ ! -f "$sig" ]]; then
				echo "	Skipping $f: no .sig file, cannot verify integrity" >&2
				continue
			fi
			if ! iso_is_valid "$f"; then
				echo "	Skipping invalid ISO: $f" >&2
				continue
			fi
			# Key the sort on the version, not the path, so a directory name
			# can never outrank the build number.
			ver="$(basename "$f" | sed -n 's/^fedora-coreos-\([0-9.]*\)-.*/\1/p')"
			[[ -n "$ver" ]] || continue
			paired+=("$ver	$f")
		done
	done
	[[ ${#paired[@]} -gt 0 ]] || return 1
	# newest version first
	while IFS=$'\t' read -r _ f; do
		echo "$f"
	done < <(printf '%s\n' "${paired[@]}" | sort -V | tac)
}

coreos_installer(){
	# Generates the coreos image with automated installer
	local search_dirs=()
	if [[ "$DEPLOYMENT_MODE" == "STANDALONE" ]]; then
		echo -e "	Running in network isolation mode..\n"
		search_dirs+=("$HOME/Downloads")
	else
		if [[ -n "$DEPLOYMENT_SERVER" ]]; then
			# A deployment server already has the ISO available, we use that
			search_dirs+=("${HOME}/.config/var/www")
			echo "	Deployment mode active, checking for files in httpd resource directory: $REGISTRY_DIR"
		fi
		# There is no "else" - full ISO build mode implies LAN deployment is already available.
		search_dirs+=("${HOME}/.config/var/www")
	fi

	if [[ ! -d "$HOME/Downloads" ]]; then
		mkdir -p "$HOME/Downloads"
	fi
	FILEPREFIX="fedora-coreos-"
	# Check for any other CoreOS files that might be older builds or different formats
	OTHER_COREOS_FILES=()
    for d in "${search_dirs[@]}"; do
    	[[ -d "$d" ]] || continue
    	for f in "$d"/$FILEPREFIX*; do
    		[[ -f "$f" ]] || continue
    		basename_f=$(basename "$f")
    		if [[ "$basename_f" == *"live-iso.x86_64.iso"* ]]; then
    			# Already captured in EXISTING_FILES
    			continue
    		else
    			OTHER_COREOS_FILES+=("$f")
    		fi
    	done
    done
    DOWNLOAD_NEEDED=0
    mapfile -t EXISTING_FILES < <(find_base_isos "${search_dirs[@]}" "$HOME/.config/var/www" "$HOME/Downloads" 2>/dev/null)
    if [[ ${#EXISTING_FILES[@]} -eq 0 ]]; then
    	echo -e "\n	No valid CoreOS files found, downloading CoreOS metal raw image from internet, please be patient while this task executes..\n"
    	DOWNLOAD_NEEDED=1
    else
    	echo "	Valid CoreOS images/components already exist."
    fi
   	# Download if needed
   	if [[ $DOWNLOAD_NEEDED -eq 1 ]]; then
   		# Using the podman container for consistency with build_registry.sh
   		REGISTRY_REF="quay.io/coreos/coreos-installer:latest"
   		podman run --security-opt label=disable \
   			--pull=always \
   			--rm \
   			-v /tmp:/data -w /data \
   			"$REGISTRY_REF" download -s stable -a x86_64 -p metal -f iso
   		# Move the downloaded ISO to the first candidate location for future use
   		DOWNLOADED_FILE=$(ls /tmp/fedora-coreos-*-live-iso.x86_64.iso 2>/dev/null | head -n1)
   		if [[ -n "$DOWNLOADED_FILE" ]]; then
   			mv "$DOWNLOADED_FILE" "${search_dirs[0]}/" 2>/dev/null || true
   			# Notify about older builds if they exist
   			if [[ ${#OTHER_COREOS_FILES[@]} -gt 0 ]]; then
   				echo -e "\n	**	Note: Older CoreOS build(s) or files exist:"
   				for old_file in "${OTHER_COREOS_FILES[@]}"; do
   					echo "	   - $(basename "$old_file")"
   				done
   				echo "	Consider cleaning up older builds if they are no longer needed."
   			fi
   		fi
   		# Re-scan now that the download has landed in a candidate directory.
   		mapfile -t EXISTING_FILES < <(find_base_isos "${search_dirs[@]}" "$HOME/.config/var/www" "$HOME/Downloads" 2>/dev/null)
   	fi
    # Use the newest valid candidate.
    IMAGEFILE="${EXISTING_FILES[0]:-}"
    if [[ -z "$IMAGEFILE" ]]; then
    	echo "	Error: No valid CoreOS live ISO found in ${search_dirs[*]}, ~/.config/var/www or ~/Downloads."
    	echo "	A usable image needs fedora-coreos-<version>-live-iso.x86_64.iso plus its .sig."
    	return 1
    fi
    if [[ ${#EXISTING_FILES[@]} -gt 1 ]]; then
    	echo "	Available CoreOS live ISOs (newest first):"
    	for f in "${EXISTING_FILES[@]}"; do echo "	   - $(basename "$f")"; done
    fi
    echo "	Using base ISO: $IMAGEFILE"
	echo "	Generating Ignition files with Butane"
	# Generate butane setting files-dir to current path
	# This is so that we can utilize the local files argument in server_custom.yml to inject the necessary files from /ignition subdir
	# NEW - using automated-installer.yml for everything here now.
	embedDir="./ignition_files/"
	ymlSource="$embedDir/bootstrap_installer.yml"
	outputIgn="$embedDir/installer.ign"
	butane --pretty --files-dir "$embedDir" "$ymlSource" --output "$outputIgn"
	build_image "$IMAGEFILE"
}


####
#
# Main
#
####


waveletdir="$(pwd)"
# We generally want stdout here instead of a log.
#exec >$waveletdir/logs/server_bootstrap.log 2>&1
echo "	Input Args: "; echo "	${*}"
timeZone=""

for i in "$@"
	do
		case $i in
			-d|--dev)
				echo -e "${RED}Dev mode enabled, switching git tree to working branch${NC}"	;	developerMode="1"
				;;
			-h|--help)
				print_help
				;;
			-p=*|--password=*|--pass=*)
				# TODO - split to SU and wavelet user options so we get different passwords.  LATER.  right now we are still labbing!
				ROOT_PASSWORD="${i#*=}"; WAVELET_PASSWORD="${i#*=}"; echo -e "	Passwords defined for BOTH user accounts as: ${ROOT_PASSWORD}"
				;;
			-ws=*|--wifissid=*)
				wifi_ssid=${i#*=}; echo -e "	WiFi SSID defined as: ${wifi_ssid}";
				;;
			-wb=*|--wifibssid=*)
				wifi_bssid=${i#*=}; echo -e "	WiFi BSSID/MAC defined as: ${wifi_bssid}";
				;;
			-wip=*|--wifiapip=*)
				wifi_ipAddr=${i#*=}; echo -e "	WiFi Access Point IP defined as: ${wifi_ipAddr}"
				;;
			-wp=*|--wifipass=*)
				wifi_password=${i#*=}; echo -e "	WiFi WPA PSK defined as: ${wifi_password}";
				;;
			-wap=*|--wifiappass=*)
				wifi_devicePassword=${i#*=}; echo -e "WiFi AP Password: ${wifi_devicePassword}";
				;;
			-wau=*|--wifiapuser=*)
				wifi_deviceUser=${i#*=}; echo -e "WiFi AP User: ${wifi_deviceUser}";
				;;
			-enablewifi)
				enableWifi="1"; echo -e "	WiFi mode enabled. WiFi parameters will be written to ignition files.";
				;;
			-domain=*)	domain=${i#*=}; echo -e "Target domain: ${domain}";
				;;
			-ip=*|--serverip=*)
				svr_ip=${i#*=}; echo -e "	Server Static IPv4 defined as ${svr_ip}";
				;;
			-g=*|--servergateway=*)
				svr_gw=${i#*=}; echo -e "	Server IPv4 gateway defined as ${svr_gw}";
				;;
			-dns=*|--serverdns=*)
				svr_dns=${i#*=}; echo -e "	Server IPv4 dns defined as ${svr_dns}";
				;;
     	    -reg=*|--localregistry=*)
				registry=${i#*=}; echo -e "	Local registry defined as IP ${registry}";
				;;
            -b|--patched)
            	patchMode="ON"; echo -e "	Pulling from patched UG branch";
            	;;
            -t=*|--timezone=*)
            	timeZone=${i#*=}; echo -e "	Timezone set to $timeZone (default to America/New_York if empty)";
            	;;
			-c=*|--config=*)
				configFile=${i#*=}; echo -e "	Extracting configuration from defined config file: ${configFile}"
				;;
			-u|--unattend)
				UNATTENDED_INSTALL="1"
				echo "	Unattend flag enabled, server will not wait to setup DHCP, DNS and IdM services during bootstrap!"
				;;
			--full|--DEPLOYMENT_MODE=FULL)
				echo "	Building full offline installation!"
				DEPLOYMENT_MODE="FULL"
				;;
			*)
				echo "bad input argument: $i";
				;;
		esac
done


if [[ -z "$timeZone" ]]; then
	timeZone="America/New_York"
fi

if [[ -z "$configFile" ]]; then
	requiredOptions=(
		"ROOT_PASSWORD"
		"WAVELET_PASSWORD"
		"domain"
		"svr_gw"
		"DEPLOYMENT_MODE"
		"svr_ip"
		"svr_dns"
		)
else
	# Parse the configFile for all options
	parse_config_file "$configFile" || exit 1
	requiredOptions=() # Options already set via config file
fi

DEPLOYMENT_MODE="$(echo "${DEPLOYMENT_MODE:-STANDALONE}" | tr '[:lower:]' '[:upper:]')"

# Test for required options from either the configFile or direct args.
if [[ ${#requiredOptions[@]} -gt 0 ]]; then
	for opt in "${requiredOptions[@]}"; do
		echo "Option: $opt is set!"
		if [[ -z "${!opt}" ]]; then
			echo -e "\n\n${RED} ERROR:	The install option '$opt' must be defined!
			\n	Aborting installation as process will fail without these data.${NC}\n\n"
			exit 1
		fi
	done
fi

if [[ $domain == *".local" ]]; then
	echo -e "\n${RED}	.local TLD domain is reserved for mDNS, please select another domain or subdomain, preferably one from your organization's domain"
	echo -e "${RED}	Failure to do this may result in unpredictable behavior with local name resolution.${NC}"
	exit 1
fi

echo "	Dev mode is now enabled by default due to the need for running a customized UltraGrid AppImage.."
# Yes, this is supposed to be forced.
dev_flag="DEV";

if [[ -z "$configFile" ]]; then
	echo -e "${RED}	A configuration file (--config=<file>) must be provided.${NC}"
	print_help
fi

# Check tooling before any work so we fail fast and clean
check_required_tools || exit 1

if [[ "$DEPLOYMENT_MODE" == "FULL" ]] || [[ "$DEPLOYMENT_MODE" == "LAN" ]]; then
	get_publicinterface || exit 1
	if [[ -z "$DEPLOYMENT_IP" ]]; then
		# We specified a registry, but not a deployment registry IP.  resolve it here
    	if [[ -n "${ip:-}" ]]; then
    		DEPLOYMENT_IP="$ip"
    	else
    		# for some reason get_publicInterface failed, fallback to hostname -I
    		DEPLOYMENT_IP="$(hostname -I | awk '{print $1}')"
    	fi
	fi
	validate_ip_port "$DEPLOYMENT_IP" || exit 1
	# Always update to latest wavelet source from github or other official repo
	download_wavelet_git || exit 1
	if [[ "$UGCHECK" == 0 ]]; then
		check_and_update_ultragrid_continuous || exit 1
	fi
	# Add the LAN CA to the ignition folder if present (consumed by the CONF partition).
	CAcert="$HOME/.config/var/ssl/certs/ca.crt"
	if [[ -f "$CAcert" ]]; then
		cp -f "$CAcert" "ignition_files/ca.crt"
	fi
	coreos_installer || exit 1
else
	echo "	Local registry option not defined, additional config not required.."
	coreos_installer || exit 1
fi

echo -e "${GREEN}	Bootstrap installation complete, please ensure a valid .conf file exists on the USB install media CONF partition.${NC}"