#!/bin/bash

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
exec >/home/wavelet/ug_depends.log 2>&1
install_ug_depends