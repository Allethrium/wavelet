#!/bin/bash
# Runs RPM-OStree overlay 
# Then extracts the downloaded tar files to their appropriate directories.  Should be one of the first things to run on boot.

rpm_ostree_install(){
/usr/bin/rpm-ostree install -A \
https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
echo -e "RPM Fusion repo installed, waiting for 5 seconds..\n"
wait 5

/usr/bin/rpm-ostree install \
-A wget fontawesome-fonts wl-clipboard nnn mako sway bemenu rofi-wayland lxsession sway-systemd waybar \
foot vim powerline powerline-fonts vim-powerline NetworkManager-wifi iw wireless-regdb wpa_supplicant \
cockpit-bridge cockpit-networkmanager cockpit-system cockpit-ostree cockpit-podman buildah rdma git \
iwlwifi-dvm-firmware.noarch iwlwifi-mvm-firmware.noarch etcd dnf yum-utils createrepo \
libsrtp libdrm python3-pip srt srt-libs libv4l v4l-utils libva-v4l2-request pipewire-v4l2 \
ImageMagick  intel-opencl mesa-dri-drivers mesa-vulkan-drivers mesa-vdpau-drivers libdrm mesa-libEGL mesa-libgbm mesa-libGL \
mesa-libxatracker alsa-lib pipewire-alsa alsa-firmware alsa-plugins-speex bluez-tools
echo -e "Base RPM Packages installed, waiting for 5 seconds..\n"
wait 5

/usr/bin/rpm-ostree install -A --idempotent intel-media-driver \
intel-gpu-tools intel-compute-runtime intel-basekit oneVPL-intel-gpu intel-media-driver intel-gmmlib \
intel-level-zero oneapi-level-zero oneVPL intel-mediasdk libva libva-utils libva-v4l2-request intel-ocloc \
ocl-icd opencl-headers mpv libsrtp mesa-dri-drivers intel-opencl \
mesa-libOpenCL python3-pip srt srt-libs ffmpeg vlc libv4l v4l-utils libva-v4l2-request pipewire-v4l2 \
ImageMagick mplayer firefox
echo -e "RPMFusion Media Packages installed, waiting for 5 seconds..\n"
wait 5
}

extract_base(){
	tar xf /home/wavelet/wavelet-files.tar.xz -C /home/wavelet --no-same-owner
	cd /home/wavelet
	mv ./usrlocalbin.tar.xz /usr/local/bin/

}
extract_etc(){
	umask 022
	tar xf /etc/etc.tar.xz -C /etc --no-same-owner --no-same-permissions
	echo -e "System config files setup successfully..\n"
}
extract_home(){
	tar xf /home/wavelet/wavelethome.tar.xz -C /home/wavelet
	chown -R wavelet:wavelet /home/wavelet
	echo -e "Wavelet homedir setup successfully..\n"
}
extract_usrlocalbin(){
	umask 022
	tar xf /usr/local/bin/usrlocalbin.tar.xz -C /usr/local/bin --no-same-owner
	chmod +x /usr/local/bin
	chmod 0755 /usr/local/bin/*
	echo -e "Wavelet modules setup successfully..\n"
}

# Perhaps add a checksum to make sure nothing's been tampered with here..
set -x
extract_base
extract_home && extract_usrlocalbin
rpm_ostree_install
systemctl disable zincati.service --now
touch /var/rpm-ostree-overlay.complete
touch /var/rpm-ostree-overlay.rpmfusion.repo.complete
touch /var/rpm-ostree-overlay.rpmfusion.pkgs.complete