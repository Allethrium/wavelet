#!/bin/bash
# This runs as a systemd unit on the SECOND boot.  
# Is ensures that the ostree overlay is available by falling back to an old method if container overlay failed.
# It then proceeds to configure dependencies, then reboots

install_ug_depends(){
	# This is lifted from the UltraGrid project with a couple of tweaks for CoreOS/my purposes
	# It builds dependencies for;
	#   Cineform
	#   libAJA to support AJA capture cards
	#   Live555 for rtmp
	#   LibNDI for Magewell devices
	# Needs to run as root after the second reboot, since it requires some of the coreos overlay features to be available.
	pip install zfec
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
		tar xvf ${LIBNDI_INSTALLER}
		yes | PAGER="cat" sh $LIBNDI_INSTALLER_NAME.sh
		cp -P /home/wavelet/libNDI/NDI\ SDK\ for\ Linux/lib/x86_64-linux-gnu/* /usr/local/lib/
		ldconfig
		chown -R wavelet:wavelet /home/wavelet/libNDI
		echo -e "\nLibNDI Installed..\n"
	}
	install_libaja
	install_cineform
	install_live555
	install_libndi
	touch /var/ug_depends.complete
}

rpm_ostree_install_git(){
	# Needed because otherwise sway launches the userspace setup before everything is ready
	# Some other packages which do not install properly in the ostree container build are also included here
	/usr/bin/rpm-ostree install -y -A git avahi
}

rpm_ostree_install(){
	# Retained as failover encase the new procedure breaks
	echo -e "Installing packages..\n"
	rpm_ostree_install_step1(){
	/usr/bin/rpm-ostree install \
	-y -A \
	alsa-firmware alsa-lib alsa-plugins-speex bemenu bluez-tools buildah busybox butane bzip2-devel \
	cmake cockpit-bridge cockpit-networkmanager cockpit-ostree cockpit-podman cockpit-system createrepo \
	dkms dnf etcd ffmpeg ffmpeg ffmpeg-libs firefox fontawesome-fonts foot gcc htop \
	ImageMagick ImageMagick inotify-tools \
	intel-compute-runtime intel-gmmlib intel-gpu-tools intel-level-zero intel-media-driver \
	intel-media-driver intel-mediasdk intel-ocloc intel-opencl intel-opencl ipxe-bootimgs-x86.noarch iw iwlwifi-dvm-firmware.noarch iwlwifi-mvm-firmware.noarch \
	jo kernel-headers libdrm libdrm libffi-devel libheif-freeworld libndi libndi-devel libsrtp libsrtp libudev-devel libuuid-devel \
	libv4l libv4l libva libva-intel-driver libva-utils libva-v4l2-request libva-v4l2-request libva-v4l2-request libva-vdpau-driver \
	libvdpau libvdpau-devel libvdpau-va-gl libvpl lxsession \
	make mako mesa-dri-drivers mesa-dri-drivers mesa-libEGL mesa-libgbm mesa-libGL mesa-libOpenCL mesa-libxatracker mesa-vdpau-drivers mesa-vdpau-drivers mesa-vulkan-drivers mplayer mpv \
	ndi-sdk neofetch netcat NetworkManager-wifi nnn obs-ndi ocl-icd oneapi-level-zero oneVPL-intel-gpu opencl-headers openssl-devel \
	pipewire-alsa pipewire-utils pipewire-v4l2 pipewire-v4l2 powerline powerline-fonts python3-pip \
	rdma realtime-setup realtime-tests rofi-wayland rtkit sha srt srt srt-libs srt-libs sway sway-systemd syslinux syslinux-efi64 syslinux-nonlinux \
	tftp-server tuned usbutils v4l-utils v4l-utils vim vim-powerline vlc waybar wget wireless-regdb wl-clipboard wpa_supplicant yum-utils zlib-devel
	echo -e "\nRPMFusion Media Packages installed, waiting for 1 second..\n"
	sleep 1
	}
	rpm_ostree_install_step1
	touch /var/rpm-ostree-overlay.complete
	touch /var/rpm-ostree-overlay.rpmfusion.repo.complete && \
	touch /var/rpm-ostree-overlay.rpmfusion.pkgs.complete && \
	touch /var/rpm-ostree-overlay.dev.pkgs.complete
	echo -e "RPM package updates completed, finishing installer task..\n"
}

generate_decoder_iso(){
	echo -e "\n\nCreating PXE functionality for client devices..\n\n"
	wavelet_pxe_grubconfig.sh
}


####
#
# Main
#
####


exec >/home/wavelet/ug_depends.log 2>&1
rpm_ostree_install_git
if vim --help; then 
	echo "Packages are available, Container overlay succeeded, continuing to install dependencies..\n"
else
	echo "Packages are not available, attempting to install live from old rpm-ostree layering approach..\n"
	rpm_ostree_install
fi
install_ug_depends
generate_decoder_iso
echo -e "Installation completed, rebooting..\n"
sleep 5
return 0