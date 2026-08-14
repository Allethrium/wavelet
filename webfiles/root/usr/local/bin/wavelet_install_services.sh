#!/bin/bash
# This runs as a systemd unit on the SECOND boot on the SERVER ONLY
# It then proceeds to configure dependencies, then reboots
# Most of the wavelet modules and directory configuration incl. permissions that doesn't fit elsewhere is also handled here

# Source the wavelet configuration
if [[ -f "/etc/wavelet.conf" ]]; then
    source "/etc/wavelet.conf"
fi

install_ug_depends(){
	# This is lifted from the UltraGrid project with a couple of tweaks for CoreOS/my purposes
	# Needs to run as root after the second reboot, since it requires some of the coreos overlay features to be available.
	cd "/var/home/wavelet/setup" || return
	install_cineform(){
		# CineForm SDK
		git clone https://github.com/gopro/cineform-sdk
		cd cineform-sdk || return
		# Broken command: git apply "$curdir/0001-CMakeList.txt-remove-output-lib-name-force-UNIX.patch"
		# removed mkdir build && cd build too
		cmake -DBUILD_TOOLS=OFF
		cmake --build . --parallel "$(nproc)"
		cmake --install .
		cd "/var/home/wavelet/setup" || return
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
		cd "/var/home/wavelet/setup" || return
	}
	install_live555(){
		# Live555
		git clone https://github.com/xanview/live555/; cd live555 || return
		# Ensure DNO_STD_LIB is set otherwise compilation will fail
		sed -i 's|-D_FILE_OFFSET_BITS=64 -fPIC|-D_FILE_OFFSET_BITS=64 -fPIC -DNO_STD_LIB|g' "/var/home/wavelet/setup/live555/config.linux-with-shared-libraries"
		./genMakefiles linux-with-shared-libraries
		make -j "$(nproc)"
		make install
		cd "/var/home/wavelet/setup" || return
	}
	#install_libaja
	#install_cineform
	#install_live555
	cd /var/home/wavelet/setup || return
}

etcd_create_roles(){
	# Certificates should already be generated from wavelet_install_hardening
	sed -i "s|svrIP|$SVR_IP|g" "/etc/etcd.yaml.conf"
	sed -i "s|svrHostName|$SVR_HOSTNAME|g" "/etc/etcd.yaml.conf"
	mv "/etc/etcd.yaml.conf" "/etc/etcd/etcd.conf"
	echo "	Waiting for etcd service to spin up.."
	until systemctl start etcd-quadlet.service; do
		sleep .1
	done
	# RunOnce for server provisioning, creates etcd roles.
	echo -e "\n	Calling etcd_interaction to generate etcd authentication and roles..\n"
	# Ensure decoder ignition template is copied
	cp "/var/home/wavelet/config/decoder_custom.yml" "/var/home/wavelet/http/ignition/"
	/usr/local/bin/wavelet_etcd_management.sh "generate_etcd_core_roles"
}

generate_tftpboot() {
	local max_retries=3
	local retry_count=${1:-0}
	# The Containerfile will generate an output direct to /var/lib/tftpboot with a populated set of UEFI secure boot files.
	# Note that the shim may only load if the client host's BIOS/EFI is set to OS:Other -
	# the shim may not work with the microsoft defaults on some machines without complaints.
	# NOTE: --privileged is used here to allow the container to access network/boot files and generate the tftpboot directory structure.
	# This is necessary for the tftpboot generation process but should be documented as a security consideration.
	if [[ "$retry_count" -ge "$max_retries" ]]; then
		echo "	ERR: TFTPboot generation failed after $max_retries attempts, aborting."
		return 1
	fi
	if [[ -n "$DEPLOYMENT_REGISTRY" ]]; then
		echo "	Pulling prebuilt container image from LAN registry server.."
		if podman run --privileged --security-opt label=disable -v /var/lib:/tmp/ "$DEPLOYMENT_REGISTRY/tftpboot"; then
			echo "	TFTPboot directory generated! Continuing.."
			return 0
		else
			echo "	ERR:  issue pulling container.  Attempting to build tftpboot container image and execute locally.."
			(( retry_count++ ))
			generate_tftpboot "$retry_count"
			return $?
		fi
	else
		echo "	Building tftpboot container image and executing.."
		if podman build --tag tftpboot -f /home/wavelet/containerfiles/Containerfile.tftpboot; then
			podman run --privileged --security-opt label=disable -v /var/lib:/tmp/ "tftpboot"
			return 0
		else
			# This cannot be a failable step
			echo "	TFTPboot generation failed!  Attempting again!"
			(( retry_count++ ))
			generate_tftpboot "$retry_count"
			return $?
		fi
	fi
	# Grub aarch64 boot option (just here as placeholder)
	# curl http://ports.ubuntu.com/ubuntu-ports/dists/focal/main/uefi/grub2-arm64/current/grubnetaa64.efi.signed \
	# -o /var/lib/tftpboot/grubnetaa64.efi.signed
}

