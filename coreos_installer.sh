#!/bin/bash
for i in "$@"
	do
		case $i in
			"mode=iso") echo -e "\n	Running in network isolation mode, enabling kargs for faster provisioning..\n"	;	isoMode="1"
			;;
			*)			echo -e "\n	Initial Setup mode running, configuring Server ISO File..\n"			;	serverMode="1"
			;;
		esac
done

if [[ ! -f "$HOME/Downloads" ]]; then
	mkdir -p "$HOME/Downloads"
fi

echo "	Removing old customized ISO files if they exist.."
	rm -rf "${HOME}"/Downloads/wavelet_server.iso
	rm -rf "${HOME}"/Downloads/wavelet_decoder.iso

echo -e "\n		**	Note: Put the drive controller for target devices in AHCI mode from BIOS setup!\n		**	RAID or other modes have been observed to interfere with the process.\n"
# automated_installer process now autodetects the system's drive for installation - this arg is just here as a placeholder now.
DESTINATION_DEVICE="/dev/nvme0n1"
FILEPREFIX="fedora-coreos-"
if ls ./$FILEPREFIX* > /dev/null 2>&1; then
	echo -e "\n	CoreOS image already exists.\n"
	:
	else
	echo -e "\n	No ISO found, downloading CoreOS ISO from internet, please be patient while this task executes..\n"
	coreos-installer download -s stable -a x86_64 -p metal -f iso
fi

# Find Image file and generate ignition files utilizing Butane
IMAGEFILE="$(ls *.iso | head -n1)"
	echo -e "	Generating Ignition files with Butane..\n"
	# Generate butane setting files-dir to current path
	# This is so that we can utilize the local files argument in server_custom.yml to inject the necessary files from /ignition subdir
	echo -e "	Generating server.ign..\n"
	embedDir="./ignition_files/"
	ymlSource="./ignition_files/server_custom.yml"
	outputIgn="./ignition_files/server.ign"
	butane --pretty --strict --files-dir "$embedDir" "$ymlSource" --output "$outputIgn"

echo "	Customizing ISO files with Ignition\n"
	# This will only want to be switched on if we are using an isolated system, it will significantly speed up boot time;
	if [[ "${isoMode}" = "1" ]]; then 
		# ip<client-IP-number>:[<server-id>]:<gateway-IP-number>:<netmask>:<client-hostname>:<interface>:{dhcp|dhcp6|auto6|on|any|none|off}
		liveKarg="--live-karg-append ip=192.168.1.32::192.168.1.1:255.255.255.0:svr::none"
	fi
	echo -e "\n	ISO files output to ${HOME}/Downloads..\n"
	# Generate Server ISO
	echo -e "	Provision Server ISO..\n"
	liveKarg="--live-karg-append ip=192.168.1.32::192.168.1.1:255.255.255.0:svr::none"
	coreos-installer iso customize \
	--dest-device ${DESTINATION_DEVICE} \
	--dest-ignition ./ignition_files/server.ign ${liveKarg} \
	-o ${HOME}/Downloads/wavelet_server.iso ${IMAGEFILE}

echo "	Done, please note customized yml and transpiled files will remain in the /ignition_files/ folder for inspection and debugging purposes."
# removes generated user YAML blocks to keep everything clean
#rm -rf ./*.yml
echo -e " 	Image(s) generated,\n	If this is initial setup please burn wavelet_server.iso to a USB stick and boot to continue setup..\n"