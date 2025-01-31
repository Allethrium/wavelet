#!/bin/bash
# Runs RPM-OStree overlay 
# Then extracts the downloaded tar files to their appropriate directories.  Should be one of the first things to run on initial boot.
# All wavelet modules, including the web server code, are deployed on all devices, however only the server has the web servers enabled.

detect_self(){
systemctl --user daemon-reload
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*)                   echo -e "I am an Encoder \n" && echo -e "Provisioning systemD units as an encoder.."            ;   event_encoder
	;;
	decX.wavelet.local)     echo -e "I am a Decoder, but my hostname is generic.  Randomizing my hostname, and rebooting"   ;   event_decoder 
	;;
	dec*)                   echo -e "I am a Decoder \n" && echo -e "Provisioning systemD units as a decoder.."              ;   event_decoder
	;;
	svr*)                   echo -e "I am a Server. Proceeding..."                                                          ;   event_server
	;;
	*)                      echo -e "This device Hostname is not set approprately, exiting \n" && exit 0
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
	export DKMS_KERNEL_VERSION=$(uname -r)
	# create directories, install git, clone wavelet and setup modules
	mkdir -p /home/wavelet/.config/containers/systemd/
	chown -R wavelet:wavelet /home/wavelet
	cd /home/wavelet
	rpm_ostree_install_git
	if [[ ! -f /var/tmp/DEV_ON ]]; then
		echo -e "\n\n***WARNING***\n\nDeveloper Mode is ON\n\nCloning from development repository..\n"
		git clone -b armelvil-working --single-branch https://github.com/ALLETHRIUM/wavelet 
	else
		echo -e "\nDeveloper Mode is off, cloning from main repository..\n"
		git clone https://github.com/ALLETHRIUM/wavelet
	fi
	generate_tarfiles
	# This seems redundant, but works to ensure correct placement+permissions of wavelet modules
	extract_base
	extract_home && extract_usrlocalbin
	# Install dependencies and base packages.  Could definitely be pared down.
	rpm_ostree_install
	# generate a hostname file so that dnsmasq's dhcp-script call works properly
	echo -e "${hostname}" > /var/lib/dnsmasq/hostname.local
	# Build and install decklink kmod/akmod to support pcie cards - **not functional yet, needs a lot of work**
	# sets up local rpm repository - there's an issue with importing Intel repo GPG keys which might need user intervention.
	# **NOTE** Broken until DNF is made to work with rpm-ostree installations again. **NOTE**
	# /usr/local/bin/local_rpm.sh
	# Add various libraries required for NDI and capture card support
	install_ug_depends
	# Perform any further customization required in our scripts
	hostname=$(hostname)
	sed -i "s/!!hostnamegoeshere!!/${hostname}/g" /usr/local/bin/wavelet_network_sense.sh
	get_ipValue
	sed -i "s/SVR_IPADDR/${IPVALUE}/g" /etc/dnsmasq.conf
}

get_ipValue(){
	# Gets the current IP address for this host
	IPVALUE=$(ip a | grep 192.168.1 | awk '/inet / {gsub(/\/.*/,"",$2); print $2}')
	if [[ "${IPVALUE}" == "" ]] then
			# sleep for five seconds, then call yourself again
			echo -e "\nIP Address is null, sleeping and calling function again\n"
			sleep 5
			get_ipValue
		else
			echo -e "\nIP Address is not null, testing for validity..\n"
			valid_ipv4() {
				local ip=$1 regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
				if [[ $ip =~ $regex ]]; then
					echo -e "\nIP Address is valid, continuing..\n"
					return 0
				else
					echo "\nIP Address is not valid, sleeping and calling function again\n"
					get_ipValue
				fi
			}
			valid_ipv4 "${IPVALUE}"
	fi
}

