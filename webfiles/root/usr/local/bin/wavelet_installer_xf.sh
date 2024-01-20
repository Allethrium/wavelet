#!/bin/bash
# Runs RPM-OStree overlay 
# Then extracts the downloaded tar files to their appropriate directories.  Should be one of the first things to run on initial boot.
# All wavelet modules, including the web server code, are deployed on all devices, however only the server has the web servers enabled.

detect_self(){
systemctl --user daemon-reload
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*) 					echo -e "I am an Encoder \n" && echo -e "Provisioning systemD units as an encoder.."			;	event_encoder
	;;
	decX.wavelet.local)		echo -e "I am a Decoder, but my hostname is generic.  Randomizing my hostname, and rebooting"	;	event_decoder 
	;;
	dec*)					echo -e "I am a Decoder \n" && echo -e "Provisioning systemD units as a decoder.."				;	event_decoder
	;;
	svr*)					echo -e "I am a Server. Proceeding..."  														;	event_server
	;;
	*) 						echo -e "This device Hostname is not set approprately, exiting \n" && exit 0
	;;
	esac
}

event_encoder(){
	extract_base
	extract_home && extract_usrlocalbin
	rpm_ostree_install
	exit 0
}

event_decoder(){
	extract_base
	extract_home && extract_usrlocalbin
	rpm_ostree_install
	exit 0
}

event_server(){
	mkdir -p /home/wavelet/.config/containers/systemd/
	chown -R wavelet:wavelet /home/wavelet
	extract_base
	extract_home && extract_usrlocalbin
	rpm_ostree_install
	/usr/local/bin/local_rpm.sh
}

rpm_ostree_install(){
/usr/bin/rpm-ostree install \
-y -A \
wget fontawesome-fonts wl-clipboard nnn mako sway bemenu rofi-wayland lxsession sway-systemd waybar \
foot vim powerline powerline-fonts vim-powerline NetworkManager-wifi iw wireless-regdb wpa_supplicant \
cockpit-bridge cockpit-networkmanager cockpit-system cockpit-ostree cockpit-podman buildah rdma git \
iwlwifi-dvm-firmware.noarch iwlwifi-mvm-firmware.noarch etcd dnf yum-utils createrepo \
libsrtp libdrm python3-pip srt srt-libs libv4l v4l-utils libva-v4l2-request pipewire-v4l2 \
ImageMagick  intel-opencl mesa-dri-drivers mesa-vulkan-drivers mesa-vdpau-drivers libdrm mesa-libEGL mesa-libgbm mesa-libGL \
mesa-libxatracker alsa-lib pipewire-alsa alsa-firmware alsa-plugins-speex bluez-tools
echo -e "Base RPM Packages installed, waiting for 2 seconds..\n"
sleep 5

/usr/bin/rpm-ostree install \
-y -A \
https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
echo -e "RPM Fusion repo installed, waiting for 2 seconds..\n"
sleep 2

/usr/bin/rpm-ostree install \
-y -A --idempotent \
intel-media-driver \
intel-gpu-tools intel-compute-runtime oneVPL-intel-gpu intel-media-driver intel-gmmlib \
intel-level-zero oneapi-level-zero oneVPL intel-mediasdk libva libva-utils libva-v4l2-request libva-vdpau-driver intel-ocloc \
ocl-icd opencl-headers mpv libsrtp mesa-dri-drivers intel-opencl \
libvdpau-va-gl mesa-vdpau-drivers libvdpau libvdpau-devel \
ffmpeg ffmpeg-libs libheif-freeworld \
neofetch \
mesa-libOpenCL python3-pip srt srt-libs ffmpeg vlc libv4l v4l-utils libva-v4l2-request pipewire-v4l2 \
ImageMagick mplayer
echo -e "RPMFusion Media Packages installed, waiting for 2 seconds..\n"
sleep 2

/usr/bin/rpm-ostree install \
-y -A --idempotent \
firefox
echo -e "Firefox installed for local console capability, waiting for two seconds..\n"
sleep 2

touch /var/rpm-ostree-overlay.complete
touch /var/rpm-ostree-overlay.rpmfusion.repo.complete
touch /var/rpm-ostree-overlay.rpmfusion.pkgs.complete
echo -e "RPM package updates completed, finishing installer task..\n"
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
	chmod 0755 /home/wavelet/http
	chmod -R 0755 /home/wavelet/http-php
	echo -e "Wavelet homedir setup successfully..\n"
}

extract_usrlocalbin(){
	umask 022
	tar xf /usr/local/bin/usrlocalbin.tar.xz -C /usr/local/bin --no-same-owner
	chmod +x /usr/local/bin
	chmod 0755 /usr/local/bin/*
	echo -e "Wavelet application modules setup successfully..\n"
}

# Perhaps add a checksum to make sure nothing's been tampered with here..
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
systemctl disable zincati.service --now
set -x
exec >/home/wavelet/wavelet_installer.log 2>&1
detect_self