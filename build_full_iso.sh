#!/bin/bash
# build_full_iso.sh
#
# Generates a "full" wavelet_server ISO (~8GB) which embeds EVERYTHING required to provision a wavelet server with
# no internet access and no deployment host:
#
#   /offline/images/*.oci.tar   - podman save OCI archives of all container images
#                                 (base images + coreos_overlay_server/client)
#   /offline/wavelet.tar.gz     - the wavelet git tarball (copied by the
#                                 wavelet_load_offline.service first-boot unit)
#   /offline/UltraGrid.AppImage - the UltraGrid AppImage (same)
#   /offline/rpms/*.rpm         - FFmpeg RPMs
#	/offline/iso/*.iso			- CoreOS ISO files
#
# Prerequisites (run first, on a Linux workbench):
#   1. ./build_registry.sh  <path> [registry-IP]     - populates local podman image store and downloads coreos images.
#   2. ./install_wavelet_server.sh -c=wavelet.conf    - generates the thin wavelet_server.iso
#
# Usage:
#   ./build_full_iso.sh <path-to-wavelet-git> [output-iso]
#
# This install process does not support windows because WSL2 does not provide "full" podman;
# it only provides a podman wrapper for windows containers.

RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"

ISO_ROOT="$(mktemp -d /tmp/wavelet_full_iso.XXXXXX)"

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

# Check tooling before any work so we fail fast and clean
check_required_tools

generate_full_ignition(){
    # Produces ignition_files/server_full.yml + server_full.ign.
	local waveletdir="$1"
	cp "$waveletdir/ignition_files/server_custom.yml" "$waveletdir/ignition_files/server_full.yml"
	# Remove the two 3-line "path:/mode:/contents: source: https..." entries
	sed -i '/# Wavelet master zipfile/,/source: https:\/\/[^ ]*\.tar\.gz/d' \
		"$waveletdir/ignition_files/server_full.yml"
	sed -i '/# UltraGrid executable/,/source: https:\/\/[^ ]*\.AppImage/d' \
		"$waveletdir/ignition_files/server_full.yml"
	# Ensure FULL_ISO_MODE=1 is in the wavelet.conf that ignition writes.
    local conf_src="$waveletdir/ignition_files/wavelet.conf"
    local conf_tmp
    conf_tmp="$(mktemp "$waveletdir/ignition_files/wavelet.conf.XXXXXX")"
    if [[ -f "$conf_src" ]]; then
        if grep -q '^FULL_ISO_MODE=' "$conf_src"; then
            sed 's/^FULL_ISO_MODE=.*/FULL_ISO_MODE=1/' "$conf_src" > "$conf_tmp"
        else
            cp "$conf_src" "$conf_tmp"
            echo "FULL_ISO_MODE=1" >> "$conf_tmp"
        fi
		# Bootc-era FCOS is the only target for the full ISO.
        if grep -q '^USE_BOOTC=' "$conf_tmp"; then
            sed -i 's/^USE_BOOTC=.*/USE_BOOTC=1/' "$conf_tmp"
        else
            echo "USE_BOOTC=1" >> "$conf_tmp"
        fi
        # Replace the file in place (the YAML references it by name)
        mv "$conf_tmp" "$conf_src"
    else
        echo -e "${RED}	ERROR: wavelet.conf not found at $conf_src - cannot set FULL_ISO_MODE${NC}"
        return 1
    fi
	# Transpile (same --files-dir mechanism)
	butane --pretty --files-dir "$waveletdir/ignition_files/" \
        "$waveletdir/ignition_files/server_full.yml" \
        --output "$waveletdir/ignition_files/server_full.ign"
}