rpm_ostree_install_git(){
	# Needed because otherwise sway launches the userspace setup before everything is ready
	/usr/bin/rpm-ostree install -y -A git 
}
rpm_ostree_install(){
	echo -e "FROM quay.io/fedora/fedora-bootc:40
	ARG DKMS_KERNEL_VERSION
	# Install the appropriate kernel and headers from the base system
	RUN koji download-build --rpm --arch=x86_64 kernel-core-${DKMS_KERNEL_VERSION} && \
	koji download-build --rpm --arch=x86_64 kernel-devel-${DKMS_KERNEL_VERSION} && \
	koji download-build --rpm --arch=x86_64 kernel-modules-${DKMS_KERNEL_VERSION}
	RUN dnf install kernel-core-${DKMS_KERNEL_VERSION}.rpm \
	kernel-devel-${DKMS_KERNEL_VERSION}.rpm \
	kernel-modules-${DKMS_KERNEL_VERSION}.rpm -y
	# Install base OS packages
	RUN dnf install -y wget fontawesome-fonts wl-clipboard nnn mako sway bemenu rofi-wayland lxsession sway-systemd waybar \
        foot vim powerline powerline-fonts vim-powerline NetworkManager-wifi iw wireless-regdb wpa_supplicant \
        cockpit-bridge cockpit-networkmanager cockpit-system cockpit-ostree cockpit-podman buildah rdma avahi \
        iwlwifi-dvm-firmware.noarch iwlwifi-mvm-firmware.noarch etcd sha libsrtp libdrm python3-pip srt srt-libs \
        libv4l v4l-utils libva-v4l2-request pipewire-v4l2 ImageMagick intel-opencl \
        mesa-dri-drivers mesa-vulkan-drivers mesa-vdpau-drivers libdrm mesa-libEGL mesa-libgbm mesa-libGL \
        mesa-libxatracker alsa-lib pipewire-alsa alsa-firmware alsa-plugins-speex bluez-tools netcat busybox inotify-tools \
        make cmake dnf yum-utils createrepo dkms kernel-devel kernel-devel-matched kernel-headers usbutils \
        tuned realtime-setup realtime-tests rtkit jo gcc openssl-devel bzip2-devel libffi-devel zlib-devel \
        libuuid-devel libudev-devel gcc gcc-c++ git
	# RPMFusion repos and vendor blobs necessary for HW acceleration
	RUN dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
        https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
	RUN dnf install -y intel-media-driver intel-gpu-tools intel-compute-runtime oneVPL-intel-gpu intel-media-driver intel-gmmlib \
        intel-level-zero oneapi-level-zero libvpl intel-mediasdk libva libva-utils libva-v4l2-request libva-vdpau-driver intel-ocloc \
        ocl-icd opencl-headers mpv libsrtp mesa-dri-drivers intel-opencl libvdpau-va-gl mesa-vdpau-drivers libvdpau libvdpau-devel \
        libva-intel-driver ffmpeg ffmpeg-libs libheif-freeworld neofetch htop mesa-libOpenCL python3-pip srt srt-libs firefox \
        ffmpeg vlc libv4l v4l-utils libva-v4l2-request pipewire-v4l2 ImageMagick mplayer libndi libndi-devel ndi-sdk obs-ndi pipewire-utils firefox
	# Clone git repos
	RUN curl -L https://www.andymelville.net/wavelet/desktopvideo-12.8a19.x86_64.rpm -f --retry 5 > "desktopvideo.rpm"
	RUN git clone https://github.com/xanview/live555/
	RUN git clone https://github.com/gopro/cineform-sdk
	RUN git clone https://github.com/aja-video/libajantv2.git
	RUN curl -L https://downloads.ndi.tv/SDK/NDI_SDK_Linux/Install_NDI_SDK_v6_Linux.tar.gz -f --retry 5 > "Install_NDI_SDK_v6_Linux.tar.gz"
	RUN tar -xzvf Install_NDI_SDK_v6_Linux.tar.gz
	RUN yes | PAGER="cat" sh Install_NDI_SDK_v6_Linux.sh
	RUN cp -P NDI\ SDK\ for\ Linux/lib/x86_64-linux-gnu/* /usr/local/lib/
	RUN ldconfig
	RUN (cd live555 && ./genMakefiles linux-with-shared-libraries) && (cd live555 && make -j "$(nproc)") && (cd live555 && make install)
	RUN cmake -DAJANTV2_DISABLE_DEMOS=ON -DAJANTV2_DISABLE_DRIVER=OFF -DAJANTV2_DISABLE_TOOLS=OFF -DAJANTV2_DISABLE_TESTS=ON \
	-DAJANTV2_BUILD_SHARED=ON -DCMAKE_BUILD_TYPE=Release -Blibajantv2/build -Slibajantv2
	RUN cmake --build libajantv2/build --config Release -j "$(nproc)"
	RUN cmake --install libajantv2/build
	RUN (cd cineform-sdk && cmake -DBUILD_TOOLS=OFF && cmake --build . --parallel "$(nproc)" && cmake --install . && cd ..)
	RUN (mkdir -p /lib/modules/$KERNEL_VERSION && (ln -t /lib/modules/$KERNEL_VERSION /usr/src/kernels/$KERNEL_VERSION)) && (dnf install -y desktopvideo.rpm)
	" > Containerfile
	podman build --build-arg DKMS_KERNEL_VERSION=${DKMS_KERNEL_VERSION}
	touch /var/rpm-ostree-overlay.complete
	touch /var/rpm-ostree-overlay.rpmfusion.repo.complete
	touch /var/rpm-ostree-overlay.rpmfusion.pkgs.complete

	podman run --rm --privileged -v /dev:/dev -v /var/lib/containers:/var/lib/containers -v /:/target \
             --pid=host --security-opt label=type:unconfined_t \
             <image> \
             bootc install to-existing-root
}

generate_tarfiles(){
	echo -e "Generating tar.xz files for upload to distribution server..\n"
	tar -cJf usrlocalbin.tar.xz --owner=root:0 -C /home/wavelet/wavelet/webfiles/root/usr/local/bin/ .
	tar -cJf wavelethome.tar.xz --owner=wavelet:1337 -C /home/wavelet/wavelet/webfiles/root/home/wavelet/ .
	echo -e "Packaging files together..\n"
	tar -cJf wavelet-files.tar.xz {./usrlocalbin.tar.xz,wavelethome.tar.xz}
	echo -e "Done."
	rm -rf {./usrlocalbin.tar.xz,wavelethome.tar.xz}
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



####
#
#
# Main
#
#
####

# Perhaps add a checksum to make sure nothing's been tampered with here..
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
systemctl disable zincati.service --now
# Unlock RPM ostree persistently across reboots, needed for the weird library linking we are doing here and MAY sidestep the decklink issue.
# - update, NOPE.  and it breaks rpm-ostree installing anything so that's a no-go.
# ostree admin unlock --hotfix
#set -x
exec >/home/wavelet/wavelet_installer.log 2>&1
detect_self