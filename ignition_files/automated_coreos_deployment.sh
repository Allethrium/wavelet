#!/usr/bin/bash

# This script is a modification of that provided on:
# https://dustymabe.com/2020/04/04/automating-a-custom-install-of-fedora-coreos/
# It attempts to detect common block devices and configure the initial automation live installer for that device.

main() {
    # We tell the SECOND boot after installation is completed to utilize the client device ignition file.
    ignition_file="/home/decoder.ign"
    # We do NOT need an image file, because we already booted CoreOS from PXE.
    # Image url should be wherever our FCOS image is stored
    #  In Wavelet's case, the image is downloaded by wavelet_pxe_grubconfig.sh during server spinup
    # Note you'll want to use https and also copy the image .sig
    # to the appropriate place. Otherwise you'll need to `--insecure`
    # image_url='http://192.168.1.32:8080/pxe/fedora-coreos-31.20200310.3.0-metal.x86_64.raw.xz'
    # Some custom arguments for firstboot
    # firstboot_args='console=tty0'

    # Dynamically detect which device to install to.
    # This represents something an admin may want to do to share the
    # same installer automation across various hardware.
    nvme=$(lsblk -o name -lpn | grep "/dev/nv" | head -n 1)
    sata=$(lsblk -o name -lpn | grep "/dev/sd" | head -n 1)
    mmcblk=$(lsblk -o name -lpn | grep "/dev/mmcblk" | head -n 1)
    if [[ -b "${sata}" ]]; then
            install_device="${sata}"
            echo -e "SATA Device discovered!"
        elif [[ -b "${nvme}" ]]; then
            install_device="${nvme}"
            echo -e "NVME Device discovered!"
        elif [[ -b "${mmcblk}" ]]; then
            install_device="${mmcblk}"
            echo -e "EMMC Flash device discovered!"
        else
            return 1
    fi
    echo -e "\nInstalling to ${install_device}"
    echo -e "IP address is: $(ip a)"
    # We need to add --insecure and --insecure-ignition because currently the apache server does not serve https requests.
    cmd="coreos-installer install --firstboot-args=${firstboot_args}"
    cmd+="--insecure-ignition --ignition=${ignition_file}"
    cmd+=" ${install_device}"
    if $cmd; then
        echo "Install Succeeded!"
        return 0
    else
        echo "Install Failed!"
        return 1
    fi
}

####
#
# Main
#
####


main