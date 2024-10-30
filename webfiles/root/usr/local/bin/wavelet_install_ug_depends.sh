#!/bin/bash
# This runs as a systemd unit on the SECOND boot on the SERVER ONLY
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
	cd /var/home/wavelet
	install_cineform(){
		# CineForm SDK
		git clone https://github.com/gopro/cineform-sdk
		cd cineform-sdk
		# Broken command: git apply "$curdir/0001-CMakeList.txt-remove-output-lib-name-force-UNIX.patch"
		# removed mkdir build && cd build too
		cmake -DBUILD_TOOLS=OFF
		cmake --build . --parallel "$(nproc)"
		sudo cmake --install .
		cd /var/home/wavelet
	}
	install_libaja(){
		#Install libAJA Library
		git clone https://github.com/aja-video/libajantv2.git && \
		cmake -DAJANTV2_DISABLE_DEMOS=ON  -DAJANTV2_DISABLE_DRIVER=OFF \
		-DAJANTV2_DISABLE_TOOLS=ON  -DAJANTV2_DISABLE_TESTS=ON \
		-DAJANTV2_BUILD_SHARED=ON \
		-DCMAKE_BUILD_TYPE=Release -Blibajantv2/build -Slibajantv2 && \
		cmake --build libajantv2/build --config Release -j "1" && \
		sleep 2 && \
		sudo cmake --install libajantv2/build
		cd /var/home/wavelet
	}
	install_live555(){
		# Live555
		git clone https://github.com/xanview/live555/
		cd live555
		./genMakefiles linux-with-shared-libraries
		make -j "$(nproc)"
		make install
		cd /var/home/wavelet
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
		tar xvf ${LIBNDI_INSTALLER}
		yes | PAGER="cat" sh $LIBNDI_INSTALLER_NAME.sh
		cp -P /home/wavelet/libNDI/NDI\ SDK\ for\ Linux/lib/x86_64-linux-gnu/* /usr/local/lib/
		ldconfig
		chown -R wavelet:wavelet /home/wavelet/libNDI
		echo -e "\nLibNDI Installed..\n"
		cd /var/home/wavelet
	}
	#install_libaja
	install_cineform
	install_live555
	install_libndi
	touch /var/ug_depends.complete
}

rpm_ostree_install_git(){
	# Needed because otherwise sway launches the userspace setup before everything is ready
	# Some other packages which do not install properly in the ostree container build are also included here
	/usr/bin/rpm-ostree install -y -A git
	# We have to install avahi this way because the ostree overlay does NOT install dependencies correctly, and it's REQUIRED for NDI to function.
	/usr/bin/rpm-ostree install -y avahi --allow-inactive
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

install_wavelet_modules(){
	gitcommand="/usr/bin/git"
	cd /var/home/wavelet
	if [[ -f /var/developerMode.enabled ]]; then
		echo -e "\n\n***WARNING***\n\nDeveloper Mode is ON\n\nCloning from development repository..\n"
		GH_USER="armelvil"
		GH_BRANCH="armelvil-working"
	else
		echo -e "\nDeveloper mode off, cloning main branch..\n"
		GH_USER="ALLETHRIUM"
	fi
	GH_REPO="https://github.com/Allethrium/wavelet"
	# Git complains about the directory already existing so we'll just work in a tmpdir for now..
	rm -rf /var/home/wavelet/wavelet-git
	mkdir -p /var/home/wavelet/wavelet-git
	echo -e "\nCommand is; ${gitcommand} clone -b ${GH_BRANCH} ${GH_REPO} /var/home/wavelet/wavelet-git\n"
	git clone -b ${GH_BRANCH} ${GH_REPO} /var/home/wavelet/wavelet-git && echo -e "Cloning git repository..\n"
	generate_tarfiles
	# This seems redundant, but works to ensure correct placement+permissions of wavelet modules
	extract_base
	extract_home
	extract_usrlocalbin
	hostname=$(hostname)
	echo -e "${hostname}" > /var/lib/dnsmasq/hostname.local
	# Perform any further customization required in our scripts, and clean up.
	sed -i "s/!!hostnamegoeshere!!/${hostname}/g" /usr/local/bin/wavelet_network_sense.sh
	touch /var/extract.target
}

generate_tarfiles(){
	echo -e "Generating tar.xz files for upload to distribution server..\n"
	tar -cJf usrlocalbin.tar.xz --owner=root:0 -C /var/home/wavelet/wavelet-git/webfiles/root/usr/local/bin/ .
	tar -cJf wavelethome.tar.xz --owner=wavelet:1337 -C /var/home/wavelet/wavelet-git/webfiles/root/home/wavelet/ .
	echo -e "Packaging files together..\n"
	tar -cJf wavelet-files.tar.xz {./usrlocalbin.tar.xz,wavelethome.tar.xz}
	echo -e "Done."
	rm -rf {./usrlocalbin.tar.xz,wavelethome.tar.xz}
}

extract_base(){
	tar xf /home/wavelet/wavelet-files.tar.xz -C /home/wavelet --no-same-owner
	mv ./usrlocalbin.tar.xz /usr/local/bin/
}

extract_etc(){
	umask 022
	tar xf /etc/etc.tar.xz -C /etc --no-same-owner --no-same-permissions
	echo -e "System config files setup successfully..\n"
}

extract_home(){
	tar xf /var/home/wavelet/wavelethome.tar.xz -C /var/home/wavelet
	echo -e "Wavelet homedir setup successfully..\n"
}

extract_usrlocalbin(){
	umask 022
	tar xf /usr/local/bin/usrlocalbin.tar.xz -C /usr/local/bin --no-same-owner
	chmod +x /usr/local/bin
	chmod -R 0755 /usr/local/bin/
	echo -e "Wavelet application modules setup successfully..\n"
}

fun_with_dkms(){
	# Perhaps there's something we can do here to build the DKMS kernel module or at minimum decompress it and sign it with a MOK..
	mkdir -p /home/wavelet/signmodules # These eventually go into /var/lib/${VENDOR}
	cd /home/wavelet/signmodules
	# This would normally be an openssl command, but it seems RedHat have some tools that are a bit smoother to utilize..
	efikeygen --dbdir /etc/pki/pesign --self-sign --module --common-name 'CN=ALLETHRIUM' --nickname 'Wavelet modules Secure Boot key'
	certutil -d /etc/pki/pesign -n 'Wavelet modules Secure Boot key' -Lr > sb_cert.cer
	openssl pkcs12 -in sb_cert.p12  -out sb_cert.priv  -nocerts -noenc
	cp /usr/lib/modules/6.10.6-200.fc40.x86_64/extra/black*.ko.xz /home/wavelet/signmodules
	# Decompress .xz file
	for file in files; do
		mv ${file} predecompress.${file}
	done
	for file in files; do
		xz -d ${file}
		# Sign the files, move them to kernel mods directory, then remove the key files we generated (!!)
		/usr/src/kernels/$(uname -r)/scripts/sign-file sha256 sb_cert.priv sb_cert.cer *.ko
		mv *.ko /lib/modules/$(uname -r)/extra
		rm -rf {sb_cert.cer,sb_cert.priv}
	done
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
chmod g+s /var/home/wavelet
setfacl -dm u:wavelet:rwx /var/home/wavelet
setfacl -dm g:wavelet:rwx /var/home/wavelet
setfacl -dm o::rx /var/home/wavelet
install_ug_depends
install_wavelet_modules
#generate_decoder_iso
echo -e "Dependencies Installation completed..\n"
touch /var/wavelet_depends.complete
# Apparently the pxe_grubconfig service might need some help to start..
systemctl enable wavelet_install_pxe.service --now