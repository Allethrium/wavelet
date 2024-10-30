#!/bin/bash

# This mods ignition_server to enable it to spinup in a VM with some reasonable settings.  No DHCP, simple password.
# For testing purposes.

STREAM="stable"
mkdir -p $HOME/virt-wavelet
podman run --pull=always --rm -v $HOME/virt-wavelet/:/data:z -w /data quay.io/coreos/coreos-installer:release download -s "${STREAM}" -p qemu -f qcow2.xz --decompress
cp ignition_wavelet_test.yml test.yml
INPUTFILES="test.yml ignition_server_custom.yml"
        touch rootpw.secure
        touch waveletpw.secure
        chmod 0600 *.secure
        unset tmp_rootpw
        unset tmp_waveletpw
cp ignition_server.yml ignition_server_custom.yml
tmp_rootpw="testlab123"
tmp_waveletpw="wavelet123"
echo -e "${tmp_rootpw}"
mkpasswd --method=yescrypt "${tmp_rootpw}" > rootpw.secure
mkpasswd --method=yescrypt "${tmp_waveletpw}" > waveletpw.secure
unset tmp_rootpw tmp_waveletpw
repl=$(cat rootpw.secure)
sed -i "s|waveletrootpassword|${repl}|g" ${INPUTFILES}
repl=$(cat waveletpw.secure)
sed -i "s|waveletuserpassword|${repl}|g" ${INPUTFILES}
#        ssh-keygen -t ed25519 -C "wavelet@wavelet.local" -f wavelet
#        pubkey=$(cat wavelet.pub)
#        sed -i "s|PUBKEYGOESHERE|${pubkey}|g" ${INPUTFILES}
echo -e "Injecting dev branch into files..\n"
repl="https://raw.githubusercontent.com/Allethrium/wavelet/armelvil-working"
sed -i "s|https://github.com/Allethrium/wavelet/raw/master|${repl}|g" ${INPUTFILES}
sed -i "s|https://raw.githubusercontent.com/Allethrium/wavelet/master|${repl}|g" ${INPUTFILES}
#sed -i "s|/var/developerMode.enabled|/var/developerMode.disabled|g" ${INPUTFILES}
sed -i "s|DeveloperModeEnabled - will pull from working branch (default behavior)|DeveloperModeDisabled - pulling from master|g" ${INPUTFILES}
# Remove IP data from boot
repl=""
sed -i "s|    - ip=192.168.1.32::192.168.1.1:255.255.255.0:svr.wavelet.local::on|${repl}|g" ${INPUTFILES}

butane --pretty --strict --files-dir ./files/ ./test.yml --output test.ign
butane --pretty --strict --files-dir ./files/ ./ignition_server_custom.yml --output server.ign


qcow2file=(*.qcow2)

virt-install --name=fcos --vcpus=8 --ram=8192 --boot uefi \
        --os-variant=fedora-coreos-next \
        --import --graphics=none \
        --qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=$HOME/virt-wavelet/server.ign" \
        --disk=size=32,backing_store=$HOME/virt-wavelet/${qcow2file} \
        --network=bridge=bridge108