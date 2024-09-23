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
	echo -e "Installing packages..\n"
	rpm_ostree_install_step1(){
	/usr/bin/rpm-ostree install \
	-y -A \
	wget fontawesome-fonts wl-clipboard nnn mako sway bemenu rofi-wayland lxsession sway-systemd waybar \
	foot vim powerline powerline-fonts vim-powerline NetworkManager-wifi iw wireless-regdb wpa_supplicant \
	cockpit-bridge cockpit-networkmanager cockpit-system cockpit-ostree cockpit-podman buildah rdma avahi \
	iwlwifi-dvm-firmware.noarch iwlwifi-mvm-firmware.noarch etcd sha libsrtp libdrm python3-pip srt srt-libs \
	libv4l v4l-utils libva-v4l2-request pipewire-v4l2 ImageMagick intel-opencl \
	mesa-dri-drivers mesa-vulkan-drivers mesa-vdpau-drivers libdrm mesa-libEGL mesa-libgbm mesa-libGL \
	mesa-libxatracker alsa-lib pipewire-alsa alsa-firmware alsa-plugins-speex bluez-tools netcat busybox inotify-tools \
	echo -e "\nBase RPM Packages installed, waiting for 1 second..\n"
	sleep 1
	}
	rpm_ostree_install_step2(){
	/usr/bin/rpm-ostree install \
	-y -A \
	https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
	https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
	echo -e "\nRPM Fusion repo installed, waiting for 1 second..\n"
	sleep 1
	}
	rpm_ostree_install_step3(){
	# This is everything-and-the-kitchen sink approach to media acceleration.
	# libvpl libvpl-devel required for older intel CPU, has clash with oneVPL library however, so need detection logic.
	# Refresh Metadata
	/usr/bin/rpm-ostree refresh-md
	/usr/bin/rpm-ostree install \
	-y -A --idempotent \
	intel-media-driver \
	intel-gpu-tools intel-compute-runtime oneVPL-intel-gpu intel-media-driver intel-gmmlib \
	intel-level-zero oneapi-level-zero libvpl intel-mediasdk libva libva-utils libva-v4l2-request libva-vdpau-driver intel-ocloc \
	ocl-icd opencl-headers mpv libsrtp mesa-dri-drivers intel-opencl \
	libvdpau-va-gl mesa-vdpau-drivers libvdpau libvdpau-devel libva-intel-driver \
	ffmpeg ffmpeg-libs libheif-freeworld \
	neofetch htop \
	mesa-libOpenCL python3-pip srt srt-libs ffmpeg vlc libv4l v4l-utils libva-v4l2-request pipewire-v4l2 \
	ImageMagick mplayer \
	libndi libndi-devel ndi-sdk obs-ndi pipewire-utils
	echo -e "\nRPMFusion Media Packages installed, waiting for 1 second..\n"
	sleep 1
	}
	rpm_ostree_install_step4(){
	usr/bin/rpm-ostree install \
	-y -A --idempotent \
	make cmake dnf yum-utils createrepo dkms kernel-headers usbutils tuned realtime-setup realtime-tests rtkit jo \
	gcc openssl-devel bzip2-devel libffi-devel zlib-devel libuuid-devel libudev-devel \
	#gcc-c++ - BROKEN right now???
	echo -e "\nBuild and Dev packages installed, waiting for one second..\n"
	sleep 1
	}
	rpm_ostree_install_step1
	touch /var/rpm-ostree-overlay.complete
	rpm_ostree_install_step2
	touch /var/rpm-ostree-overlay.rpmfusion.repo.complete
	rpm_ostree_install_step3
	touch /var/rpm-ostree-overlay.rpmfusion.pkgs.complete
	rpm_ostree_install_step4
	touch /var/rpm-ostree-overlay.dev.pkgs.complete
	/usr/bin/rpm-ostree install -y -A --idempotent firefox
	echo -e "RPM package updates completed, finishing installer task..\n"
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

