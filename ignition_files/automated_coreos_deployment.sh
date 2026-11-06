#!/usr/bin/bash

# This script is a modification of that provided on:
# https://dustymabe.com/2020/04/04/automating-a-custom-install-of-fedora-coreos/
# It attempts to detect common block devices and configure the initial automation live installer for that device.

# 11/2026 Update - we now handle the ignition customization pass here

main() {
    # We tell the SECOND boot after installation is completed to utilize the client device ignition file.
    ignition_file="/home/decoder.ign"
    # We do NOT need an image file, because we already booted CoreOS from PXE.
    # Image url should be wherever our FCOS image is stored
    # In Wavelet's case, the image is downloaded by wavelet_pxe_grubconfig.sh during server spinup
    # Note you'll want to use https and also copy the image .sig
    # to the appropriate place. Otherwise you'll need to `--insecure`
    # image_url='http://192.168.1.32:8080/pxe/fedora-coreos-31.20200310.3.0-metal.x86_64.raw.xz'
    # Some custom arguments for firstboot
    # firstboot_args='console=tty0'

    # Dynamically detect which device to install to.
    # This represents something an admin may want to do to share the
    # same installer automation across various hardware.
    nvme=$(lsblk -o name -lpn | grep "/dev/nvme" | head -n 1)
    sata=$(lsblk -o name -lpn | grep "/dev/sd" | head -n 1)
    mmcblk=$(lsblk -o name -lpn | grep "/dev/mmcblk" | head -n 1)
    if [[ -b "$nvme" ]]; then
            install_device="$nvme"
            echo -e "NVME Device discovered!"
        elif [[ -b "$sata" ]]; then
            install_device="$sata"
            echo -e "SATA Device discovered!"
        elif [[ -b "$mmcblk" ]]; then
            install_device="$mmcblk"
            echo -e "EMMC Flash device discovered!"
        else
            return 1
    fi
    echo -e "\nInstalling to $install_device"
    echo -e "IP address is: $(ip a)"
    if ! coreos-installer install --ignition="$ignition_file" "$install_device"; then
        echo -e "ERROR: coreos-installer failed! System will NOT reboot." >&2
        return 1
    else
        # Force the NEXT boot onto the installed disk so the machine cannot loop back into PXE/USB after reboot.
        set_efi_bootnext
        echo -e "Installation successful. Rebooting into installed system..."
    	/usr/bin/systemctl --no-block reboot
    fi
}

set_efi_bootnext(){
    if ! command -v efibootmgr >/dev/null 2>&1; then
        echo -e "efibootmgr not available (BIOS install?) - skipping BootNext."
        return 0
    fi
    local esp_uuid next_entry
    esp_uuid="$(blkid -s PARTUUID -o value /dev/disk/by-partlabel/EFI-SYSTEM 2>/dev/null || true)"
    if [[ -z "$esp_uuid" ]]; then
        echo -e "WARNING: could not resolve installed ESP PARTUUID; BootNext not set."
        return 0
    fi
    next_entry="$(efibootmgr -v 2>/dev/null | sed -n "s/^Boot\([0-9A-Fa-f]\{4\}\).*${esp_uuid}.*/\1/p" | head -n1)"
    if [[ -z "$next_entry" ]]; then
        echo -e "WARNING: no efibootmgr entry references ESP PARTUUID $esp_uuid."
        return 0
    fi
    if efibootmgr --bootnext "$next_entry" >/dev/null 2>&1; then
        echo -e "EFI BootNext set to Boot$next_entry (installed disk)."
    else
        echo -e "WARNING: failed to set EFI BootNext (firmware may boot the wrong device)."
    fi
    return 0
}

mount_conf_partition(){
	# Mounts the configuration partition on the boot media
	echo "Mounting boot partition, and searching for configuration file.."
	source  "/mnt/conf/wavelet.conf"
}

test_tools(){
	# Small function to test for necessary tools
	# Shove this into an array
	toolsArray=(
		sed
		mount
		butane
		tar
		gz
		mkpasswd
		ssh-keygen
		coreos-installer
	)
    for i in "$@"; doe
        if command -v "$i" >/dev/null 2>&1; then
            echo "	Tool $i available!"
        else
            echo "	ERROR:  Critical tool, $i, is unavailable!" >&2
            exit 1
        fi
    done
	echo "	Tool tests passed, continuing boot."
	echo -e "\033[33m*****\tTOOL TESTS PASSED, CONTINUING INSTALLATION	*****\033[0m" | systemd-cat -p 5 -t automated_coreos_deployment.sh
}




####
#
# Main
#
####

test_tools
main