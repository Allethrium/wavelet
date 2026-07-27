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

if [[ -n "$DEPLOYMENT_SERVER" ]]; then
	# A deployment server already has the ISO available, we use that
	REGISTRY_DIR="${HOME}/.config/var/www"
else
	REGISTRY_DIR="$(pwd)"
	# Check if CoreOS files already exist in the registry directory
	if ls "$REGISTRY_DIR"/$FILEPREFIX* > /dev/null 2>&1; then
		echo "	CoreOS images/components already exist in the registry."
	else
		echo -e "\n	No CoreOS files found in registry, downloading CoreOS metal raw image from internet, please be patient while this task executes..\n"
		# Using the podman container for consistency with build_registry.sh
		# Downloading raw.xz is typically better for automated disk imaging than ISO
		REGISTRY_REF="quay.io/coreos/coreos-installer:latest"
		podman run --security-opt label=disable \
			--pull=always \
			--rm \
			-v /tmp:/data -w /data \
			"$REGISTRY_REF" download -s stable -a x86_64 -p metal -f raw.xz
		# Move the downloaded raw.xz to the registry directory for future use
		mv /tmp/fedora-coreos-*.raw.xz "$REGISTRY_DIR/" 2>/dev/null || true
	fi
fi

# Find Image file and generate ignition files utilizing Butane
IMAGEFILE="$(ls *.iso | head -n1)"
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
echo -e "\n 	Image(s) generated,\n	If this is initial setup,  please write wavelet_server.iso to a suitable boot media."
echo "	You may then proceed to launch installation by booting from it on your target machine."