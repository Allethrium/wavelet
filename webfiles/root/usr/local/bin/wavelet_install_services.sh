#!/bin/bash
# This runs as a systemd unit on the SECOND boot on the SERVER ONLY
# It then proceeds to configure dependencies, then reboots
# Most of the wavelet modules and directory configuration incl. permissions that doesn't fit elsewhere is also handled here

# Source the wavelet configuration helper functions
if [[ -f /etc/wavelet.conf ]]; then
    source /etc/wavelet.conf
fi

install_ug_depends(){
	# This is lifted from the UltraGrid project with a couple of tweaks for CoreOS/my purposes
	# Needs to run as root after the second reboot, since it requires some of the coreos overlay features to be available.
	cd /var/home/wavelet/setup || return
	install_cineform(){
		# CineForm SDK
		git clone https://github.com/gopro/cineform-sdk
		cd cineform-sdk || return
		# Broken command: git apply "$curdir/0001-CMakeList.txt-remove-output-lib-name-force-UNIX.patch"
		# removed mkdir build && cd build too
		cmake -DBUILD_TOOLS=OFF
		cmake --build . --parallel "$(nproc)"
		cmake --install .
		cd /var/home/wavelet/setup || return
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
		cd /var/home/wavelet/setup || return
	}
	install_live555(){
		# Live555
		git clone https://github.com/xanview/live555/; cd live555 || return
		# Ensure DNO_STD_LIB is set otherwise compilation will fail
		sed -i 's|-D_FILE_OFFSET_BITS=64 -fPIC|-D_FILE_OFFSET_BITS=64 -fPIC -DNO_STD_LIB|g' /var/home/wavelet/setup/live555/config.linux-with-shared-libraries
		./genMakefiles linux-with-shared-libraries
		make -j "$(nproc)"
		make install
		cd /var/home/wavelet/setup || return
	}
	#install_libaja
	#install_cineform
	#install_live555
	cd /var/home/wavelet/setup || return
}

etcd_create_roles(){
	# Certificates should already be generated from wavelet_install_hardening
	sed -i "s|svrIP|$SVR_IP|g" /etc/etcd.yaml.conf
	sed -i "s|svrHostName|$SVR_HOSTNAME|g" /etc/etcd.yaml.conf
	mv /etc/etcd.yaml.conf /etc/etcd/etcd.conf
	until systemctl start etcd-quadlet.service; do
		sleep 1
	done
	# RunOnce for server provisioning, creates etcd roles.
	echo -e "\n	Calling etcd_interaction to generate etcd authentication and roles..\n"
	# Ensure decoder ignition template is copied
	cp /var/home/wavelet/config/decoder_custom.yml /var/home/wavelet/http/ignition/
	/usr/local/bin/wavelet_etcd_management.sh "generate_etcd_core_roles"
}

generate_tftpboot() {
	# The Containerfile will generate an output direct to /var/lib/tftpboot with a populated set of UEFI secure boot files.
	# Note that the shim may only load if the client host's BIOS/EFI is set to OS:Other -
	# the shim may not work with the microsoft defaults on some machines without complaints.
	if [[ -n "$DEPLOYMENT_REGISTRY" ]]; then
		echo "	Pulling prebuilt container image from LAN registry server.."
		if podman run --tls-verify=false --privileged --security-opt label=disable -v /var/lib:/tmp/ "$DEPLOYMENT_REGISTRY:5000/tftpboot"; then
			echo "	TFTPboot directory generated! Continuing.."
		else
			echo "	ERR:  issue pulling container.  Attempting to build tftpboot container image and execute locally.."
			generate_tftpboot
		fi
	else
		echo "	Building tftpboot container image and executing.."
		if podman build --tag tftpboot -f /home/wavelet/containerfiles/Containerfile.tftpboot; then
			podman run --privileged --security-opt label=disable -v /var/lib:/tmp/ "tftpboot"
		else
			# This cannot be a failable step
			echo "	TFTPboot generation failed!  Attempting again!"
			generate_tftpboot
		fi
	fi
	# Grub aarch64 boot option (just here as placeholder)
	# curl http://ports.ubuntu.com/ubuntu-ports/dists/focal/main/uefi/grub2-arm64/current/grubnetaa64.efi.signed \
	# -o /var/lib/tftpboot/grubnetaa64.efi.signed
}

