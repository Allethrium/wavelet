#!/bin/bash

for i in "$@"
	do
		case $i in
			"D")		echo -e "\nProvisioning mode enabled, running from server and provisioning Decoder ISO only..\n"
			;;
			"mode=iso") echo -e "\nRunning in network isolation mode, enabling kargs for faster provisioning..\n"	;	isoMode="1"
			;;
			*)			echo -e "\nInitial Setup mode running, configuring Server + Decoder ISO Files..\n"			;	serverMode="1"
			;;
		esac
done

echo "Removing old customized ISO files if they exist.."
if [[ "${serverMode}" = "1" ]]; then
	rm -rf ${HOME}/Downloads/wavelet_server.iso
	rm -rf ${HOME}/Downloads/wavelet_decoder.iso
fi

echo -e "\n	**	Note: Put the drive controller for target devices in AHCI mode from BIOS setup!\n	**	RAID or other modes have been observed to interfere with the process.\n"
#read -p "Please input the FULL path of your destination device I.E /dev/nvme0n1.  Could also be /dev/vda if VM:" DESTINATION_DEVICE
DESTINATION_DEVICE="/dev/nvme0n1"
# Symlink as per: https://docs.fedoraproject.org/en-US/fedora-coreos/storage/
# Doesn't work.
# DESTINATION_DEVICE="/dev/disk/by-id/coreos-boot-disk"
#echo -e "Destination device is set to ${DESTINATION_DEVICE}, please verify!"
#read -p "Continue? (Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit

FILEPREFIX="fedora-coreos-"
if ls ./$FILEPREFIX* > /dev/null 2>&1; then
	echo -e "\nCoreOS image already exists.\n"
	:
	else
	echo -e "\nNo ISO found, downloading CoreOS ISO from internet, please be patient while this task executes..\n"
	coreos-installer download -s stable -a x86_64 -p metal -f iso
fi

# Find Image file and generate ignition files utilizing Butane
IMAGEFILE=$(ls -t *.iso | head -n1)
	echo -e "Generating Ignition files with Butane..\n"
	# Generate decoder.ign regardless of server provisioning argument
	echo -e "Generating decoder.ign..\n"
	butane --pretty --strict --files-dir ./ ./decoder_custom.yml --output ./ignition_files/decoder.ign
	if [[ "${serverMode}" = "1" ]]; then
		# Generate butane setting files-dir to current path
		# This is so that we can utilize the local files argument in server_custom.yml to inject the necessary files from /ignition subdir
		echo -e "Generating server.ign..\n"
		butane --pretty --strict --files-dir ./ignition_files ./server_custom.yml --output ./ignition_files/server.ign
	fi

echo "Customizing ISO files with Ignition\n"
	# This will only want to be switched on if we are using an isolated system, it will significantly speed up boot time;
	if [[ "${isoMode}" = "1" ]]; then 
		liveKarg="--live-karg-append ip=192.168.1.32::192.168.1.1:255.255.255.0:svr.ignition.local::on"
	fi
	if [[ "${serverMode}" = "1" ]]; then
		echo -e "\nISO files output to ${HOME}/Downloads..\n"
		# Generate Server ISO
		echo -e "Provision Server ISO..\n"
		coreos-installer iso customize \
		--dest-device ${DESTINATION_DEVICE} \
		--dest-ignition ./ignition_files/server.ign ${liveKarg} \
		-o $HOME/Downloads/wavelet_server.iso ${IMAGEFILE}
		# Generate Decoder ISO
		echo -e "Provision Decoder ISO..\n"
		coreos-installer iso customize \
		--dest-device ${DESTINATION_DEVICE} \
		--dest-ignition ./ignition_files/decoder.ign \
		-o $HOME/Downloads/wavelet_decoder.iso ${IMAGEFILE}
	else
		echo -e "\nProvisioning Decoder, .ISO files output to /var/wavelet/http/ignition/..\n"
		# Generate only Decoder ISO
		coreos-installer iso customize \
		--dest-device ${DESTINATION_DEVICE} \
		--dest-ignition /var/home/wavelet/http/ignition/decoder.ign \
		-o /var/home/wavelet/http/ignition/wavelet_decoder.iso ${IMAGEFILE}
	fi

echo -e "Image(s) generated,\n If this is initial setup please burn wavelet_server.iso to a USB stick and boot to continue setup..\n"