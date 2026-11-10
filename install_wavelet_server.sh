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
  		exit 1
	fi
	if curl -sk -s "https://$registry_port/v2" > /dev/null; then
		echo -e "${GREEN}	Registry running and responding to curl!${NC}"
	else
		echo -e "${RED}	Registry not responding, please verify your settings..${NC}"
		exit 1
	fi
}

get_publicinterface(){
	# Tries to get the active network interface, may sometimes get it wrong.
	iface_route="$(ip -4 route show default | sort -nk1,1 | head -n1)"
	if [[ -z "$iface_route" ]]; then
		echo "	No default IPv4 route found. Cannot determine public interface."
		exit 1
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
	local cached_tarball="$HOME/.config/var/www/${GH_BRANCH}_cached.tar.gz"
	local cached_sha_file="$HOME/.config/var/www/${GH_BRANCH}_sha256.txt"
	if [[ -f "$cached_tarball" ]] && [[ -f "$cached_sha_file" ]]; then
		cached_sha=$(cat "$cached_sha_file")
		if [[ "$cached_sha" == "$commitSha" ]]; then
			# Validate the cached tarball is a valid tar.gz archive
			if tar -tzf "$cached_tarball" > /dev/null 2>&1; then
				echo "	Using cached wavelet tarball with matching commit SHA: $commitSha"
				cp "$cached_tarball" "$HOME/.config/var/www/$GH_BRANCH.tar.gz"
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
		exit 1
	fi
	# Validate the downloaded file is a valid tar.gz archive
	if ! tar -tzf "$HOME/.config/var/www/$GH_BRANCH.tar.gz" > /dev/null 2>&1; then
		echo "	Error: Downloaded file is not a valid tar.gz archive!"
		echo "	File size: $(wc -c < "$HOME/.config/var/www/$GH_BRANCH.tar.gz") bytes"
		echo "	First 200 bytes:"
		head -c 200 "$HOME/.config/var/www/$GH_BRANCH.tar.gz" | cat -v
		rm -f "$HOME/.config/var/www/$GH_BRANCH.tar.gz"
		exit 1
	fi
	# Compute SHA256 of the downloaded tarball
	local tarballSha256
	tarballSha256=$(sha256sum "$HOME/.config/var/www/$GH_BRANCH.tar.gz" | cut -d' ' -f1)
	echo "	Tarball SHA256: $tarballSha256"
	# Cache the tarball and its commit SHA
	cp "$HOME/.config/var/www/$GH_BRANCH.tar.gz" "$cached_tarball"
	echo "$commitSha" > "$cached_sha_file"
}

check_and_update_ultragrid_continuous(){
	# Checks the UltraGrid continuous build checksum against a cached local copy.
	# Downloads and overwrites the local file if the local checksum differs or file is missing.
	local ug_release_repo="${UG_RELEASE_REPO:-armelvil/UltraGrid}"
	local ug_download_url="https://github.com/${ug_release_repo}/releases/download/continuous/UltraGrid-continuous-x86_64.AppImage"
	local ug_cached_checksum="/var/home/wavelet/config/.ultragrid_continuous.sha256"
	local ug_local_file="${WAVELET_HTTP_DIR:-/home/wavelet/http}/UltraGrid-continuous-x86_64.AppImage"
	local local_sha256=""
	# Check if the local file exists and compute its checksum
	if [[ ! -f "$ug_local_file" ]]; then
		echo -e "	${GREEN}	UltraGrid continuous build not found locally. Downloading...${NC}"
		mkdir -p "$(dirname "$ug_local_file")"
		if ! curl -sL --max-time 120 -o "$ug_local_file" "$ug_download_url"; then
			echo -e "	${RED}	Error downloading UltraGrid continuous build! Aborting.${NC}"
			exit 1
		fi
		chmod +x "$ug_local_file"
		local_sha256=$(sha256sum "$ug_local_file" | cut -d' ' -f1)
		echo "$local_sha256" > "$ug_cached_checksum"
		echo -e "	${GREEN}	UltraGrid continuous build downloaded and cached with checksum: ${local_sha256}${NC}"
		return 0
	fi
	# Compute local checksum and compare with cached checksum
	local_sha256=$(sha256sum "$ug_local_file" | cut -d' ' -f1)
	if [[ -f "$ug_cached_checksum" ]]; then
		cached_sha256=$(cat "$ug_cached_checksum")
		echo -e "	Local checksum:  ${local_sha256}"
		echo -e "	Cached checksum: ${cached_sha256}"
		if [[ "$local_sha256" == "$cached_sha256" ]]; then
			echo -e "	${GREEN}	UltraGrid continuous build is verified and up to date.${NC}"
			return 0
		fi
	fi
	echo -e "	${RED}	UltraGrid checksum mismatch or no cached checksum! New version available. Downloading...${NC}"
	if ! curl -sL --max-time 120 -o "$ug_local_file" "$ug_download_url"; then
		echo -e "	${RED}	Error downloading UltraGrid continuous build! Aborting.${NC}"
		exit 1
	fi
	chmod +x "$ug_local_file"
	local_sha256=$(sha256sum "$ug_local_file" | cut -d' ' -f1)
	echo "$local_sha256" > "$ug_cached_checksum"
	echo -e "	${GREEN}	UltraGrid continuous build updated successfully with new checksum: ${local_sha256}${NC}"
}

