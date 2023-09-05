#!/bin/bash
echo -e "ensuring DNSmasq is operating and available.."
systemctl enable dnsmasq.service --now
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