fedora_gpg_import() {
	# Imports Fedora GPG signing keys for CoreOS image verification.
	# These are the official Fedora release keys used to sign Fedora CoreOS
	# PXE images. The keyring is stored persistently for re-use.
	local keyring_dir="/var/home/wavelet/config/gpg"
	local keyring="$keyring_dir/fedora-coreos.gpg"
	mkdir -p "$keyring_dir"
	# Check if keyring already has usable keys
	if [[ -f "$keyring" ]] && gpg --no-default-keyring --keyring="$keyring" --list-keys 2>/dev/null | grep -q '^pub'; then
		return 0
	fi
	local tmpdir
	tmpdir="$(mktemp -d)"
	echo "	Downloading Fedora GPG signing key from fedoraproject.org..."
	if ! curl -fsSL --retry 3 --retry-delay 5 \
		-o "$tmpdir/fedora.gpg" \
		"https://fedoraproject.org/fedora.gpg"; then
		echo "  ERR: Failed to download Fedora GPG key for signature verification!"
		rm -rf "$tmpdir"
		return 1
	fi
	# Import into keyring format usable by gpgv
	if ! gpg --no-default-keyring --keyring="$keyring" --import "$tmpdir/fedora.gpg" 2>/dev/null; then
		echo "  ERR: Failed to import Fedora GPG key into keyring!"
		rm -rf "$tmpdir"
		return 1
	fi
	rm -rf "$tmpdir"
	echo "  Fedora GPG key imported successfully for CoreOS image verification."
	return 0
}

