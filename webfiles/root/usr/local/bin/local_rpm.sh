#!/bin/bash
echo -e "ensuring DNSmasq is operating and available.."
systemctl enable dnsmasq.service --now
echo -e "Setting Date/Time to default inception location America/New_York.."
timedatectl set-timezone America/New_York
echo -e "generating a local folder in /http server directory and creating an RPM repository to serve packages locally \n"
echo -e "This will recatalog and copy all the packages currently in use on this system.  Download of about ~1Gb is required, which is the slowest operation here.\n"
echo -e "We do this so that new downloads aren't performed on every single additional device that's added."

# dnf downloads only installed packages
# This is a lazy way to do it - there may be unnecessary packages redownloaded here which we do not need to add.
mkdir -p /home/wavelet/http/repo_mirror/fedora/releases/38/x86_64/
# this is the minimal stuff, for a faster server deployment.  It'll be REALLY SLOW to deploy decoders without the full monty though..
#dnf reinstall -y --nogpgcheck --downloadonly --downloaddir=/home/wavelet/http/repo_mirror/fedora/releases/38/x86_64/ wget fontawesome-fonts wl-clipboard nnn mako sway bemenu rofi-wayland lxsession sway-systemd waybar foot vim powerline powerline-fonts vim-powerline NetworkManager-wifi iw wireless-regdb wpa_supplicant cockpit-bridge cockpit-networkmanager cockpit-system cockpit-ostree cockpit-podman buildah rdma git dnf GraphicsMagick wget oneapi-level-zero-devel intel-mediasdk libva-utils iwlwifi-dvm-firmware.noarch iwlwifi-mvm-firmware.noarch etcd yum-utils createrepo
dnf reinstall -y --nogpgcheck --downloadonly --downloaddir=/home/wavelet/http/repo_mirror/fedora/releases/38/x86_64/ `rpm -qa`
createrepo /home/wavelet/http/repo_mirror/fedora/releases/38/x86_64/
chown -R wavelet:wavelet /home/wavelet/http/repo_mirror



# This isn't at all related but this script is the only script run as root, so added it here
# If doing this intelligently, it SHOULD be its own unit
# Sets the CPU scaling to performance, which boosts CPU clockspeed across the board.
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Add wavelet to the audio group so that it can properly access audio devices
usermod -a -G audio wavelet

# This will switch the kernel to a COPR project called cachyos with a BORE scheduler, which is supposed to be lower latency..
# Ref: https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/
cd /etc/yum.repos.d/
sudo wget https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/repo/fedora-$(rpm -E %fedora)/bieszczaders-kernel-cachyos-fedora-$(rpm -E %fedora).repo
sudo rpm-ostree override remove kernel kernel-core kernel-modules kernel-modules-core --install kernel-cachyos-bore

sudo wget https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos-addons/repo/fedora-$(rpm -E %fedora)/bieszczaders-kernel-cachyos-addons-fedora-$(rpm -E %fedora).repo
sudo rpm-ostree install -A libcap-ng-devel procps-ng-devel
sudo rpm-ostree install -A uksmd
sudo systemctl enable uksmd.service