install_decklink(){
	# I can't seem to work this out.  It also seems like Fedora are experimenting more with bootc containers now?
	# adapted from https://github.com/coreos/layering-examples/tree/main/loading-kernel-module
	# Download Decklink software, extract and install base RPM's (required for Decklink support)
	# Won't work because.. i lack brain cells, apparently.
	cd /home/wavelet/
	podman build --build-arg KERNEL_VERSION=$(uname -r) -t quay.io/fedora/fedora-coreos:stable:kmm-kmod -f Containerfile
	FROM fedora:40 as builder
	ARG KERNEL_VERSION
	RUN dnf install -y \
		git \
		make
	WORKDIR /home
	# Get the kernel-headers
	RUN KERNEL_XYZ=$(echo ${KERNEL_VERSION} | cut -d"-" -f1) && \
	KERNEL_DISTRO=$(echo ${KERNEL_VERSION} | cut -d"-" -f2 | cut -d"." -f-2) && \
	KERNEL_ARCH=$(echo ${KERNEL_VERSION} | cut -d"-" -f2 | cut -d"." -f3) && \
	dnf install -y \
	https://kojipkgs.fedoraproject.org//packages/kernel/${KERNEL_XYZ}/${KERNEL_DISTRO}/${KERNEL_ARCH}/kernel-${KERNEL_VERSION}.rpm \
	https://kojipkgs.fedoraproject.org//packages/kernel/${KERNEL_XYZ}/${KERNEL_DISTRO}/${KERNEL_ARCH}/kernel-core-${KERNEL_VERSION}.rpm \
	https://kojipkgs.fedoraproject.org//packages/kernel/${KERNEL_XYZ}/${KERNEL_DISTRO}/${KERNEL_ARCH}/kernel-modules-${KERNEL_VERSION}.rpm \
	https://kojipkgs.fedoraproject.org//packages/kernel/${KERNEL_XYZ}/${KERNEL_DISTRO}/${KERNEL_ARCH}/kernel-modules-core-${KERNEL_VERSION}.rpm \
	https://kojipkgs.fedoraproject.org//packages/kernel/${KERNEL_XYZ}/${KERNEL_DISTRO}/x86_64/kernel-devel-${KERNEL_VERSION}.rpm
	# Here is where we'd want to copy the blackmagic DKMS modules into our container
	RUN git clone https://github.com/kubernetes-sigs/kernel-module-management
	RUN wget https://www.andymelville.net/wavelet/desktopvideo-12.7.1a1.x86_64.rpm
	# Extract RPM
	WORKDIR /home/kernel-module-management/ci/kmm-kmod
	RUN KERNEL_SRC_DIR=/lib/modules/${KERNEL_VERSION}/build make all
	FROM quay.io/fedora/fedora-coreos:stable
	ARG KERNEL_VERSION
	# Copy into overlay
	COPY --from=builder /home/kernel-module-management/ci/kmm-kmod/kmm_ci_a.ko /usr/lib/modules/${KERNEL_VERSION}/
	# This is needed in order to autoload the module at boot time.
	RUN depmod -a "${KERNEL_VERSION}" && echo kmm_ci_a > /etc/modules-load.d/kmm_ci_a.conf
	# Commit to ostree
	RUN rpm-ostree install strace && rm -rf /var/cache && \
	ostree container commit
}

install_ug_depends(){
	# This is lifted from the UltraGrid project with a couple of tweaks for CoreOS/my purposes
	# It builds dependencies for;
	#   Cineform
	#   libAJA to support AJA capture cards
	#   Live555 for rtmp
	#   LibNDI for Magewell devices
	cd /home/wavelet
	install_cineform(){
		# CineForm SDK
		git clone https://github.com/gopro/cineform-sdk
		cd cineform-sdk
		# Broken command: git apply "$curdir/0001-CMakeList.txt-remove-output-lib-name-force-UNIX.patch"
		# removed mkdir build && cd build too
		cmake -DBUILD_TOOLS=OFF
		cmake --build . --parallel "$(nproc)"
		sudo cmake --install .
		cd /home/wavelet
	}
	install_libaja(){
		#Install libAJA Library
		git clone https://github.com/aja-video/libajantv2.git
		# export MACOSX_DEPLOYMENT_TARGET=10.13 # needed for arm64 mac
		cmake -DAJANTV2_DISABLE_DEMOS=ON  -DAJANTV2_DISABLE_DRIVER=OFF \
		-DAJANTV2_DISABLE_TOOLS=OFF  -DAJANTV2_DISABLE_TESTS=ON \
		-DAJANTV2_BUILD_SHARED=ON \
		-DCMAKE_BUILD_TYPE=Release -Blibajantv2/build -Slibajantv2
		cmake --build libajantv2/build --config Release -j "$(nproc)"
		sudo cmake --install libajantv2/build
	}
	install_live555(){
		# Live555
		git clone https://github.com/xanview/live555/
		cd live555
		./genMakefiles linux-with-shared-libraries
		make -j "$(nproc)"
		make install
		cd /home/wavelet
	}
	install_libndi(){
		# LibNDI
		# Lifted from https://github.com/DistroAV/DistroAV/blob/master/CI/libndi-get.sh
		mkdir -p /home/wavelet/libNDI
		cd /home/wavelet/libNDI   
		LIBNDI_INSTALLER_NAME="Install_NDI_SDK_v6_Linux"
		LIBNDI_INSTALLER="$LIBNDI_INSTALLER_NAME.tar.gz"
		LIBNDI_INSTALLER_URL=https://downloads.ndi.tv/SDK/NDI_SDK_Linux/$LIBNDI_INSTALLER
		download_libndi(){
			curl -L $LIBNDI_INSTALLER_URL -f --retry 5 > "/home/wavelet/libNDI/$LIBNDI_INSTALLER"
			# Check if download was successful
			if [ $? -ne 0 ]; then
				echo "Download failed."
			fi
			echo "Download complete."
		}
	download_libndi
	tar -xzvf "/home/wavelet/libNDI/$LIBNDI_INSTALLER"
	yes | PAGER="cat" sh $LIBNDI_INSTALLER_NAME.sh
	cp -P /home/wavelet/libNDI/NDI\ SDK\ for\ Linux/lib/x86_64-linux-gnu/* /usr/local/lib/
	ldconfig
	ln -s /usr/local/lib/libndi.so.6 /usr/local/lib/libndi.so.5
	chown -R wavelet:wavelet /home/wavelet/libNDI
	echo -e "\nLibNDI Installed..\n"
	}
	install_libndi
	# Disabled these as GCC-C++ package is broken for CoreOS at the moment.
	#install_libaja
	#install_cineform
	#install_live555
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