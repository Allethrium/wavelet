#!/bin/bash
for i in "$@"
	do
		case $i in
			"mode=iso")
				echo -e "	Running in network isolation mode, enabling kargs for faster provisioning..\n"
				isoMode="1"
				;;
			deploy=*)
				DEPLOYMENT_SERVER="${i#*=}"
				;;
			*)
				echo -e "	Initial Setup mode running, configuring Server ISO File..\n"
				;;
		esac
done

if [[ ! -f "$HOME/Downloads" ]]; then
	mkdir -p "$HOME/Downloads"
fi

echo "	Removing old customized ISO files if they exist.."
	rm -rf "${HOME}"/Downloads/wavelet_server.iso
	rm -rf "${HOME}"/Downloads/wavelet_decoder.iso

echo -e "\n	**	Note: Put the drive controller for target devices in AHCI mode from BIOS setup!\n	**	RAID or other modes have been observed to interfere with the imaging process.\n"
# automated_installer process now autodetects the system's drive for installation - this arg is just here as a placeholder now.
DESTINATION_DEVICE="/dev/nvme0n1"
FILEPREFIX="fedora-coreos-"

REGISTRY_DIR=""
if [[ -n "$DEPLOYMENT_SERVER" ]]; then
	# A deployment server already has the ISO available, we use that
	REGISTRY_DIR="${HOME}/.config/var/www"
	echo "	Deployment mode active, checking for files in httpd resource directory: $REGISTRY_DIR"
else
	echo "	Deployment mode not active, checking for files in current dir.."
	REGISTRY_DIR="$(pwd)"
fi

# Check if valid CoreOS raw.xz files already exist in the registry directory
if ls "$REGISTRY_DIR"/fedora-coreos-*-live-iso.x86_64.iso > /dev/null 2>&1; then
	EXISTING_FILES=($(ls "$REGISTRY_DIR"/fedora-coreos-*-live-iso.x86_64.iso 2>/dev/null))
else
	EXISTING_FILES=()
fi

# Check for any other CoreOS files that might be older builds or different formats
OTHER_COREOS_FILES=()
if ls "$REGISTRY_DIR"/$FILEPREFIX* > /dev/null 2>&1; then
	# Get all fedora-coreos-* files
	for f in "$REGISTRY_DIR"/$FILEPREFIX*; do
		if [[ -f "$f" ]]; then
			basename_f=$(basename "$f")
			# Check if it's a metal.x86_64.raw.xz file
			if [[ "$basename_f" == *"live-iso.x86_64.iso"* ]]; then
				# It's a valid raw.xz file, already in EXISTING_RAW_XZ_FILES
				continue
			else
				# It's an older build or different format (e.g., .iso, .img, etc.)
				OTHER_COREOS_FILES+=("$f")
			fi
		fi
	done
fi

DOWNLOAD_NEEDED=0
if [[ ${#EXISTING_FILES[@]} -eq 0 ]]; then
	echo -e "\n	No valid CoreOS raw.xz files found in registry, downloading CoreOS metal raw image from internet, please be patient while this task executes..\n"
	DOWNLOAD_NEEDED=1
else
	echo "	Valid CoreOS images/components already exist in the registry."
fi

# Download if needed
if [[ $DOWNLOAD_NEEDED -eq 1 ]]; then
	# Using the podman container for consistency with build_registry.sh
	# Downloading raw.xz is typically better for automated disk imaging than ISO
	REGISTRY_REF="quay.io/coreos/coreos-installer:latest"
	podman run --security-opt label=disable \
		--pull=always \
		--rm \
		-v /tmp:/data -w /data \
		"$REGISTRY_REF" download -s stable -a x86_64 -p metal -f raw.xz

	# Move the downloaded ISO to the registry directory for future use
	DOWNLOADED_FILE=$(ls /tmp/fedora-coreos-*-live-iso.x86_64.iso 2>/dev/null | head -n1)
	if [[ -n "$DOWNLOADED_FILE" ]]; then
		mv "$DOWNLOADED_FILE" "$REGISTRY_DIR/" 2>/dev/null || true

		# Notify about older builds if they exist
		if [[ ${#OTHER_COREOS_FILES[@]} -gt 0 ]]; then
			echo -e "\n	**	Note: Older CoreOS build(s) or files exist in the registry:"
			for old_file in "${OTHER_COREOS_FILES[@]}"; do
				echo "	   - $(basename "$old_file")"
			done
			echo "	Consider cleaning up older builds if they are no longer needed."
		fi
	fi
fi

# Find Image file and generate ignition files utilizing Butane
# Look for ISO files in the registry directory or current directory
IMAGEFILE=""
if [[ -n "$REGISTRY_DIR" && -d "$REGISTRY_DIR" ]]; then
	IMAGEFILE="$(ls "$REGISTRY_DIR"/*.iso 2>/dev/null | head -n1)"
fi
if [[ -z "$IMAGEFILE" ]]; then
	IMAGEFILE="$(ls *.iso 2>/dev/null | head -n1)"
fi

if [[ -z "$IMAGEFILE" ]]; then
	echo "	Error: No ISO files found in registry directory ($REGISTRY_DIR) or current directory."
	exit 1
fi

echo "	Generating Ignition files with Butane"
# Generate butane setting files-dir to current path
# This is so that we can utilize the local files argument in server_custom.yml to inject the necessary files from /ignition subdir
echo "	Generating server.ign.."
embedDir="./ignition_files/"
ymlSource="./ignition_files/server_custom.yml"
outputIgn="./ignition_files/server.ign"
output="$(butane --pretty --files-dir "$embedDir" "$ymlSource" --output "$outputIgn")"
echo "	Customizing ISO files with Ignition"
# This will only want to be switched on if we are using an isolated system, it will significantly speed up boot time;
if [[ "${isoMode}" = "1" ]]; then
	# ip<client-IP-number>:[<server-id>]:<gateway-IP-number>:<netmask>:<client-hostname>:<interface>:{dhcp|dhcp6|auto6|on|any|none|off}
	liveKarg="--live-karg-append ip=192.168.1.32::192.168.1.1:255.255.255.0:svr::none"
fi
echo -e "\n	ISO files output to ${HOME}/Downloads..\n"
# Generate Server ISO
echo "	Provision Server ISO"
liveKarg="--live-karg-append ip=192.168.1.32::192.168.1.1:255.255.255.0:svr::none"
coreos-installer iso customize \
	--dest-device ${DESTINATION_DEVICE} \
	--dest-ignition ./ignition_files/server.ign ${liveKarg} \
	-o ${HOME}/Downloads/wavelet_server.iso ${IMAGEFILE}

echo "	Done, please note customized yml and transpiled files will remain in the /ignition_files/ folder for inspection and debugging purposes."
# removes generated user YAML blocks to keep everything clean
#rm -rf ./*.yml
echo -e "\n 	Image(s) generated,\n	If this is initial setup, please write wavelet_server.iso to a suitable boot media."
echo "	You may then proceed to launch installation by booting from it on your target machine."