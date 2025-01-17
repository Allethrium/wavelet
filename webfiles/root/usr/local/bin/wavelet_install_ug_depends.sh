#!/bin/bash
# This runs as a systemd unit on the SECOND boot on the SERVER ONLY
# Is ensures that the ostree overlay is available by falling back to an old method if container overlay failed.
# It then proceeds to configure dependencies, then reboots

install_ug_depends(){
	# This is lifted from the UltraGrid project with a couple of tweaks for CoreOS/my purposes
	# Needs to run as root after the second reboot, since it requires some of the coreos overlay features to be available.
	cd /var/home/wavelet/setup
	install_cineform(){
		# CineForm SDK
		git clone https://github.com/gopro/cineform-sdk
		cd cineform-sdk
		# Broken command: git apply "$curdir/0001-CMakeList.txt-remove-output-lib-name-force-UNIX.patch"
		# removed mkdir build && cd build too
		cmake -DBUILD_TOOLS=OFF
		cmake --build . --parallel "$(nproc)"
		cmake --install .
		cd /var/home/wavelet/setup
	}
	install_libaja(){
		#Install libAJA Library
		#Setting driver=ON breaks because I think it expects a card with valid S/N to be present.
		#Leaving this in here in the event it becomes relevant.
		git clone https://github.com/aja-video/libajantv2.git && \
		cmake -DAJANTV2_DISABLE_DEMOS=ON  -DAJANTV2_DISABLE_DRIVER=ON \
		-DAJANTV2_DISABLE_TOOLS=ON  -DAJANTV2_DISABLE_TESTS=ON \
		-DAJANTV2_BUILD_SHARED=ON \
		-DCMAKE_BUILD_TYPE=Release -Blibajantv2/build -Slibajantv2 && \
		cmake --build libajantv2/build --config Release -j "$(nproc)" && \
		sleep 2 && \
		sudo cmake --install libajantv2/build
		cd /var/home/wavelet/setup
	}
	install_live555(){
		# Live555
		git clone https://github.com/xanview/live555/; cd live555
		# Ensure DNO_STD_LIB is set otherwise compilation will fail
		sed -i 's|-D_FILE_OFFSET_BITS=64 -fPIC|-D_FILE_OFFSET_BITS=64 -fPIC -DNO_STD_LIB|g' /var/home/wavelet/setup/live555/config.linux-with-shared-libraries
		./genMakefiles linux-with-shared-libraries
		make -j "$(nproc)"
		make install
		cd /var/home/wavelet/setup
	}
	install_libndi(){
		# LibNDI
		# Lifted from https://github.com/DistroAV/DistroAV/blob/master/CI/libndi-get.sh
		mkdir -p /var/home/wavelet/setup/libNDI
		cd /var/home/wavelet/setup/libNDI   
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
		cp -P /var/home/wavelet/setup/libNDI/NDI\ SDK\ for\ Linux/lib/x86_64-linux-gnu/* /usr/local/lib/
		ldconfig
		chown -R wavelet:wavelet /home/wavelet/setup/libNDI
		echo -e "\nLibNDI Installed..\n"
		cd /var/home/wavelet/setup
	}
	#install_libaja
	install_cineform
	install_live555
	install_libndi
	touch /var/ug_depends.complete
	cd /var/home/wavelet/setup
}

rpm_ostree_install_git(){
	# Needed because otherwise sway launches the userspace setup before everything is ready
	# Some other packages which do not install properly in the ostree container build are also included here
	/usr/bin/rpm-ostree install -y -A git
}

generate_decoder_iso(){
	echo -e "\n\nCreating PXE functionality for client devices..\n\n"
	wavelet_pxe_grubconfig.sh
}

install_wavelet_modules(){
	# Git complains about the directory already existing so we'll just work in a tmpdir for now..
	rm -rf /var/home/wavelet/setup/wavelet-git;	mkdir -p /var/home/wavelet/setup/wavelet-git
	cd /var/home/wavelet/setup
	GH_REPO="https://github.com/Allethrium/wavelet"
	if [[ -f /var/developerMode.enabled ]]; then
		echo -e "\n***WARNING***\nDeveloper Mode is ON\nCloning from development repository..\n"
		GH_BRANCH="armelvil-working"
		git clone -b ${GH_BRANCH} ${GH_REPO} /var/home/wavelet/setup/wavelet-git && echo -e "Cloning git Dev repository..\n"
	else
		echo -e "\nDeveloper mode off, cloning main branch..\n"
		git clone https://github.com/ALLETHRIUM/wavelet /var/home/wavelet/setup/wavelet-git && echo -e "Cloning git Master repository..\n"
	fi
	generate_tarfiles
	# This seems redundant, but works to ensure correct placement+permissions of wavelet modules
	extract_base
	extract_home
	extract_usrlocalbin
	echo -e "$(hostname)" > /var/lib/dnsmasq/hostname.local
	# Perform any further customization required in our scripts, and clean up.
	sed -i "s/hostnamegoeshere/$(hostname)/g" /usr/local/bin/wavelet_network_sense.sh
	touch /var/extract.target
}

generate_tarfiles(){
	cd /var/home/wavelet/setup
	echo -e "Generating tar.xz files for upload to distribution server..\n"
	tar -cJf usrlocalbin.tar.xz --owner=root:0 -C /var/home/wavelet/setup/wavelet-git/webfiles/root/usr/local/bin/ .
	tar -cJf wavelethome.tar.xz --owner=wavelet:1337 -C /var/home/wavelet/setup/wavelet-git/webfiles/root/home/wavelet/ .
	tar -cJf etcd.tar.xz --owner=root:0 -C /var/home/wavelet/setup/wavelet-git/webfiles/root/etc .
	echo -e "Packaging files together..\n"
	tar -cJf wavelet-files.tar.xz {./usrlocalbin.tar.xz,wavelethome.tar.xz,etcd.tar.xz}
	echo -e "Done."
	rm -rf {./usrlocalbin.tar.xz,wavelethome.tar.xz,etc.tar.xz}
}

extract_base(){
	# Moves tar files to their target directories
	cd /var/home/wavelet/setup
	tar xf /home/wavelet/setup/wavelet-files.tar.xz -C /home/wavelet/setup --no-same-owner
	mv ./usrlocalbin.tar.xz /usr/local/bin/; mv ./etc.tar.xz /etc; mv ./wavelethome.tar.xz ../
}

extract_etc(){
	umask 022
	tar xf /etc/etc.tar.xz -C /etc --no-same-owner --no-same-permissions
	echo -e "System config files setup successfully..\n"
	rm -rf /etc/etc.tar.xz
}

extract_home(){
	tar xf /var/home/wavelet/wavelethome.tar.xz -C /var/home/wavelet
	echo -e "Wavelet homedir setup successfully..\n"
	rm -rf /var/home/wavelet/wavelethome.tar.xz
}

extract_usrlocalbin(){
	umask 022
	tar xf /usr/local/bin/usrlocalbin.tar.xz -C /usr/local/bin --no-same-owner
	chmod +x /usr/local/bin
	chmod -R 0755 /usr/local/bin/
	echo -e "Wavelet application modules setup successfully..\n"
	rm -rf /usr/local/bin/usrlocalbin.tar.xz
}


####
#
# Main
#
####

exec >/var/home/wavelet/logs/ug_depends.log 2>&1

# Set server hostname for network sense.  
sed -i "s|hostnamegoeshere|\"$(hostname)\"|g" /usr/local/bin/wavelet_network_sense.sh

mkdir -p /var/home/wavelet/setup

# Fix AVAHI otherwise NDI won't function correctly, amongst other things;  https://www.linuxfromscratch.org/blfs/view/svn/basicnet/avahi.html
# Runs first because it doesn't matter what kind of server/client device, it'll need this.
groupadd -fg 84 avahi && useradd -c "Avahi Daemon Owner" -d /run/avahi-daemon -u 84 -g avahi -s /bin/false avahi
groupadd -fg 86 netdev
systemctl enable avahi-daemon.service --now

# Fix gssproxy SElinux bug
ausearch -c '(gssproxy)' --raw | audit2allow -M my-gssproxy
semodule -X 300 -i my-gssproxy.pp

rpm_ostree_install_git

if vim --help; then 
	echo "Packages are available, Container overlay succeeded, continuing to install dependencies.."
else
	echo "Required packages are not available, installation has failed!  Please see logs/installer.log to troubleshoot."
	exit 1
fi

chmod g+s /var/home/wavelet
setfacl -dm u:wavelet:rwx /var/home/wavelet
setfacl -dm g:wavelet:rwx /var/home/wavelet
setfacl -dm o::rx /var/home/wavelet
install_ug_depends
install_wavelet_modules
#generate_decoder_iso
echo -e "Dependencies Installation completed..\n"
systemctl set-default graphical.target
touch /var/wavelet_depends.complete

# Generate sway service for allusers
echo "[Unit]
Description=sway - SirCmpwn's Wayland window manager
Documentation=man:sway(5)
BindsTo=default.target
Wants=default.target
After=default.target

[Install]
WantedBy=default.target

[Service]
Type=simple
EnvironmentFile=-%h/.config/sway/env
ExecStart=/usr/bin/sway
Restart=on-failure
RestartSec=1
TimeoutStopSec=10" > /etc/systemd/user/sway.service

# Apparently the pxe_grubconfig service might need some help to start..
systemctl enable wavelet_install_pxe.service --now