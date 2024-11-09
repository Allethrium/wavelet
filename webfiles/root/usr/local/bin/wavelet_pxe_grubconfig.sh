#!/bin/bash

# This module sets up a fully functional TFTP server + HTTP transport and populated Fedora CoreOS images,
# and hopefully soon Fedora bootC images.
# It is called from a systemd unit generated by wavelet_installer_xf.sh as part of server spinup.

# Workdir is /home/wavelet/pxe

# Refs:
#	https://github.com/robbycuenot/uefi-pxe-agents
#	https://docs.oracle.com/en/operating-systems/oracle-linux/9/install/install-ConfiguringPXEBootLoading.html
#	https://docs.fedoraproject.org/en-US/fedora-coreos/bare-metal/
# 

generate_tftpboot() {
	# The Containerfile will generate an output direct to /var/lib/tftpboot with a populated set of UEFI secure boot files.
	sudo podman build --tag shim -f /home/wavelet/containerfiles/Containerfile.tftpboot
	podman run --privileged --security-opt label=disable -v /var/lib:/tmp/ shim
}

generate_coreos_image() {
	###
	#
	# OLD METHOD - CoreOS Spinup w/ Ignition resulting in multiple redundant downloads from RPM sources etc.
	#	Advantages		-	Works reliably
	#	Disadvantages	-	requires multiple installation steps
	#
	###

	mkdir -p /home/wavelet/pxe && cd /home/wavelet/pxe
	mkdir -p /var/lib/tftpboot/wavelet-coreos
	mkdir -p /home/wavelet/http/pxe
	chmod +x {/home/wavelet/pxe,/home/wavelet/http,/home/wavelet/http/pxe}

	# Remove custom-initramfs if already exists
	rm -rf /home/wavelet/pxe/custom-initramfs.img
	# Pull coreOS PXE
	podman run --security-opt label=disable --pull=always --rm -v .:/data -w /data \
	quay.io/coreos/coreos-installer:release download -f pxe
	echo -e "\nCoreOS Image files downloaded, continuing..\n"
	# Set destination device and find downloaded initramfs file to customize
	#DESTINATION_DEVICE="/dev/disk/by-id/coreos-boot-disk"
	IMAGEFILE=$(ls -t *.img | grep 'initramfs')
	echo "Generating client machine ISO files..\n"

	# Move yml for automated installer and generate ignition file for initial client boot, then COPY it back as a compiled ignition file
	if [[ -f automated_installer.yml ]]; then
		echo -e "automated installer YAML already exists!\n"
	fi
	mv /home/wavelet/http/ignition/automated_installer.yml ./
	butane --pretty --strict --files-dir ./ automated_installer.yml --output automated_installer.ign
	cp ./automated_installer.ign /home/wavelet/http/ignition/automated_installer.ign
	cp /usr/local/bin/wavelet_install_client.sh /home/wavelet/http/ignition

	# Customize for PXE boot automation
	# Ref https://coreos.github.io/coreos-installer/customizing-install/
	# DustyMabe to the rescue! https://dustymabe.com/2020/04/04/automating-a-custom-install-of-fedora-coreos/
	# automated_installer.ign is preconfigured by the wavelet_installer during initial setup process
	FILES=$(find *img*)
	KERNEL=$(find *kernel*)
	# Copy boot images to both tftp and http server - NOTE /home/wavelet/pxe and /home/wavelet/http/pxe are NOT the same dirs!
	cp ${FILES} /var/lib/tftpboot/wavelet-coreos && cp ${KERNEL} /var/lib/tftpboot/wavelet-coreos
	cp ${FILES} /home/wavelet/http/pxe && cp ${KERNEL} /home/wavelet/http/pxe

	# Generate filenames and Modify grub2.cfg menu option
	coreosVersion=$(find *fedora* | head -n 1)
	coreosVersion=$(echo ${coreosVersion##*coreos-})
	coreosVersion=$(echo ${coreosVersion%%-live*})
	initrd=$(find *initramfs.x86_64.img)
	rootfs=$(find *rootfs.x86_64.img)
	kernel=$(find *kernel-x86_64)

	# Generate the ignition file for the automated Live Installer, then generate the initial ignition file
	# Files required; 
	#		automated_installer.yml (FCCT/Butane YML config for initial boot)
	#		automated_coreos_deployment.sh (HDD Detection script)
	#		decoder.ign (should be pre-provisioned from initial setup script prior to installing the server)
	configURL="http://192.168.1.32:8080/ignition/automated_installer.ign"
	# The boot process now calls an initial coreOS Live image, which has an automation process burned in with a custom ignition file.
	# It THEN installs the host OS after detecting available hard drives, configured with decoder.ign.  So this is a two-step bootstreap process.
	coreOShttpEntry="menuentry  'Decoder FCOS V.${coreosVersion} HTTP live boot' --class fedora --class gnu-linux --class gnu --class os {
echo -e '\nLoading CoreOS kernel...'   
linuxefi (http,192.168.1.32:8080)/pxe/${kernel} coreos.live.rootfs_url=http://192.168.1.32:8080/pxe/${rootfs} ignition.firstboot ignition.platform.id=metal ignition.config.url=${configURL}		
echo 'Loading Fedora CoreOS initial ramdisk...'
initrdefi (http,192.168.1.32:8080)/pxe/${initrd}
echo 'Booting Fedora CoreOS...'
}"
}

configure_tftpboot(){
	# Generate grub.cfg file in /var/lib/tftpboot root and copy to pxe folder
	mkdir -p /var/lib/tftpboot/efi
	echo -e	"\n
function load_video {
	insmod all_video
}
load_video
set gfxpayload=keep
insmod gzio
insmod part_gpt
insmod ext2
insmod chain
insmod regexp
set default=2
set timeout=3
menuentry 'EFI Firmware System Setup'  'uefi-firmware' {
	fwsetup
}
menuentry 'Reboot' {
	reboot
}
${coreOShttpEntry}
${coreOStftpEntry}
${coreOSbootCEntry}
}" > /var/lib/tftpboot/grub.cfg
	cp /var/lib/tftpboot/grub.cfg /var/home/wavelet/http/pxe && chown wavelet:wavelet /var/home/wavelet/http/pxe/grub.cfg
}