parse_config_file() {
	local config_file="$1"
	if [[ ! -f "$config_file" ]]; then
		echo -e "${RED}Error: Config file $config_file not found.${NC}"
		exit 1
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
## These functions are for build_full_iso mode
#

build_full_iso_main(){
	# Adds the offline files layer to the ISO file as an additional partition.
	# At this point, we already have wavelet_installer.iso available, so all we need to do is append the datadirs.
    echo -e "\n **	Building FULL wavelet server ISO (no internet required at install site) **\n"
    SRC_ISO="$HOME/Downloads/wavelet_server_installer.iso"
    if [[ ! -f "$SRC_ISO" ]]; then
    	echo "	${RED}	ERR: installer source ISO missing!"
    	exit 1
    fi
    OUT_ISO="/var/tmp/wavelet_installer_full_tmp.iso"
    echo "	Source ISO: $SRC_ISO"
    echo "	Output ISO: $OUT_ISO"
	ISO_ROOT="/var/tmp/offline"; mkdir -p "$ISO_ROOT"
	echo "	Temporary folder located at: $ISO_ROOT"
    mkdir -p "$ISO_ROOT/offline"
    save_iso_images
    if ! download_offline_artifacts; then
        echo -e "${RED}	Failed to download offline artifacts (tarball/AppImage). Aborting.${NC}"
        exit 1
    fi
    if ! save_registry_images "$ISO_ROOT/offline/images"; then
        echo -e "${RED}	One or more images could not be saved, ISO would be incomplete. Aborting.${NC}"
        exit 1
    fi
    if ! stage_offline_artifacts "$waveletdir" "$ISO_ROOT/offline"; then
        echo -e "${RED}	Failed to stage offline artifacts. Aborting.${NC}"
        exit 1
    fi
    # Ensure we have disk space on this machine to properly generate the ISO.
    tmp_bytes=$(( $(stat -c%s "$SRC_ISO") ))
    offline_bytes=$(( $(du -sb "$ISO_ROOT/offline" | cut -f1) ))
    needed_bytes=$(( tmp_bytes + offline_bytes + tmp_bytes / 10 ))
    out_fs="$(df --output=target "$(dirname "$OUT_ISO")" | tail -n1)"
    avail_bytes="$(df -B1 --output=avail "$(dirname "$OUT_ISO")" | tail -n1)"
    needed_gib=$(( needed_bytes / 1024 / 1024 / 1024 ))
    avail_gib=$(( avail_bytes / 1024 / 1024 / 1024 ))
    echo "	Free space check: need ~${needed_gib}GiB, ${avail_gib}GiB available on ${out_fs}"
    if (( avail_bytes < needed_bytes )); then
        echo -e "${RED}	Not enough free space on ${out_fs} for the output ISO (need ~${needed_gib}GiB, have ${avail_gib}GiB).${NC}"
        echo "	Free up space, or point OUT_ISO at another filesystem:"
        echo "	  OUT_ISO=/path/on/bigger/disk/wavelet_installer.iso $0"
        rm -f "$OUT_ISO"
        exit 1
    fi
    append_offline_partition "$SRC_ISO" "$OUT_ISO" || {
        echo -e "${RED}	xorriso failed to build output ISO. Aborting.${NC}"
        exit 1
    }
    size_gib=$(( $(stat -c%s "$OUT_ISO") / 1024 / 1024 / 1024 ))
    # overwrite the original source with the newly generated file.
    mv "$OUT_ISO" "$HOME/Downloads/wavelet_installer_full.iso"
    echo -e "\n${GREEN}	Full ISO generated: $SRC_ISO (${size_gib}GiB)${NC}"
    echo -e "\n	Deployment instructions:"
    echo "	  1. Flash $OUT_ISO to USB"
    echo "	  2. Boot the target machine from the USB and LEAVE THE USB PLUGGED IN."
    echo "	  3. First boot installs to disk fully offline (all images are embedded)."
    echo "	  4. When prompted on the console, confirm the machine is on its own isolated network."
    echo "	  5. After provisioning completes, the USB may be removed."
}

cleanup(){
    [[ -n "$ISO_ROOT" && -d "$ISO_ROOT" ]] && rm -rf "$ISO_ROOT"
}
trap cleanup EXIT

check_required_tools(){
    local missing=()
    for cmd in podman xorriso butane coreos-installer; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Missing required tools: ${missing[*]}${NC}"
        echo -e "${GREEN}Fedora/RHEL: sudo dnf install podman xorriso butane coreos-installer${NC}"
        echo -e "${GREEN}Debian/Ubuntu: sudo apt install podman xorriso butane coreos-installer${NC}"
        exit 1
    fi
}

save_iso_images(){
	# Save the newest coreos installer image set (.iso/.img + .sig) to the installer drive.
	mkdir -p "$ISO_ROOT/offline/iso"
	curl -fsSL https://fedoraproject.org/fedora.gpg | gpg --import
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
					exit 1
				fi
				if ! gpg --verify "$file.sig" "$file" >/dev/null 2>&1; then
					echo "ERROR: Signature verification failed" >&2
					exit 1
				fi
				# copy to ISO
				cp "$file" "$ISO_ROOT/offline/iso"; cp "${file}.sig" "$ISO_ROOT/offline/iso"
				;;
		esac
	done
}

save_registry_images(){
    # Save every image the server will need into $ISO_ROOT/offline/images/
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
        podman save --format oci-archive -o "$dest/$short.oci.tar" "$ref" || failed=1
    done
    echo "	Saving built overlay/service images as OCI archives.."
    for name in "${built_images[@]}"; do
        if podman image exists "localhost/$name"; then
            echo "	  -> localhost/$name  =>  $name.oci.tar"
            # oci-archive keeps the gzip-compressed layer blobs small for the USB.
            podman save --format oci-archive -o "$dest/$name.oci.tar" "localhost/$name" || failed=1
        else
            echo -e "${RED}	Image localhost/$name not present (run build_registry.sh first).${NC}"
            failed=1
        fi
    done
    return $failed
}

download_offline_artifacts(){
    # Fetch the wavelet tarball and UltraGrid AppImage from their internet sources
    local conf="$waveletdir/ignition_files/wavelet.conf"
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
}

stage_offline_artifacts(){
    local src_dir="$1"
    local dest="$2"
    mkdir -p "$dest/rpms"
    local branch="master"
    local conf="$src_dir/ignition_files/wavelet.conf"
    if [[ -f "$conf" ]] && grep -q '^DEVELOPER_MODE=1' "$conf"; then
        branch="armelvil-working"
    fi
    local tarball="$HOME/.config/var/www/$branch.tar.gz"
    if [[ ! -f "$tarball" ]]; then
        echo -e "${RED}	Wavelet tarball missing at $tarball (download step failed?).${NC}"
        return 1
    fi
    echo "	Staging $(basename "$tarball").."
    cp "$tarball" "$dest/wavelet.tar.gz"
    # UltraGrid AppImage - downloaded by download_offline_artifacts() above.
    local appimage="$HOME/.config/var/www/UltraGrid-continuous-x86_64.AppImage"
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

append_offline_partition(){
    # Append the offline tree as a SEPARATE PARTITION on the USB image,
    # with its own filesystem label "wavelet-offline".  This is where install_packages.sh will look on 1st boot.
    local in_iso="$1"
    local out_iso="$2"
    local part_img
    part_img="$(dirname "$out_iso")/wavelet-offline-part.img"
    # Remove if previously exists
    rm -f "$part_img"
    # Size: the offline tree + 10% margin, rounded up to whole MiB.
    local offline_bytes size_mib
    offline_bytes="$(du -sb "$ISO_ROOT/offline" | cut -f1)"
    size_mib=$(( (offline_bytes + offline_bytes / 10) / 1024 / 1024 + 1 ))
    echo "	Creating ${size_mib}MiB ext4 partition image for offline data.."
    if ! mkfs.ext4 -L wavelet-offline -F -d "$ISO_ROOT/offline" "$part_img" "${size_mib}M" 2>&1 | tail -n 3; then
        echo -e "${RED}	mkfs.ext4 failed for offline partition image. Aborting.${NC}"
        rm -f "$part_img"
        return 1
    fi
    echo "	Appending offline partition to ISO with xorriso (rewrites the image, may take a while).."
    rm -f "$out_iso"
    if ! xorriso \
        -indev "$in_iso" \
        -outdev "$out_iso" \
        -boot_image any keep \
        -append_partition 2 0x83 "$part_img" \
        2>&1 | tail -n 5; then
        echo -e "${RED}	xorriso failed to append offline partition. Aborting.${NC}"
        rm -f "$part_img"
        return 1
    fi
    rm -f "$part_img"
    [[ -f "$out_iso" ]]
}

#
## previously in coreos_installer.sh
#

coreos_installer(){
	# Generates the bootable ISO
	isoMode=""
	local search_dirs=()
	if [[ "$DEPLOYMENT_MODE" == "STANDALONE" ]]; then
		echo -e "	Running in network isolation mode, enabling kargs for faster provisioning..\n"
		isoMode="1"
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
    # Collect any existing live-iso files across all candidate locations
    EXISTING_FILES=()
    local d f
    for d in "${search_dirs[@]}"; do
    	[[ -d "$d" ]] || continue
    	while IFS= read -r f; do
    		EXISTING_FILES+=("$f")
    	done < <(ls "$d"/fedora-coreos-*-live-iso.x86_64.iso 2>/dev/null)
    done
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
   	fi
    # Find Image file and generate ignition files utilizing Butane
    # Look for ISO files across all candidate locations
    IMAGEFILE=""
    for d in "${search_dirs[@]}"; do
    	[[ -d "$d" ]] || continue
    	IMAGEFILE="$(ls "$d"/*.iso 2>/dev/null | head -n1)"
    	[[ -n "$IMAGEFILE" ]] && break
    done
    if [[ -z "$IMAGEFILE" ]]; then
    	IMAGEFILE="$(ls *.iso 2>/dev/null | head -n1)"
    fi
    if [[ -z "$IMAGEFILE" ]]; then
    	echo "	Error: No ISO files found in ${search_dirs[*]} or current directory."
    	exit 1
    fi
	echo "	Generating Ignition files with Butane"
	# Generate butane setting files-dir to current path
	# This is so that we can utilize the local files argument in server_custom.yml to inject the necessary files from /ignition subdir
	# NEW - using automated-installer.yml for everything here now.
	embedDir="./ignition_files/"
	ymlSource="./ignition_files/bootstrap_installer.yml"
	outputIgn="./ignition_files/installer.ign"
	butane --pretty --files-dir "$embedDir" "$ymlSource" --output "$outputIgn"
	echo "	Customizing ISO files with Ignition"
	# This will only want to be switched on if we are using an isolated system, it will significantly speed up boot time;
	if [[ "${isoMode}" = "1" ]]; then
		# ip<client-IP-number>:[<server-id>]:<gateway-IP-number>:<netmask>:<client-hostname>:<interface>:{dhcp|dhcp6|auto6|on|any|none|off}
		liveKarg="--live-karg-append ip=192.168.1.32::192.168.1.1:255.255.255.0:svr::none"
	fi
	echo -e "\n	ISO files output to ${HOME}/Downloads..\n"
	# Generate Server ISO
	echo "	Provision Server ISO"
	installer_preconf="$HOME/Downloads/wavelet_installer_preconf.iso"
	# Remove stale ISO file
	rm -rf "$installer_preconf"
	coreos-installer iso customize \
		--live-ignition "$outputIgn" --live-karg-append "${liveKarg}" \
		-o "$installer_preconf" "$IMAGEFILE"
	echo "	Generating conf partition on install media and copying in conf template file."
    # Generate a 2MB configuration partition, and copy server yaml template in.
	conf_img="/var/tmp/wavelet-conf-part.img"
	# ensure any stale attempts are removed prior to recreating the conf img file.
	rm -f "$conf_img"
    if ! mkfs.vfat -n conf -C "$conf_img" 2048 2>&1 | tail -n 3; then
        echo -e "${RED}	mkfs.vfat failed for conf partition. Aborting.${NC}"
        rm -f "$conf_img"
        return 1
    fi
    # Ensure the conf partition has ignition_server template, the conf.file and the LAN CA, if it exists.
	mcopy -i "$conf_img" -s "./ignition_files/ignition_server.yml" ::/
	mcopy -i "$conf_img" -s "./ignition_files/ignition_decoder.yml" ::/
	if [[ -f "$configFile" ]]; then
		mcopy -i "$conf_img" -s "$configFile" ::/
	else
		# We must generate a config file from our cmdline params in reverse
		echo "	This is actually quite a silly idea, please provide a .conf file."
	fi
	if [[ -f "$CAcert" ]]; then
		mcopy -i "$conf_img" -s "$CAcert" ::/
	fi
	# Create a temp copy for modification and generate
	out_iso="$HOME/Downloads/wavelet_server_installer.iso"
	rm -rf "$out_iso"
    if ! xorriso \
        -indev "$installer_preconf" \
        -outdev "$out_iso" \
        -boot_image any keep \
        -append_partition 3 0x0c "$conf_img" \
        2>&1 | tail -n 5; then
        echo -e "${RED}	xorriso failed to append offline partition. Aborting.${NC}"
        rm -f "$conf_img"
        return 1
    fi
	echo "	Please note that files on this partition may be edited in-place for subsequent new installations"
	echo "	$HOME/Downloads/wavelet_installer.iso is now available to be imaged onto USB install media!"
	rm -rf "$installer_preconf"
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
	parse_config_file "$configFile"
	requiredOptions=() # Options already set via config file
fi

DEPLOYMENT_MODE="$(echo "${DEPLOYMENT_MODE:-STANDALONE}" | tr '[:lower:]' '[:upper:]')"

# Test for required options from either the configFile or direct args.
if [[ ${#requiredOptions[@]} -gt 0 ]]; then
	for opt in "${requiredOptions[@]}"; do
		echo "Option: $opt is set!"
		if [[ -z "${!opt}" ]]; then
			echo -e "\n\n${RED} ERROR:	The install option '$opt' must be defined!
			\n	Aborting installation, as process will fail without these data.${NC}\n\n"
			exit 1
		fi
	done
fi

if [[ $domain == *".local" ]]; then
	echo -e "\n${RED}.local TLD domain is reserved for mDNS, please select another domain or subdomain, preferably one from your organization's domain"
	echo -e "${RED}Failure to do this may result in unpredictable behavior with local name resolution.${NC}"
	exit 1
fi

echo "	Dev mode is now enabled by default due to the need for running a customized UltraGrid AppImage.."
# Yes, this is supposed to be forced.
dev_flag="DEV";

if [[ -z "$configFile" ]]; then
	echo -e "${RED}A configuration file (--config=<file>) must be provided.${NC}"
	print_help
fi

# Check tooling before any work so we fail fast and clean
check_required_tools

if [[ "$DEPLOYMENT_MODE" == "FULL" ]] || [[ "$DEPLOYMENT_MODE" == "LAN" ]]; then
	get_publicinterface
	if [[ -z "$DEPLOYMENT_IP" ]]; then
		# We specified a registry, but not a deployment registry IP.  resolve it here
    	if [[ -n "${ip:-}" ]]; then
    		DEPLOYMENT_IP="$ip"
    	else
    		# for some reason get_publicInterface failed, fallback to hostname -I
    		DEPLOYMENT_IP="$(hostname -I | awk '{print $1}')"
    	fi
	fi
	validate_ip_port "$DEPLOYMENT_IP"
	# Always update to latest wavelet source from github or other official repo
	download_wavelet_git
	check_and_update_ultragrid_continuous
	if [[ "$DEPLOYMENT_MODE" == "LAN" ]]; then
		CAcert="$HOME/.config/var/ssl/certs/ca.crt"
       	if [[ -f "$CAcert" ]]; then
      		# Add the CA to ignition folder
       		cp -f "$CAcert" "ignition_files/ca.crt"
		fi
		coreos_installer
		mv "$HOME/Downloads/wavelet_server_installer.iso" "$HOME/Downloads/wavelet_installer_lan.iso"
	else
		coreos_installer
		build_full_iso_main
	fi
else
	echo "	Local registry option not defined, additional config not required.."
	coreos_installer
	mv "$HOME/Downloads/wavelet_server_installer.iso" "$HOME/Downloads/wavelet_installer_standalone.iso"
fi

echo "	${GREEN}Bootstrap installation complete, please ensure a valid .conf file exists on the USB install media /conf/ partition.${NC}"