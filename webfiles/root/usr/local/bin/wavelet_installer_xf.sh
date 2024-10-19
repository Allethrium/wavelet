#!/bin/bash
# Runs RPM-OStree overlay 
# Then extracts the downloaded tar files to their appropriate directories.  Should be one of the first things to run on initial boot.
# All wavelet modules, including the web server code, are deployed on all devices, however only the server has the web servers enabled.

detect_self(){
systemctl --user daemon-reload
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*)                   echo -e "I am an Encoder \n" && echo -e "Provisioning systemD units as an encoder.."            ;   event_decoder
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

event_decoder(){
	extract_base
	extract_home && extract_usrlocalbin
	rpm_overlay_install_decoder
	echo -e "Initial provisioning completed, attempting to connect to WiFi..\n"
	connectwifi
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
	# Attempt to install from overlay container, if fails, we will run old method.
	rpm_overlay_install
	# Generating a local repository is no longer needed, because we are using an ostree overlay for the server and for future client machines.
	#/usr/local/bin/local_rpm.sh
	# generate a hostname file so that dnsmasq's dhcp-script call works properly
	echo -e "${hostname}" > /var/lib/dnsmasq/hostname.local
	# Add various libraries required for NDI and capture card support
	install_ug_depends
	# Perform any further customization required in our scripts
	hostname=$(hostname)
	sed -i "s/!!hostnamegoeshere!!/${hostname}/g" /usr/local/bin/wavelet_network_sense.sh
	get_ipValue
	sed -i "s/SVR_IPADDR/${IPVALUE}/g" /etc/dnsmasq.conf
	# Generate the wavelet decoder ISO
	generate_decoder_iso
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
	alsa-firmware alsa-lib alsa-plugins-speex avahi bemenu bluez-tools buildah busybox butane bzip2-devel \
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

rpm_overlay_install(){
	echo -e "Installing via container and applying as Ostree overlay..\n"
	DKMS_KERNEL_VERSION=$(uname -r)
	podman build -t localhost/coreos_overlay --build-arg DKMS_KERNEL_VERSION=${DKMS_KERNEL_VERSION} -f /home/wavelet/containerfiles/Containerfile.coreos.overlay
	if rpm-ostree --bypass-driver --experimental rebase ostree-unverified-image:containers-storage:localhost/coreos_overlay; then
		touch /var/rpm-ostree-overlay.complete
		touch /var/rpm-ostree-overlay.rpmfusion.repo.complete && \
		touch /var/rpm-ostree-overlay.rpmfusion.pkgs.complete && \
		touch /var/rpm-ostree-overlay.dev.pkgs.complete
		echo -e "\n\nRPM package updates completed, pushing container to registry for client availability, and finishing installer task..\n\n"
		# Push the image to the registry and ensure it's tagged, then remove local image to save storage.
		podman tag localhost/coreos_overlay localhost:5000/coreos_overlay:latest
		podman push localhost:5000/coreos_overlay:latest --tls-verify=false 
		podman rmi localhost:5000/coreos_overlay -f
	else
		echo -e "RPM Ostree overlay failed!  Reverting to old method..\n"
		rpm_ostree_install_git
		rpm_ostree_install
	fi
}

rpm_overlay_install_decoder(){
	# This differs from the server in that we don't need to build the container,
	# and we pull the already generated overlay from the server registry
	echo -e "Installing via container and applying as Ostree overlay..\n"
	DKMS_KERNEL_VERSION=$(uname -r)
	if rpm-ostree --bypass-driver --experimental rebase ostree-unverified-image:containers-storage:192.168.1.32:5000/coreos_overlay; then
		touch /var/rpm-ostree-overlay.complete
		touch /var/rpm-ostree-overlay.rpmfusion.repo.complete && \
		touch /var/rpm-ostree-overlay.rpmfusion.pkgs.complete && \
		touch /var/rpm-ostree-overlay.dev.pkgs.complete
		echo -e "RPM package updates completed, finishing installer task..\n"
	else
		echo -e "RPM Ostree overlay failed!  Reverting to old method..\n"
		rpm_ostree_install_git
		rpm_ostree_install
	fi
}

generate_decoder_iso(){
	echo -e "\n\nCreating PXE functionality..\n\n"
	wavelet_pxe_grubconfig.sh
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

install_ug_depends(){
	# This is lifted from the UltraGrid project with a couple of tweaks for CoreOS/my purposes
	# It builds dependencies for;
	#   Cineform
	#   libAJA to support AJA capture cards
	#   Live555 for rtmp
	#   LibNDI for Magewell devices
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
		yes | PAGER="cat" sh $LIBNDI_INSTALLER_NAME.sh
		cp -P /home/wavelet/libNDI/NDI\ SDK\ for\ Linux/lib/x86_64-linux-gnu/* /usr/local/lib/
		ldconfig
		chown -R wavelet:wavelet /home/wavelet/libNDI
		echo -e "\nLibNDI Installed..\n"
	}
	install_libaja
	install_cineform
	install_live555
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
# Debug flag
# set -x
exec >/home/wavelet/wavelet_installer.log 2>&1
detect_self