save_iso_images(){
	# Saves the coreos installer images to the installer drive
	mkdir -p "$ISO_ROOT/offline/iso"
	curl -fsSL https://fedoraproject.org/fedora.gpg | gpg --import
	 for file in ~/.config/var/www/fedora-coreos-*; do
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
    # Size: the offline tree + 10% margin, rounded up to whole MiB.
    local offline_bytes size_mib
    offline_bytes="$(du -sb "$ISO_ROOT/offline" | cut -f1)"
    size_mib=$(( (offline_bytes + offline_bytes / 10) / 1024 / 1024 + 1 ))
    echo "	Creating ${size_mib}MiB ext4 partition image for offline data.."
    rm -f "$part_img"
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


####
#
# Main
#
####


waveletdir="$(pwd)"
if [[ "$1" == */ ]]; then
    waveletdir="${1%/*}"
elif [[ -n "$1" ]]; then
    waveletdir="$1"
fi

SRC_ISO="${SRC_ISO:-$HOME/Downloads/wavelet_server.iso}"
OUT_ISO="${2:-$HOME/Downloads/wavelet_server_full.iso}"

if [[ ! -f "$SRC_ISO" ]]; then
    echo -e "${RED}	Source ISO not found: $SRC_ISO${NC}"
    echo "	Generate it first with: ./install_wavelet_server.sh -c=<wavelet.conf>"
    exit 1
fi

# Generate the full-mode ignition
STOCK_ISO="$(ls "$HOME/.config/var/www"/fedora-coreos-*-live-iso.x86_64.iso 2>/dev/null | sort -V | tail -n1)"
if [[ -z "$STOCK_ISO" ]]; then
    STOCK_ISO="$(ls "$HOME/Downloads"/fedora-coreos-*-live-iso.x86_64.iso 2>/dev/null | sort -V | tail -n1)"
fi
if [[ -z "$STOCK_ISO" ]]; then
    echo -e "${RED}	Stock CoreOS live ISO not found (fedora-coreos-*-live-iso.x86_64.iso).${NC}"
    echo "	It is normally downloaded to ~/.config/var/www by build_registry.sh / coreos_installer.sh."
    exit 1
fi

USE_BOOTC="${USE_BOOTC:-}"
if [[ -z "$USE_BOOTC" ]]; then
    fcos_version="$(basename "$STOCK_ISO" | sed -n 's/^fedora-coreos-\([0-9]*\)\..*/\1/p')"
    if (( fcos_version >= 45 )); then
        USE_BOOTC=1
    else
        USE_BOOTC=0
    fi
fi
echo "	Detected FCOS $(basename "$STOCK_ISO" | grep -oP 'fedora-coreos-\K[0-9.]+') - USE_BOOTC=$USE_BOOTC (overlay suffix: $([[ "$USE_BOOTC" == 1 ]] && echo _bootc || echo none))"

if ! ls "$HOME/.config/var/www"/*.tar.gz >/dev/null 2>&1 || \
   ! ls "$HOME/.config/var/www"/UltraGrid-*.AppImage >/dev/null 2>&1; then
    echo -e "${RED}	Wavelet tarball or UltraGrid AppImage missing from ~/.config/var/www.${NC}"
    exit 1
fi

echo "	Generating full-mode ignition (offline loader wired in, small initramfs).."
generate_full_ignition "$waveletdir" || {
    echo -e "${RED}	Butane failed to transpile server_full.yml. Aborting.${NC}"
    exit 1
}

echo "	Customizing stock CoreOS ISO with full-mode ignition.."
rm -f "$HOME/Downloads/wavelet_server_full_tmp.iso" "$OUT_ISO"
# Same live karg coreos_installer.sh applies (static IP for the live env)
liveKarg="--live-karg-append ip=192.168.1.32::192.168.1.1:255.255.255.0:svr::none"
DEST_DEVICE="${DEST_DEVICE:-/dev/nvme0n1}"

BOOTNEXT_HOOK="$(mktemp /tmp/wavelet_bootnext.XXXXXX.sh)"
cat > "$BOOTNEXT_HOOK" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "	Setting EFI BootNext to the installed disk.."
if ! command -v efibootmgr >/dev/null 2>&1; then
    echo "	efibootmgr not available (BIOS install?) - skipping."
    exit 0
fi
esp_uuid="$(blkid -s PARTUUID -o value /dev/disk/by-partlabel/EFI-SYSTEM 2>/dev/null || true)"
if [[ -z "$esp_uuid" ]]; then
    echo "	WARNING: could not resolve installed ESP PARTUUID; BootNext not set."
    exit 0
fi
next_entry="$(efibootmgr -v 2>/dev/null | sed -n "s/^Boot\([0-9A-Fa-f]\{4\}\).*${esp_uuid}.*/\1/p" | head -n1)"
if [[ -z "$next_entry" ]]; then
    echo "	WARNING: no efibootmgr entry references ESP PARTUUID $esp_uuid."
    exit 0
fi
if efibootmgr --bootnext "$next_entry" >/dev/null 2>&1; then
    echo "	EFI BootNext set to Boot$next_entry (installed disk)."
else
    echo "	WARNING: failed to set EFI BootNext (firmware may boot the USB again)."
fi
exit 0
EOF
coreos-installer iso customize \
    --dest-device "$DEST_DEVICE" \
    --dest-ignition "$waveletdir/ignition_files/server_full.ign" \
    --post-install "$BOOTNEXT_HOOK" \
    ${liveKarg} \
    -o "$HOME/Downloads/wavelet_server_full_tmp.iso" "$STOCK_ISO" || {
    rm -f "$BOOTNEXT_HOOK"
    echo -e "${RED}	coreos-installer failed. Aborting.${NC}"
    exit 1
}
rm -f "$BOOTNEXT_HOOK"
SRC_ISO="$HOME/Downloads/wavelet_server_full_tmp.iso"

echo -e "\n **	Building FULL wavelet server ISO (no internet required at install site) **\n"
echo "	Source ISO: $SRC_ISO"
echo "	Output ISO: $OUT_ISO"

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
    echo "	  OUT_ISO=/path/on/bigger/disk/wavelet_server_full.iso $0"
    rm -f "$HOME/Downloads/wavelet_server_full_tmp.iso"
    exit 1
fi

append_offline_partition "$SRC_ISO" "$OUT_ISO" || {
    echo -e "${RED}	xorriso failed to build output ISO. Aborting.${NC}"
    exit 1
}
rm -f "$HOME/Downloads/wavelet_server_full_tmp.iso"

size_gib=$(( $(stat -c%s "$OUT_ISO") / 1024 / 1024 / 1024 ))
echo -e "\n${GREEN}	Full ISO generated: $OUT_ISO (${size_gib}GiB)${NC}"
echo -e "\n	Deployment instructions:"
echo "	  1. Flash $OUT_ISO to USB"
echo "	  2. Boot the target machine from the USB and LEAVE THE USB PLUGGED IN."
echo "	  3. First boot installs to disk fully offline (all images are embedded)."
echo "	  4. When prompted on the console, confirm the machine is on its own isolated network."
echo "	  5. After provisioning completes, the USB may be removed."
