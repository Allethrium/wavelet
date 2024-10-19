#!/bin/bash

# This module sets up a fully functional TFTP server + HTTP transport and populated Fedora CoreOS images,
# and hopefully soon Fedora bootC images.
# It is called from wavelet_installer_xf.sh as part of server spinup.

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

	# Generate grub.cfg file
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
	${bootCentry}
	}" > /var/lib/tftpboot/efi/grub.cfg
	cp /var/lib/tftpboot/efi/grub.cfg /home/wavelet/http/pxe
	chmod -R 0755 /home/wavelet/http
	chown -R wavelet:wavelet /home/wavelet/http
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
	# Pull coreOS ISO
	#podman run --security-opt label=disable --pull=always --rm -v .:/data -w /data \
	#    quay.io/coreos/coreos-installer:release download -s stable -p metal -f iso
	#mount -vvv /home/wavelet/pxe/wavelet-coreos-decoder.iso /var/mnt

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

	# Customize iso for PXE boot
	# Ref https://coreos.github.io/coreos-installer/customizing-install/
	# We seem to have an issue where the installer will fail fue to updating kernel arguments, but we have already customized them in the liveCD?
	# I appear to have misunderstood something about the pxe baremetal installation instructions here..
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
	cp ${FILES} /home/wavelet/http/pxe && cp ${KERNEL} /home/wavelet/http/pxe && chown -R wavelet:wavelet /home/wavelet/http

	# Generate filenames and Modify grub2.cfg menu option
	coreosVersion=$(find *fedora* | head -n 1)
	coreosVersion=$(echo ${coreosVersion##*coreos-})
	coreosVersion=$(echo ${coreosVersion%%-live*})
	initrd=$(find *initramfs.x86_64.img)
	rootfs=$(find *rootfs.x86_64.img)
	kernel=$(find *kernel-x86_64)
	installdev="/dev/nvme0n1"
	configURL="http://192.168.1.32:8080/ignition/decoder.ign"
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
	menuentry  'Decoder FCOS V.${coreosVersion} HTTP' --class fedora --class gnu-linux --class gnu --class os {
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

#coreos.inst.install_dev=/dev/sda 


generate_bootc_image() {
	## WIP
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

# ref https://docs.fedoraproject.org/en-US/fedora/f36/install-guide/advanced/Kickstart_Installations/
#	menuentry 'Install Fedora 36 Server'  --class fedora --class gnu-linux --class gnu --class os {
#	kernel f41/vmlinuz
#	append initrd=f41/initrd.img 
#	inst.repo=https://download.fedoraproject.org/pub/fedora/linux/releases/41/Server/x86_64/os/ ip=dhcp 
#	ks=https://git.fedorahosted.org/cgit/spin-kickstarts.git/plain/fedora-install-server.ks?h=f21
#	}

}


mess() {
# Download Coreos files
# Do we need to do this or can we just generate the iso from the ignition file using coreos-installer?
mkdir -p /var/lib/tftpboot/coreos

#podman run --privileged --security-opt label=disable --pull=always \
--rm -v /var/lib/tftpboot/coreos/:/data \
-w /data quay.io/coreos/coreos-installer:release download -f pxe

# Get version 
coreosVersion=$(ls /var/lib/tftpboot/coreos/*.img | head -n 2)
coreosVersion=$(echo ${coreosVersion##*coreos-})
coreosVersion=$(echo ${coreosVersion%%-live*})

# populate vars
rootfs=$(ls /var/lib/tftpboot/coreos/*.img | grep rootfs)
initramfs=$(ls /var/lib/tftpboot/coreos/*.img | grep initramfs)
kernel=$(ls /var/lib/tftpboot/coreos/*-x86-64 | grep kernel)
kernel=$(echo ${kernel##*coreos/})

#linux fedora-x86_64/vmlinuz inst.repo=http://dl.fedoraproject.org/pub/fedora/linux/releases/40/Everything/x86_64/os inst.stage2=http://dl.fedoraproject.org/pub/fedora/linux/releases/40/Everything/x86_64/os ip=dhcp initrd fedora-x86_64/initrd.img
}


###
#
# Main
#
###

exec >/home/wavelet/pxe_grubconfig.log 2>&1

generate_coreos_image
#generate_bootc_image
# Generate TFTPBOOT folder along with appropriate entries for our populated boot options
generate_tftpboot
# Set Apache +x and read perms on http folder
chmod -R 0755 /home/wavelet/http
echo -e "PXE bootable images completed and populated in http serverdir, client provisioning should now be available..\n"
echo -e "Rebooting system to continue to userland setup..\n"