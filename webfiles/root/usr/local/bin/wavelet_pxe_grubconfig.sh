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

	# Remove custom-initramfs if already exists
	rm -rf /home/wavelet/pxe/custom-initramfs.img
	# Pull coreOS PXE
	podman run --security-opt label=disable --pull=always --rm -v .:/data -w /data \
	quay.io/coreos/coreos-installer:release download -f pxe
	echo -e "\nCoreOS Image files downloaded, continuing..\n"
	# Set destination device and find downloaded initramfs file to customize
	DESTINATION_DEVICE="/dev/disk/by-id/coreos-boot-disk"
	IMAGEFILE=$(ls -t *.img | grep 'initramfs')
	echo "Generating client machine ISO files..\n"

	# Customize for PXE boot automation
	# Ref https://coreos.github.io/coreos-installer/customizing-install/
	# DustyMabe to the rescue! https://dustymabe.com/2020/04/04/automating-a-custom-install-of-fedora-coreos/
	# The long and short of it is I need to generate two ignitions, one to install everything and then THAT calls the decoder ignition.
	coreos-installer pxe customize \
			--dest-device ${DESTINATION_DEVICE} \
			--dest-ignition /home/wavelet/http/ignition/decoder.ign \
			-o /home/wavelet/pxe/custom-initramfs ${IMAGEFILE}
	FILES=$(find *img*)
	KERNEL=$(find *kernel*)
	# Copy boot images to both tftp and http server - NOTE /home/wavelet/pxe and /home/wavelet/http/pxe are NOT the same dirs!
	mkdir -p /var/lib/tftpboot/wavelet-coreos
	mkdir -p /home/wavelet/http/pxe
	cp ${FILES} /var/lib/tftpboot/wavelet-coreos && cp ${KERNEL} /var/lib/tftpboot/wavelet-coreos
	cp ${FILES} /home/wavelet/http/pxe && cp ${KERNEL} /home/wavelet/http/pxe

	# Generate filenames and Modify grub2.cfg menu option
	coreosVersion=$(find *fedora* | head -n 1)
	coreosVersion=$(echo ${coreosVersion##*coreos-})
	coreosVersion=$(echo ${coreosVersion%%-live*})
	initrd=$(find *initramfs.x86_64.img)
	rootfs=$(find *rootfs.x86_64.img)
	kernel=$(find *kernel-x86_64)
	installdev="/dev/nvme0n1"
	configURL="/home/wavelet/http/ignition/decoder.ign"
	# Note - it might seem like a lot of work to do it this way rather than simply generate and boot an ISO.
	# This is because grub2 needs certain information regarding the host machine which we can't easily generate.
	# It also needs data on the internal arrangement of the ISO rather just just being able to "boot" it
	# Since we already downloaded these components earlier in the process, we'll just keep doing it this way.
	coreOSentry=" \
	menuentry  'Decoder FCOS V.${coreosVersion} TFTP' --class fedora --class gnu-linux --class gnu --class os {
	echo 'Loading CoreOS kernel...'   
		linuxefi wavelet-coreos/${kernel} \
			ignition.firstboot \
			ignition.platform.id=metal \
			coreos.inst.install_dev=${installDev} \
			coreos.inst.ignition_url=${configURL}

	echo 'Loading Fedora CoreOS initial ramdisk...'
		initrdefi \
			wavelet-coreos/${initrd} \
    		wavelet-coreos/${rootfs}
		echo 'Booting Fedora CoreOS...'
	}"
	coreOShttpEntry=" \
	menuentry  'Decoder FCOS V.${coreosVersion} HTTP live boot' --class fedora --class gnu-linux --class gnu --class os {
	echo 'Loading CoreOS kernel...'   
		linuxefi (http,192.168.1.32:8080)/pxe/${kernel} \
			coreos.live.rootfs_url=http://192.168.1.32:8080/pxe/${rootfs} \
			ignition.firstboot \
			ignition.platform.id=metal \
			coreos.inst.install_dev=${installDev} \
			coreos.inst.ignition_url=${configURL}
			

	echo 'Loading Fedora CoreOS initial ramdisk...'
		initrdefi \
			(http,192.168.1.32:8080)/pxe/${initrd}
		echo 'Booting Fedora CoreOS...'
	}"
}

configure_tftpboot(){
	# Generate grub.cfg file in /var/lib/tftpboot root
	mkdir -p /var/lib/tftpboot/efi
	echo -e	"
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
	set default=3
	set timeout=10
	menuentry 'EFI Firmware System Setup'  'uefi-firmware' {
		fwsetup
	}
	menuentry 'Reboot' {
		reboot
	}
	${coreOSentry}
	${coreOShttpEntry}
	${coreOShttpISOEntry}
	${bootCentry}
	}" > /var/lib/tftpboot/grub.cfg
	cp /var/lib/tftpboot/efi/grub.cfg /home/wavelet/http/pxe
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
	bootCentry="menuentry  'Decoder BootC V.${coreosVersion} HTTP' --class fedora --class gnu-linux --class gnu --class os {
	echo 'Loading Fedora BootC Kernel...'   
		linuxefi (http,192.168.1.32:8080)/pxe/${kernel} \

	echo 'Loading Fedora BootC initial ramdisk...'
		initrdefi \
			(http,192.168.1.32:8080)/pxe/${initrd}
		echo 'Booting Fedora CoreOS...'
	}"
}

###
#
# Main
#
###

set -x
exec >/home/wavelet/pxe_grubconfig.log 2>&1

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
# Set Apache +x and read perms on http folder
chmod -R 0755 /home/wavelet/http
chown -R wavelet /home/wavelet/http
# Remove executable bit from all FILES in http (folders need +x for apache to traverse them)
find /home/wavelet/http -type f -print0 | xargs -0 chmod 644
echo -e "\nPXE bootable images completed and populated in http serverdir, client provisioning should now be available..\n"
# We do not install Fedora's TFTP server package, because DNSMASQ has one built-in.
touch /var/pxe.complete