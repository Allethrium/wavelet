#!/bin/bash
STREAM="next"
vlanName=""
podman run --pull=always --rm -v ./:/data -w /data quay.io/coreos/coreos-installer:release download -s "${STREAM}" -p qemu -f qcow2.xz --decompress
cp ignition_wavelet_test.yml test.yml
INPUTFILES="test.yml"
        touch rootpw.secure
        touch waveletpw.secure
        chmod 0600 *.secure
        unset tmp_rootpw
        unset tmp_waveletpw
tmp_rootpw="password123"
tmp_waveletpw="password123"
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
butane --pretty --strict --files-dir ./files/ ./test.yml --output test.ign

qcow2file=(*.qcow2)

virt-install --name=fcos --vcpus=8 --ram=8192 --boot uefi \
	--os-variant=fedora-coreos-next \
	--import --graphics=none \
	--qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=/home/andy/bootc-containers/test.ign" \
	--disk=size=32,backing_store=/home/andy/bootc-containers/${qcow2file} \
	--network=bridge=${vlanName}