pull_coreos_files() {
	# Copy coreos ISO files from the server (or download from internet sources)
	dir="/var/home/wavelet/setup"
	mkdir -p "/var/home/wavelet/http/pxe"
	if [[ -n $DEPLOYMENT_REGISTRY ]]; then
		echo "	Running external httpd initialization server, pulling from LAN source: $DEPLOYMENT_REGISTRY"
		# Get httpd contents
		HTTPD_SERVER="http://$DEPLOYMENT_REGISTRY:8080"
		result="$(curl -s "$HTTPD_SERVER" | sed -n 's/.*href="\([^"]*\)".*/\1/p' | grep -E '\.[^/]+$')"
		# Generate our file candidate list
		declare -a files=()
		kernel=""; rootfs=""; initrd=""
		while IFS= read -r line; do
			filename="$(basename "$line")"
			if [[ "$filename" == *.sig ]]; then
				continue # skip line
			fi
			case "$(basename "$line")" in
                *live-rootfs*.img)	rootfs="$line"; files+=("$line");;
                *live-kernel.x86_64)	kernel="$line"; files+=("$line");;
                *live-initramfs*.img)	initrd="$line"; files+=("$line");;
				*)	: ;;
			esac
		done <<<"$result"
		pids=()
		for file in "${files[@]}"; do
			echo "	Downloading: $HTTPD_SERVER/$file"
			rm -rf "$dir/${file##*/}"
			(
				until curl -f \
				-o "$dir/$(basename "$file")" \
				--retry 3 --retry-delay 1 \
				"$HTTPD_SERVER/$file"; do
					sleep .1;
				done
				cp "$dir/${file##*/}" "/var/home/wavelet/http/pxe/" &
				cp "$dir/${file##*/}" "/var/lib/tftpboot/"
			) &
			pids+=($!)
		done
		for pid in "${pids[@]}"; do
			wait "$pid"
		done
		localFile=${file##*/}
		chown -R wavelet:wavelet "/var/home/wavelet/http/pxe"
	else
		echo "	Attempting to pull CoreOS images from internet sources.."
		# This can fail, hence gets it's own function with a retry
		# We need to "jog" DNS resolution
		ping -c 4 quad9.org
		podman run --security-opt label=disable --pull=always --rm -v .:/data -w /data \
			"$(hostname -f)/coreos-installer:latest" download -f pxe
		echo "	CoreOS Image files downloaded, continuing to generate client machine ISO files.."
	fi
	# Check the generated files exist
	coreosVersion="$(find $dir/*fedora* | head -n 1)"
	coreosVersion="${coreosVersion##*coreos-}"
	coreosVersion="${coreosVersion%%-live*}"
	if [[ -z "$initrd" ]] || [[ -z "$rootfs" ]] || [[ -z "$kernel" ]]; then
		echo "	Files missing! failing and retrying.."
		if (( attempt < 9 )); then
			(( attempt++ ))
			pull_coreos_files
		else
			echo "	Failed after 9 attempts, likely a network issue!"
			exit 1
		fi
	fi
	echo "	Pulled files: kernel=${kernel##*/} rootfs=${rootfs##*/} initrd=${initrd##*/}"
}