generate_bootc_image() {
	## ********* Extremely early WIP ********* 
	###
	#
	# NEW METHOD - Generate a pre-provisioned ISO utilizing a bootc image (WIP)
	#	Advantages		-	One pre-generated composeFS ISO file.
	#	Disadvantages	-	have to dump ignition and find another way to config the client machine
	#
	###
	# Call bootc container build process and let it run
	# configure and verify config.toml
	# configure and verify kickstart.ks
	# Build container, generate images
	sudo podman build --tag bootc-decoder -f /home/wavelet/containerfiles/Containerfile.bootc-decoder
	# Convert container to ISO
	sudo podman run \
    --rm \
    -it \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v $(pwd):/output \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    registry.redhat.io/rhel9/bootc-image-builder:latest \
    --type iso \
    bootc-decoder
    # Copy images to tftp and http
    mkdir -p /home/wavelet/http/pxe/fcos-bootc/
    mkdir -p /var/lib/tftpboot/fcos-bootc/
	# Add grub2 menu option for bootc ISO
	coreOSbootCEntry="menuentry  'Decoder BootC V.${coreosVersion} HTTP' --class fedora --class gnu-linux --class gnu --class os {
echo 'Loading Fedora BootC Kernel...'   
linuxefi (http,192.168.1.32:8080)/pxe/${kernel} \
echo 'Loading Fedora BootC initial ramdisk...'
initrdefi (http,192.168.1.32:8080)/pxe/${initrd}
echo 'Booting Fedora CoreOS...'
}"
}

###
#
# Main
#
###

set -x
exec >/home/wavelet/grubconfig.log 2>&1

if [[ -f /var/pxe.complete ]]; then
	echo -e "\nInstaller has already run, ending task!"
	exit 0
fi

# Generate TFTPBOOT folder along with appropriate entries for our populated boot options
generate_tftpboot
generate_coreos_image
configure_tftpboot
# generate_bootc_image

# Mess around with permissions
# dnsmasq is the tftpserver, therefore dnsmasq user requires rights to /var/lib/tftpboot for secure operation
chown -R dnsmasq:root /var/lib/tftpboot
# We don't need tftp files to be executable, *maybe not even writable..
find /var/lib/tftpboot -type f -print0 | xargs -0 chmod 644
# Restore SElinux contexts or we will get an AVC denial when Dnsmasq attempts to serve tftp requests
restorecon -Rv /var/lib/tftpboot
# Copy EFI files to http pxe
cp -R /var/lib/tftpboot/*.efi /home/wavelet/http/pxe
cp -R /var/lib/tftpboot/boot /home/wavelet/http/pxe
cp -R /var/lib/tftpboot/efi /home/wavelet/http/pxe
# Ensure the wavelet user owns the http folder, and set +x and read perms on http folder and subfolders
chmod -R 0755 /home/wavelet/http
chown -R wavelet /home/wavelet/
# Remove executable bit from all FILES in http (folders need +x for apache to traverse them) - apparently this breaks PXE though?
find /var/home/wavelet/http/ -type f -print0 | xargs -0 chmod 644
find /var/home/wavelet/http-php/ -type f -print0 | xargs -0 chmod 644
echo -e "\nPXE bootable images completed and populated in http serverdir, client provisioning should now be available..\n"
touch /var/pxe.complete
# we disable the service so it won't attempt to start on next boot
systemctl disable wavelet_install_pxe.service 
systemctl reboot