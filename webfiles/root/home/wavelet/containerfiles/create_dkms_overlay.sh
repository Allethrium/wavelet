#!/bin/bash
export DKMS_KERNEL_VERSION=$(uname -r)
podman build --squash --build-arg DKMS_KERNEL_VERSION=${DKMS_KERNEL_VERSION} .

containerID=$(podman images | grep bootc | awk '{print $3}')
podman tag ${containerID} dkms

# verify container is there
podman images
# verify container functionality


# apply container to CoreOS host!
rpm-ostree --bypass-driver --experimental rebase ostree-unverified-image:containers-storage:localhost/dkms

# if tests=good, touch succcess
touch /var/ostree_bootc_rebase.complete

#Reboot
systemctl reboot