verify_coreos_signatures() {
	# Verifies downloaded CoreOS PXE images against their detached .sig files
	# using gpgv. Corrupted/mismatched files are removed so the caller can retry.
	local verify_dir="$1"
	local keyring="/var/home/wavelet/config/gpg/fedora-coreos.gpg"
	if [[ ! -f "$keyring" ]] || ! gpg --no-default-keyring --keyring="$keyring" --list-keys 2>/dev/null | grep -q '^pub'; then
		if ! fedora_gpg_import; then
			echo "  ERR: Cannot verify CoreOS image signatures -- Fedora GPG key unavailable."
			echo "  ERR: Supply chain verification disabled for this run."
			return 0
		fi
	fi
	local all_valid=0
	local verified_count=0
	for sigfile in "$verify_dir"/*.sig; do
		[[ -f "$sigfile" ]] || continue
		local datafile="${sigfile%.sig}"
		if [[ ! -f "$datafile" ]]; then
			echo "  WARN: Signature file $(basename "$sigfile") has no matching data file, skipping."
			continue
		fi
		echo "  Verifying signature: $(basename "$datafile")..."
		if gpgv --keyring="$keyring" "$sigfile" "$datafile"; then
			echo "    OK: $(basename "$datafile") -- signature valid."
			(( verified_count++ ))
		else
			echo "    FAIL: $(basename "$datafile") -- signature INVALID! Removing corrupted file."
			rm -f "$datafile" "$sigfile"
			all_valid=1
		fi
	done
	if [[ "$verified_count" -eq 0 ]] && [[ "$all_valid" -eq 0 ]]; then
		echo "  WARN: No CoreOS .sig files found to verify. Supply chain check skipped."
		echo "  WARN: Falling back to file existence check only."
		return 0
	fi
	if [[ "$all_valid" -ne 0 ]]; then
		echo "  ERR: One or more CoreOS image signature checks FAILED."
		echo "  ERR: Corrupted files removed; re-download will be attempted."
		return 1
	fi
	echo "  All available CoreOS image signatures verified successfully."
	return 0
}

pull_coreos_files() {
	# Copy coreos ISO files from the server (or download from internet sources)
	dir="/var/home/wavelet/setup"
	mkdir -p "/var/home/wavelet/http/pxe"
	if [[ -n $DEPLOYMENT_REGISTRY ]]; then
		# Get httpd contents
		cp "/etc/docker/certs.d/$DEPLOYMENT_IP:5000/ca.crt" "/var/home/wavelet/config/deployment_ca.crt"
		caCertLocation="/var/home/wavelet/config/deployment_ca.crt"
		HTTPD_SERVER="https://$DEPLOYMENT_IP:8443"
		echo "	Running external httpd initialization server, pulling from LAN source: $HTTPD_SERVER"
		result="$(curl --cacert "$caCertLocation" -s "$HTTPD_SERVER" | sed -n 's/.*href="\([^"]*\)".*/\1/p' | grep -E '\.[^/]+$')"
		echo -e "	Result:\n$result"
		# Generate our file candidate list
		declare -a files=()
		declare -a pids=()
		kernel=""; rootfs=""; initrd=""
		while IFS= read -r line; do
			filename="$(basename "$line")"
			# Include .sig files for verification
			if [[ "$filename" == *.sig ]]; then
				# Download .sig files as well
				sigFile="$line"
				echo "	Downloading signature: $HTTPD_SERVER/$sigFile"
				rm -rf "$dir/${sigFile##*/:-}"
				(
					until curl -f \
						--cacert "$caCertLocation" -s \
						-o "$dir/$(basename "$sigFile")" \
						--retry 3 --retry-delay 1 \
						"$HTTPD_SERVER/$sigFile"; do
						sleep .1;
					done
				) &
				pids+=($!)
				continue
			fi
			case "$(basename "$line")" in
                *live-rootfs*.img)	rootfs="$line"; files+=("$line");;
                *live-kernel.x86_64)	kernel="$line"; files+=("$line");;
                *live-initramfs*.img)	initrd="$line"; files+=("$line");;
				*)	: ;;
			esac
		done <<<"$result"
		for file in "${files[@]}"; do
			echo "	Downloading: $HTTPD_SERVER/$file"
			rm -rf "$dir/${file##*/:-}"
			(
					until curl -f \
					--cacert "$caCertLocation" -s \
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
		chown -R wavelet:wavelet "/var/home/wavelet/http/pxe"
		# Verify downloaded CoreOS images against their detached GPG signatures
		if ! verify_coreos_signatures "$dir"; then
			echo "  ERR: CoreOS image verification failed, clearing download state for retry."
			kernel=""; rootfs=""; initrd=""
		fi
	else
		echo "	Attempting to pull CoreOS images from internet sources.."
		# This can fail, hence gets it's own function with a retry
		# We need to "jog" DNS resolution
		ping -c 4 quad9.org
		# Download using coreos-installer (signature verification is enabled by default, use --insecure to disable)
		podman run --security-opt label=disable --pull=always --rm -v .:/data -w /data \
			"$(hostname -f)/coreos-installer:latest" download -f pxe
		echo "	CoreOS Image files downloaded with default signature verification, continuing to generate client machine ISO files.."
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
	# TODO - https implementation, does Grub even support this?
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
    cat > "/var/lib/tftpboot/pxelinux.cfg/default" <<-EOF
		DEFAULT pxeboot
		PROMPT 0
		TIMEOUT 150
		LABEL pxeboot
		KERNEL ${kernel##*/}
		INITRD ${initrd##*/},${rootfs##*/}
		APPEND coreos.inst.ignition.config.url=${configURL}
		IPAPPEND 2
	EOF
	# Generate grub.cfg (for UEFI)
	cat > "/var/lib/tftpboot/grub.cfg" <<EOF
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
EOF
	# Ensure correct files exist in the tftpboot rootdir
	cp /var/lib/tftpboot/EFI/fedora/{grubx64.efi,grubia32.efi,mmx64.efi,shimx64.efi,shim.efi} /var/lib/tftpboot/
    # Copy configs to HTTP server
    cp /var/lib/tftpboot/grub.cfg "/var/home/wavelet/http/pxe/"
    cp /var/lib/tftpboot/EFI/fedora/{grubx64.efi,grubia32.efi,mmx64.efi,shimx64.efi,shim.efi} "/var/home/wavelet/http/pxe/"
    cp "/var/lib/tftpboot/pxelinux.cfg/default" "/var/home/wavelet/http/pxe/pxelinux.cfg/"
}

generate_bootc_image() {
	# TODO - Develop full bootc container image now that it seems to be stabilizing 2H 2026
	local bootc_image_name="decoder-bootc-${coreosVersion:-latest}"
	podman build \
		--tag "$bootc_image_name" \
		-f /home/wavelet/containerfiles/Containerfile.bootc-decoder \
		/home/wavelet/containerfiles/
	# NOTE: --privileged is used here for the bootc-image-builder container to allow it to build bootable images.
	# This is necessary for the bootc-image-builder process but should be documented as a security consideration.
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
	# Ensure the CA & conf file is available for injection into the decoder.ign
	cp "/etc/ipa/ca.crt" "/var/home/wavelet/config/"
	cp "/etc/wavelet.conf" "/var/home/wavelet/config/"
	# Generate the CA sha256 hash
	caHash="$(sha256sum <"/etc/ipa/ca.crt" | tr -d \"[:space:]-\")"
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
	# Add the verification hash
	sed -i "s|wavelet_dc1_caHash|sha256-$caHash|g" /var/home/wavelet/config/decoder_custom.yml
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
	systemctl enable gssproxy.service --now
	# no.wifi is a mode flag, set via configuration
	systemctl enable avahi-daemon
	systemctl enable avahi-daemon.service --now
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

if [[ "$PXE_COMPLETE" == 1 ]]; then
	exit 0
fi

# Enable entropy daemon for quicker CA generation during hardening
# Haveged is installed in the client layer, so is available on all wavelet devices.
# We need to ensure we have an SElinux context here
# REF: https://github.com/fedora-selinux/selinux-policy/issues/3206
# Install pre-compiled haveged SELinux policy module to allow entropyd_t to create files in tmpfs_t
mkdir -p /var/lib/wavelet/selinux
if [[ -f "/var/lib/wavelet/selinux/my-haveged.pp" ]]; then
    semodule -i "/var/lib/wavelet/selinux/my-haveged.pp"
fi
systemctl enable haveged --now

# Wavelet modules are now preprovisioned on both the server and clients, and processed in the installer script
# So we don't need to handle them here.
install_ug_depends

echo "	Setting wavelet homedir permissions.."
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
PXE_SUCCESS=0
(
	echo "	Generating PXE and UEFI/HTTPS Boot infrastructure in subshell.."
	mkdir -p "/var/lib/tftpboot/pxelinux.cfg"
	mkdir -p "/var/home/wavelet/http/pxe/pxelinux.cfg/"
	mkdir -p "/var/home/wavelet/pxe" && cd "/var/home/wavelet/pxe" || exit 1
	mkdir -p "/var/lib/tftpboot"
	chmod +x {/var/home/wavelet/pxe,/var/home/wavelet/http,/var/home/wavelet/http/pxe}
	if ! generate_tftpboot; then
		echo "	ERR: TFTPboot generation failed, aborting PXE infrastructure setup."
		exit 1
	fi
	if ! generate_coreos_image; then
		echo "	ERR: CoreOS image generation failed, aborting PXE infrastructure setup."
		exit 1
	fi
	if ! configure_tftpboot; then
		echo "	ERR: TFTPboot configuration failed, aborting PXE infrastructure setup."
		exit 1
	fi
	# We don't need tftp files to be executable, maybe not even writable..
	find "/var/lib/tftpboot" -type f -print0 | xargs -0 chmod 644
	# Restore SElinux contexts or we will get an AVC denial when DHCP attempts to serve tftp requests
	restorecon -Rv "/var/lib/tftpboot"
	# Copy EFI files to http pxe
	if ! cp -R /var/lib/tftpboot/* "/var/home/wavelet/http/pxe"; then
		echo "	ERR: Copying EFI files to http pxe failed, aborting PXE infrastructure setup."
		exit 1
	fi
	if ! cp "/etc/wavelet.conf" "/var/home/wavelet/http/ignition/wavelet.conf"; then
		echo "	ERR: Copying wavelet.conf to ignition failed, aborting PXE infrastructure setup."
		exit 1
	fi
	if ! coreos_systemd_fix; then
		echo "	ERR: CoreOS systemd fix failed, aborting PXE infrastructure setup."
		exit 1
	fi
	if ! chown -R wavelet:wavelet "/var/home/wavelet/http"; then
		echo "	ERR: Setting http ownership failed, aborting PXE infrastructure setup."
		exit 1
	fi
	echo "	PXE infrastructure setup completed successfully."
	PXE_SUCCESS=1
) &
PXE_SUBPID=$!

HARDENING_SUBPID=0
(
	# Setup Domain Controller, PKI and provision service principals
	echo "	Calling hardening module to install security layer in subshell.."
	echo "	logs in: /var/roothome/logs/hardening.log"
	if ! /usr/local/bin/wavelet_install_hardening.sh > /dev/null 2>&1; then
		echo "	ERR: Hardening module failed, aborting DC provisioning."
		exit 1
	fi
	# Enable provision watcher for ETCD user RBAC as well as the domain enrollment watcher for generating our initial domain join OTP.
	if ! machinectl shell wavelet-root@ "$(which bash)" \
		-c "/usr/local/bin/wavelet_configure_radius.sh server"; then
		echo "	ERR: Configuring RADIUS failed."
		exit 1
	fi
	# Reload systemd daemon and reload registry to cut down on trace logspam
	if ! systemctl daemon-reload; then
		echo "	ERR: Systemd daemon-reload failed."
		exit 1
	fi
	if ! systemctl restart registry.service; then
		echo "	ERR: Restarting registry.service failed."
		exit 1
	fi
	# RADIUS seems to have some issues unless manually restarted
	if ! machinectl shell wavelet-root@ "$(which bash)" \
		-c "systemctl --user restart freeradius.service"; then
		echo "	ERR: Restarting freeradius.service failed."
		exit 1
	fi
	if [[ -f "/etc/pki/tls/certs/etcd.crt" ]]; then
		echo "	ETCD Certificate available, continuing to generate ETCD users and roles.."
		if ! etcd_create_roles; then
			echo "	ERR: ETCD roles creation failed."
			exit 1
		fi
	else
		echo "	Etcd cert not available, DC provisioning has encountered a fatal error!"
		echo "	Hardening log is available at:  /var/roothome/logs/"
		echo "	Please also check IPA logs in /var/freeipa-data/var/log/ for more information"
		exit 1
	fi
	if ! machinectl shell wavelet-root@ "$(which bash)" \
		-c "systemctl --user daemon-reload && systemctl --user enable wavelet_provision.service wavelet_enrollment_watcher.service wavelet_deprovision_watcher.service --now"; then
		echo "	ERR: Enabling provision watcher services failed."
		exit 1
	fi
	echo "	DC provisioning completed successfully."
) &
HARDENING_SUBPID=$!

# Wait for PXE subshell to complete and check its status
wait $PXE_SUBPID
PXE_EXIT_STATUS=$?
if [[ "$PXE_EXIT_STATUS" -ne 0 ]]; then
	echo "	ERR: PXE infrastructure setup subshell failed with exit status $PXE_EXIT_STATUS!"
	exit 1
fi

# Wait for hardening subshell to complete and check its status
if [[ "$HARDENING_SUBPID" -gt 0 ]]; then
	wait "$HARDENING_SUBPID"
	HARDENING_EXIT_STATUS="$?"
	if [[ $HARDENING_EXIT_STATUS -ne 0 ]]; then
		echo "	ERR: DC provisioning subshell failed with exit status $HARDENING_EXIT_STATUS!"
		exit 1
	fi
fi

echo "	Regenerating decoder ignition files and keys.."
generate_decoder_ignition

# These two steps require the subshell processes to have completed
cp "/etc/ipa/ca.crt" "/var/home/wavelet/http/ignition"

# Set PXE_COMPLETE=1 flag in wavelet.conf only after successful completion
echo "PXE_COMPLETE=1" >> "/etc/wavelet.conf"

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
# TODO - silence this to keep the log clean unless error
/usr/local/bin/UltraGrid.AppImage --appimage-extract
echo "	Extracted AppImage contents available in /usr/local/bin/ultragrid/squashfs-root/"
echo "	to invoke call the AppRun binary from this location or the /var/wavelet_ramfs dir"

# Generate the persistent ramdisk
mkdir -p "/var/wavelet_ramfs"
cat > "/etc/systemd/system/var-wavelet_ramfs.mount" <<-EOF
	[Unit]
	Description=Wavelet system ramdisk (tmpfs) for UltraGrid binaries

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

# Enable initramfs
rpm-ostree initramfs --enable

# Modify the Firefox policies.json
sed -i "s|https://localhost|https://$SVR_HOSTNAME|g" "/etc/firefox/policies/policies.json"
# Restart getty@tty1 to reload UI and start userland build process, which will run under the WAVELET user
systemctl restart getty@tty1