generate_coreos_image() {
	###
	# OLD METHOD - CoreOS Spinup w/ Ignition resulting in multiple redundant downloads from RPM sources etc.
	#	Advantages		-	Works reliably
	#	Disadvantages	-	requires multiple installation steps
	###
	# Remove custom-initramfs if already exists
	rm -rf /var/home/wavelet/pxe/custom-initramfs.img
	# Pull coreOS PXE
	attempt=0
	pull_coreos_files
	cp /var/home/wavelet/config/automated_installer.yml ./
	butane --pretty --files-dir ./ automated_installer.yml --output automated_installer.ign
	cp ./automated_installer.ign /var/home/wavelet/http/ignition/automated_installer.ign
	cp /usr/local/bin/wavelet_install_client.sh /var/home/wavelet/http/ignition
	# Customize for PXE boot automation
	# Ref https://coreos.github.io/coreos-installer/customizing-install/
	# DustyMabe to the rescue! https://dustymabe.com/2020/04/04/automating-a-custom-install-of-fedora-coreos/
	# automated_installer.ign is preconfigured by the wavelet_installer during initial setup process
	# Generate filenames and Modify grub2.cfg menu option

	# Copy boot images to both tftp and http server - NOTE /home/wavelet/pxe and /home/wavelet/http/pxe are NOT the same dirs!
	# Copy IP CA Cert so that it is available to the decoders on spinup (this should be changed once we enable HTTPS for apache!)
	# Generate the ignition file for the automated Live Installer, then generate the initial ignition file
	# Files required;
	#		automated_installer.yml (FCCT/Butane YML config for initial boot)
	#		automated_coreos_deployment.sh (HDD Detection script)
	#		decoder.ign (should be pre-provisioned from initial setup script prior to installing the server)
	configURL="http://$SVR_HOSTNAME:8080/ignition/automated_installer.ign"
	# The boot process now calls an initial coreOS Live image
	# This has an automation process burned in with a custom ignition file.
	# The enrollment and provision passwords are random
	# They are injected into the decoder ignition after the etcd management process has generated core users/roles.
	# Note we don't use HTTPS here as it's unlikely that the UEFI firmware booting this will trust our self-signed certificate,
	# so we leave http enabled
	# Because we are working (very) locally, and not passing secrets at this point, it isn't so much of a big deal.
	coreOShttpEntry="menuentry  'Decoder FCOS V.${coreosVersion} HTTP live boot' --class fedora --class gnu-linux --class gnu --class os {
echo -e '\nLoading CoreOS kernel...'
linuxefi (http,$(hostname):8080)/pxe/${kernel##*/} coreos.live.rootfs_url=http://$SVR_HOSTNAME:8080/pxe/${rootfs##*/} ignition.firstboot ignition.platform.id=metal ignition.config.url=${configURL}
echo 'Loading Fedora CoreOS initial ramdisk...'
initrdefi (http,$(hostname):8080)/pxe/${initrd##*/}
echo 'Booting Fedora CoreOS...'
}"
}

configure_tftpboot(){
    # Generate pxelinux config (for BIOS/legacy)
    echo -e "
DEFAULT pxeboot
PROMPT 0
TIMEOUT 150
LABEL pxeboot
KERNEL ${kernel##*/}
INITRD ${initrd##*/},${rootfs##*/}
APPEND coreos.inst.ignition.config.url=${configURL}
IPAPPEND 2" > "/var/lib/tftpboot/pxelinux.cfg/default"
	# Generate grub.cfg (for UEFI)
	echo -e "
function load_video {
    insmod all_video
}
load_video
set gfxpayload=keep
insmod gzio
insmod part_gpt
insmod ext2
insmod chain
insmod regexp
set default=2
set timeout=3
menuentry 'EFI Firmware System Setup' 'uefi-firmware' {
    fwsetup
}
menuentry 'Reboot' {
    reboot
}
${coreOShttpEntry}
# Legacy PXE (Syslinux) fallback
menuentry 'Legacy PXE (Syslinux)' {
    insmod pxelinux
    pxelinux
}
" > /var/lib/tftpboot/grub.cfg
	# Ensure correct files exist in the tftpboot rootdir
	cp /var/lib/tftpboot/EFI/fedora/{grubx64.efi,grubia32.efi,mmx64.efi,shimx64.efi,shim.efi} /var/lib/tftpboot/
    # Copy configs to HTTP server
    cp /var/lib/tftpboot/grub.cfg /var/home/wavelet/http/pxe/
    cp /var/lib/tftpboot/EFI/fedora/{grubx64.efi,grubia32.efi,mmx64.efi,shimx64.efi,shim.efi} /var/home/wavelet/http/pxe/
    cp /var/lib/tftpboot/pxelinux.cfg/default /var/home/wavelet/http/pxe/pxelinux.cfg/
}

generate_bootc_image() {
	# TODO - Develop full bootc container image now that it seems to be stabilizing 2H 2026
	local bootc_image_name="decoder-bootc-${coreosVersion:-latest}"
	podman build \
		--tag "$bootc_image_name" \
		-f /home/wavelet/containerfiles/Containerfile.bootc-decoder \
		/home/wavelet/containerfiles/
	podman run --rm -it --privileged \
		-v "$(pwd)":/output \
		-v /var/lib/containers/storage:/var/lib/containers/storage \
		registry.redhat.io/rhel9/bootc-image-builder:latest \
		--type pxe \
		--with-plymouth \
		--with-bootloader-entry \
		"$bootc_image_name"
	mkdir -p "/home/wavelet/http/pxe/bootc" "/var/lib/tftpboot/bootc"
	cp /output/*.efi "/home/wavelet/http/pxe/bootc/"
	cp /output/vmlinuz /output/initramfs.img "/var/lib/tftpboot/bootc/"
    coreOSbootCEntry="menuentry 'Decoder BootC V.${coreosVersion} PXE' --class fedora --class gnu-linux {
echo 'Loading BootC kernel...'
linuxefi (http,$SVR_HOSTNAME:8080)/pxe/bootc/vmlinuz \
	bootc.install.image=${REGISTRY}:5000/bootc-decoder:latest \
	bootc.install.pxe \
	bootc.install.pxe.kernel-args=console=tty0 \
	ignition.firstboot ignition.platform.id=metal
echo 'Loading BootC initramfs...'
initrdefi (http,$SVR_HOSTNAME:8080)/pxe/bootc/initramfs.img
}"
}

generate_wavelet_userspace_services(){
	# Generates the wavelet_build.service, which launches upon UI restart
	file="/home/wavelet/.config/systemd/user/wavelet_build.service"
	local targetFile
	if [[ -f "/var/wavelet_ramfs/wavelet_build.sh" ]]; then
		targetFile="/var/wavelet_ramfs/wavelet_build.sh"
	else
		targetFile="/usr/local/bin/wavelet_build.sh"
	fi
	cat > "$file" <<-EOF
		[Unit]
		Description=Wavelet Initial Setup Service
		After=network-online.target etcd-quadlet.service sway-session.target
		Wants=network-online.target sway-session.target

		[Service]
		Type=oneshot
		ExecStart=${targetFile}

		[Install]
		WantedBy=sway-session.target
	EOF
	chown wavelet:wavelet "$file"; chmod 0644 "$file"
	file="/home/wavelet/.config/systemd/user/wavelet_init.service"
	targetFile=""
	if [[ -f "/var/wavelet_ramfs/wavelet_init.sh" ]]; then
		targetFile="/var/wavelet_ramfs/wavelet_init.sh"
	else
		targetFile="/usr/local/bin/wavelet_init.sh"
	fi
	cat > "$file" <<-EOF
		[Unit]
		Description=Wavelet Initial Start Service
		After=network-online.target etcd-quadlet.service sway-session.target
		Wants=network-online.target sway-session.target

		[Service]
		Type=oneshot
		ExecStart=${targetFile}

		[Install]
		WantedBy=sway-session.target
	EOF
  chown wavelet:wavelet "$file"; chmod 0644 "$file"
}

generate_decoder_ignition(){
	# Generates the decoder ignition with wavelet_decoder_keys.csv
	# Populate vars for use below
	# TODO - these should be in the conf file now.
	# Ensure the CA is available for injection into the decoder.ign
	cp "/etc/ipa/ca.crt" "/var/home/wavelet/config/"
	cat > /var/home/wavelet/config/wavelet_decoder_keys.csv <<-EOF
		type,path,mode,overwrite,owner,group,content
		file,/etc/systemd/logind.conf.d/inhibit-suspend.conf,0644,,,[Login]\nHandleLidSwitch=ignore
		file,/etc/zincati/config.d/90-disable-auto-updates.toml,0644,,,[updates]\nenabled = false
		file,/etc/hosts,0664,true,,,127.0.0.1	localhost localhost.localdomain localhost4 localhost4.localdomain4\n::1	localhost localhost.localdomain localhost6 localhost6.localdomain6\n$SVR_IP	$SVR_HOSTNAME	${SVR_HOSTNAME%%.*}
		dir,/home/wavelet/config,0755,,wavelet,wavelet,
		dir,/home/wavelet/.ssh/secrets,0755,,wavelet,wavelet,
		dir,/home/wavelet/.config,0755,,wavelet,wavelet,
		dir,/home/wavelet/.config/systemd,0755,,wavelet,wavelet,
		dir,/home/wavelet/.config/systemd/user,0755,,wavelet,wavelet,
		dir,/home/wavelet/.config/systemd/user/default.target.wants,0755,,wavelet,wavelet,
		dir,/home/wavelet-root/.ssh/secrets,0755,,wavelet-root,wavelet-root,
		dir,/home/wavelet-root/config,0755,,wavelet-root,wavelet-root,
		dir,/etc/systemd/resolved.conf.d,0755,,,root,
		dir,/var/lib/systemd/linger/wavelet,0755,,,root,
		dir,/var/lib/systemd/linger/wavelet-root,0755,,,root,
	EOF
	echo -e "  \nRegenerating decoder.ign with enrollment and provision credentials.."
	sed -i "s|#hostname#|$DOMAIN|g" /var/home/wavelet/config/decoder_custom.yml
	# Embed the expected SHA512 hash of the wavelet archive.  wavelet_installer_update should alter this value on new git pulls.
	#sed -i "s|#waveletFilesVerificationHash|sha512-$(cat /var/secrets/waveletFiles_sha512.txt)|g" /var/home/wavelet/config/decoder_custom.yml
	butane --pretty --files-dir "/var/home/wavelet/config/" "/var/home/wavelet/config/decoder_custom.yml" \
		--output "/var/home/wavelet/http/ignition/decoder.ign"
	cp "/home/wavelet/config/automated_coreos_deployment.sh" "/var/home/wavelet/http/ignition/"
	chown -R wavelet:wavelet "/var/home/wavelet/http"
}

coreos_systemd_fix(){
	# Fix AVAHI, otherwise NDI won't function correctly
	# https://www.linuxfromscratch.org/blfs/view/svn/basicnet/avahi.html
	mkdir -p "/var/lib/avahi/services" && mkdir -p "/run/avahi-daemon"
	cat > "/etc/dbus-1/system.d/org.freedesktop.avahi.conf" << EOF
<!DOCTYPE busconfig PUBLIC
		  "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
		  "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <!-- Only root or user avahi can own the Avahi service -->
  <policy user="avahi">
	<allow own="org.freedesktop.Avahi"/>
  </policy>
  <policy user="root">
	<allow own="org.freedesktop.Avahi"/>
  </policy>
  <!-- Allow anyone to invoke methods on Avahi server, except SetHostName -->
  <policy context="default">
	<allow send_destination="org.freedesktop.Avahi"/>
	<allow receive_sender="org.freedesktop.Avahi"/>
	<deny send_destination="org.freedesktop.Avahi"
		  send_interface="org.freedesktop.Avahi.Server" send_member="SetHostName"/>
  </policy>
  <!-- Allow everything, including access to SetHostName to users of the group "adm" -->
  <policy group="adm">
	<allow send_destination="org.freedesktop.Avahi"/>
	<allow receive_sender="org.freedesktop.Avahi"/>
  </policy>
  <policy user="root">
	<allow send_destination="org.freedesktop.Avahi"/>
	<allow receive_sender="org.freedesktop.Avahi"/>
  </policy>
</busconfig>
EOF
	groupadd -fg 84 avahi && useradd -c "Avahi Daemon Owner" -d /run/avahi-daemon -u 84 -g avahi -s /bin/false avahi
	groupadd -fg 86 netdev
	# seems to work after two attempts
	systemctl start avahi-daemon.service
	systemctl restart avahi-daemon.service

	# Fix gssproxy SElinux bug
	ausearch -c '(gssproxy)' --raw | audit2allow -M my-gssproxy
	semodule -X 300 -i my-gssproxy.pp
	systemctl enable gssproxy.service --now
	# no.wifi is a mode flag, set via configuration
	set_config "WIFI_MODE_ENABLED" "no"
	systemctl enable avahi-daemon
	systemctl enable avahi-daemon.service --now
	/usr/local/bin/wavelet_system_optimize.sh
	echo -e " Dependencies Installation completed..\n"
	systemctl set-default graphical.target
}


#####
#
# Main
#
#####


exec >"/var/home/wavelet/logs/services.log" 2>&1

# Set server hostname for network sense.  
sed -i "s|hostnamegoeshere|\"$(hostname)\"|g" "/usr/local/bin/wavelet_network_sense.sh"
ip="$(hostname -I | cut -d " " -f 1)"
mkdir -p "/var/home/wavelet/setup"

if vim --help; then
	echo "  Packages are available, Container overlay succeeded, continuing to install dependencies.."
else
	echo "  Required packages are not available, installation has failed!  Please see logs/installer.log to troubleshoot."
	exit 1
fi

# Enable entropy daemon for quicker CA generation during hardening
# Haveged is installed in the client layer, so is available on all wavelet devices.
systemctl enable haveged --now

# Firewalld is installed from.. somewhere as a dependency.  Disable (for now until performance testing, because a firewall would be nice)
systemctl disable firewalld.service --now

# Wavelet modules are now preprovisioned on both the server and clients, and processed in the installer script
# So we don't need to handle them here.
install_ug_depends

echo "  Setting wavelet homedir permissions.."
chmod g+s "/var/home/wavelet"
setfacl -dm u:wavelet:rwx "/var/home/wavelet"
setfacl -dm g:wavelet:rwx "/var/home/wavelet"
setfacl -dm o::rx "/var/home/wavelet"

# We setup etcd core roles from root, since the etcd root pw should be accessible only from that user.
# We need to create logging files for these accounts.
mkdir -p "/var/home/root/logs"
mkdir -p "/var/home/wavelet-root/logs"
chown -R wavelet-root:wavelet-root "/var/home/wavelet-root/"

# Generate TFTPBOOT folder along with appropriate entries for our populated boot options
# We can run this in a parallel subshell as it's independent of the hardening process
(
	echo "	Generating PXE and UEFI/HTTPS Boot infrastructure in subshell.."
	mkdir -p "/var/lib/tftpboot/pxelinux.cfg"
	mkdir -p "/var/home/wavelet/http/pxe/pxelinux.cfg/"
	mkdir -p "/var/home/wavelet/pxe" && cd "/var/home/wavelet/pxe" || return
	mkdir -p "/var/lib/tftpboot"
	chmod +x {/var/home/wavelet/pxe,/var/home/wavelet/http,/var/home/wavelet/http/pxe}
	generate_tftpboot
	generate_coreos_image
	configure_tftpboot
	# We don't need tftp files to be executable, maybe not even writable..
	find /var/lib/tftpboot -type f -print0 | xargs -0 chmod 644
	# Restore SElinux contexts or we will get an AVC denial when DHCP attempts to serve tftp requests
	restorecon -Rv /var/lib/tftpboot
	# Copy EFI files to http pxe
	cp -R /var/lib/tftpboot/* "/var/home/wavelet/http/pxe"
	cp "/etc/wavelet.conf" "/var/home/wavelet/http/ignition/wavelet.conf"
	coreos_systemd_fix
	chown -R wavelet:wavelet /var/home/wavelet/http
) &

(
	# Setup Domain Controller, PKI and provision service principals
	echo "  Calling hardening module to install security layer in subshell.."
	/usr/local/bin/wavelet_install_hardening.sh > /dev/null 2>&1
	if [[ -f "/etc/pki/tls/certs/etcd.crt" ]]; then
		echo "  ETCD Certificate available, continuing to generate ETCD users and roles.."
		etcd_create_roles
	else
		echo "  Etcd cert not available, DC provisioning has encountered an error!"
		exit 1
	fi
	# Enable provision watcher for ETCD user RBAC as well as the domain enrollment watcher for generating our initial domain join OTP.
	machinectl shell wavelet-root@ "$(which bash)" \
		-c "systemctl --user daemon-reload && systemctl --user enable wavelet_provision.service wavelet_enrollment_watcher.service wavelet_deprovision_watcher.service --now"
	machinectl shell wavelet-root@ "$(which bash)" \
		-c "/usr/local/bin/wavelet_configure_radius.sh server"
	# Reload systemd daemon and reload registry to cut down on trace logspam
	systemctl daemon-reload
	systemctl restart registry.service
	# RADIUS seems to have some issues unless manually restarted
	machinectl shell wavelet-root@ "$(which bash)" \
		-c "systemctl --user restart freeradius.service"
	if [[ -f "/etc/pki/tls/certs/etcd.crt" ]]; then
		echo "	ETCD Certificate available, continuing to generate ETCD users and roles.."
		etcd_create_roles
	else
		echo "	Etcd cert not available, DC provisioning has encountered an error!"
		exit 1
	fi
) &

wait

echo "	Regenerating decoder ignition files and keys.."
generate_decoder_ignition

# These two steps require the subshell processes to have completed
cp "/etc/ipa/ca.crt" "/var/home/wavelet/http/ignition"

if is_state_flag_set "PXE_COMPLETE"; then
	exit 0
fi

# Ensure the wavelet user owns the http folder, and set +x and read perms on http folder and subfolders
chmod -R 0755 "/var/home/wavelet/http"
chown -R wavelet "/var/home/wavelet/"
chown -R wavelet-root "/var/home/wavelet-root"
chown -R kea:root "/var/lib/tftpboot"
# Remove executable bit from all FILES in http (folders need +x for apache to traverse them)
find "/var/home/wavelet/http/" -type f -print0 | xargs -0 chmod 644
find "/var/home/wavelet/http-php/" -type f -print0 | xargs -0 chmod 644
echo -e "	PXE bootable images completed and populated in http serverdir, client provisioning should now be available..\n"
# Clean up
rm -rf "/var/home/wavelet/pxe"

# Generate base layer virus checking and ensure everything is up to date
freshclam
# Rkhunter doesn't expect proper coreos directories so that might be more problematic here.  The propupd function would be nice, however.

# Generate UltraGrid squashfs dir so we don't need to worry about FUSE for some uses (reflector/hd-rum-translator)
mkdir -p "/usr/local/bin/ultragrid" && cd "/usr/local/bin/ultragrid"
/usr/local/bin/UltraGrid.AppImage --appimage-extract
echo "	Extracted AppImage contents available in /usr/local/bin/ultragrid/squashfs-root/"
echo "	to invoke call the AppRun binary from this location or the /var/wavelet_ramfs dir"

# Generate the persistent ramdisk
mkdir -p "/var/wavelet_ramfs"
cat > "/etc/systemd/system/var-wavelet_ramfs.mount" <<-EOF
	[Unit]
	Description=Wavelet system ramdisk (tmpfs) for UltraGrid binaries
	After=local-fs.target
	Wants=local-fs.target

	[Mount]
	What=tmpfs
	Where=/var/wavelet_ramfs
	Type=tmpfs
	# Mount options:
	#   size=1G     - cap at 1GiB (1073741824 bytes); tmpfs reports actual used
	#   mode=0755   - directory permissions after mount
	#   defaults    - standard mount options
	#   nosuid      - ignore setuid/setgid bits (security)
	#   nodev       - block creation of device files
	#   noatime     - avoid atime updates (reduces writes)
	Options=size=1G,nosuid,nodev,noatime,mode=0755

	[Install]
	WantedBy=multi-user.target
EOF
# Smaller ramfs mount for the wavelet user (wrapper files)
cat > "/etc/systemd/system/var-home-wavelet-ramfs.mount" <<-EOF
	[Unit]
	Description=Wavelet user ramdisk (tmpfs) for ephemeral scripts
	After=local-fs.target
	Wants=local-fs.target

	[Mount]
	What=tmpfs
	Where=/var/home/wavelet/ramfs
	Type=tmpfs
	Options=size=1M,nodev,noatime,mode=0755,uid=1337,gid=1337

	[Install]
	WantedBy=multi-user.target
EOF
cat > "/etc/systemd/system/wavelet_copyfiles.service" <<-EOF
	[Unit]
	Description=Copies binaries from /usr/local/bin to ramdisk
	After=var-wavelet_ramfs.mount
	Wants=var-wavelet_ramfs.mount

	[Service]
	ExecStart=/usr/bin/bash -c 'cp -a /usr/local/bin/* /var/wavelet_ramfs/'

	[Install]
	WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now var-wavelet_ramfs.mount var-home-wavelet-ramfs.mount wavelet_copyfiles.service

# Generate wavelet_build.service
generate_wavelet_userspace_services
# Restart getty@tty1 to reload UI and start userland build process, which will run under the WAVELET user
systemctl restart getty@tty1