#!/usr/bin/bash

# This script is a modification of that provided on:
# https://dustymabe.com/2020/04/04/automating-a-custom-install-of-fedora-coreos/
# It attempts to detect common block devices and configure the initial automation live installer for that device.

# 11/2026 Update - we now handle the ignition customization pass here

RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"

install_operatingSystem() {
    # The SECOND boot after installation uses the generated ignition file.
    # We already booted CoreOS from PXE, so no image file is required.

    # Dynamically detect which device to install to.
    # This represents something an admin may want to do to share the
    # same installer automation across various hardware.
    nvme=$(lsblk -o name -lpn | grep "/dev/nvme" | head -n 1)
    sata=$(lsblk -o name -lpn | grep "/dev/sd" | head -n 1)
    mmcblk=$(lsblk -o name -lpn | grep "/dev/mmcblk" | head -n 1)
    if [[ -b "$nvme" ]]; then
            install_device="$nvme"
            echo -e "NVME Device discovered!"
        elif [[ -b "$sata" ]]; then
            install_device="$sata"
            echo -e "SATA Device discovered!"
        elif [[ -b "$mmcblk" ]]; then
            install_device="$mmcblk"
            echo -e "EMMC Flash device discovered!"
        else
            echo -e "NO device discovered! Installation cannot continue."
            exit 1
    fi
    echo -e "\nInstalling to $install_device"
    echo -e "IP address is: $(hostname -I)"
    if ! coreos-installer install --ignition="$ignition_file" "$install_device"; then
        echo -e "ERROR: coreos-installer failed! System will NOT reboot." >&2
        exit 1
    else
        # Force the NEXT boot onto the installed disk so the machine cannot loop back into PXE/USB after reboot.
        set_efi_bootnext
        echo -e "Installation successful. Rebooting into installed system..."
    	/usr/bin/systemctl --no-block reboot
    fi
}

set_efi_bootnext(){
    if ! command -v efibootmgr >/dev/null 2>&1; then
        echo -e "efibootmgr not available (BIOS install?) - skipping BootNext."
        return 0
    fi
    local esp_uuid next_entry
    esp_uuid="$(blkid -s PARTUUID -o value /dev/disk/by-partlabel/EFI-SYSTEM 2>/dev/null || true)"
    if [[ -z "$esp_uuid" ]]; then
        echo -e "WARNING: could not resolve installed ESP PARTUUID; BootNext not set."
        return 0
    fi
    next_entry="$(efibootmgr -v 2>/dev/null | sed -n "s/^Boot\([0-9A-Fa-f]\{4\}\).*${esp_uuid}.*/\1/p" | head -n1)"
    if [[ -z "$next_entry" ]]; then
        echo -e "WARNING: no efibootmgr entry references ESP PARTUUID $esp_uuid."
        return 0
    fi
    if efibootmgr --bootnext "$next_entry" >/dev/null 2>&1; then
        echo -e "EFI BootNext set to Boot$next_entry (installed disk)."
    else
        echo -e "WARNING: failed to set EFI BootNext (firmware may boot the wrong device)."
    fi
    return 0
}

read_conf_partition(){
    echo "Mounting configuration partition, and searching for configuration file.."
    local conf_dir="/mnt/conf"
    local conf_label="${CONF_PART_LABEL:-conf}"
    local conf_dev confs conf_file
    # Locate the bootable/conf partition by filesystem label (fall back to a
    # label match over all block devices if `blkid -L` is unavailable).
    conf_dev="$(blkid -L "$conf_label" 2>/dev/null || true)"
    if [[ -z "$conf_dev" ]]; then
        conf_dev="$(lsblk -o name,label -lpn | awk -v l="$conf_label" '$2==l {print $1; exit}')"
    fi
    if [[ -z "$conf_dev" ]]; then
        echo -e "${RED}ERROR: No partition labelled '$conf_label' found.${NC}" >&2
        exit 1
    fi
    mkdir -p "$conf_dir"
    if ! mountpoint -q "$conf_dir"; then
        if ! mount -o ro "$conf_dev" "$conf_dir"; then
            echo -e "${RED}ERROR: Could not mount $conf_dev on $conf_dir.${NC}" >&2
            exit 1
        fi
    fi
    # Collect any .conf files; if several exist, select the most recently modified.
    mapfile -t confs < <(find "$conf_dir" -maxdepth 1 -name '*.conf' -type f 2>/dev/null)
    if [[ ${#confs[@]} -eq 0 ]]; then
        echo -e "${RED}ERROR: No .conf file found on $conf_dev.${NC}" >&2
        exit 1
    fi
    conf_file="$(printf '%s\n' "${confs[@]}" | xargs ls -t 2>/dev/null | head -n1)"
    echo "	Sourcing latest configuration file: $conf_file"
    source "$conf_file"
}

configure_ignition(){
	# Most of this formerly lived in install_wavelet_server.sh, and customizes the ignition files.
	local startDir; startDir="$(pwd)"
	scratchDir="$(mktemp -d)"
	# All customization happens inside the scratch dir so that relative `local:`
	# references resolve against --files-dir when butane transpiles below.
	# We record the starting dir so we can restore the CWD when done (deterministic).
	cd "$scratchDir" || { echo -e "${RED}ERROR: could not enter scratch dir $scratchDir.${NC}" >&2; exit 1; }
	# Copy the base templates and their supporting `local:` files from the conf partition.
	echo -e "\n	Copying base ignition files for customization.."
	local conf_files=(
		ignition_server.yml
		ignition_decoder.yml
		automated_client_installer.yml
		wavelet_install_packages.sh
		ca.crt
	)
	for f in "${conf_files[@]}"; do
		if [[ -f "/mnt/conf/$f" ]]; then
			cp "/mnt/conf/$f" "$scratchDir/$f"
		fi
	done
	cp "/mnt/conf/ignition_decoder.yml" "$scratchDir/decoder_custom.yml"
	# Use absolute paths so the deployment-mode functions are independent of CWD.
	# server_custom.yml is the working file that gets transpiled below.  It is
	# seeded from the ignition_server.yml template for STANDALONE/LAN, but
	# full_deployment replaces it wholesale with server_full.yml, so we seed it
	# per-mode below rather than unconditionally.
	INPUTFILES="$scratchDir/server_custom.yml $scratchDir/decoder_custom.yml"
    # Here, we properly configure the server_custom.yml ignition file with our conf settings.
	case $DEPLOYMENT_MODE in
		FULL)	full_deployment;;
		STANDALONE)	cp "/mnt/conf/ignition_server.yml" "$scratchDir/server_custom.yml"; standalone_deployment;;
		LAN) cp "/mnt/conf/ignition_server.yml" "$scratchDir/server_custom.yml"; lan_deployment;;
		*) echo "	ERR: No deployment mode specified!  Failing installation."; exit 0;;
	esac
	# Common ignition blocks shared between all variants
	init_users_yaml
	users=("wavelet-root" "wavelet")
	for user in "${users[@]}"; do
		if [[ $user == "wavelet-root" ]]; then
			mkpasswd --method=yescrypt "${ROOT_PASSWORD}" > "${user}.pw.secure"
		else
			mkpasswd --method=yescrypt "${WAVELET_PASSWORD}" > "${user}.pw.secure"
		fi
		ssh-keygen -t ed25519 -C "${user}@wavelet.allethrium" -N '' <<< $'\ny' >/dev/null 2>&1
		cp users_yaml "${user}_yaml.yml"
		generate_user_yaml "${user}"
#		echo -e "	Adding generated YAML block to ignition file for ${user}.."
		f2="$(<"${user}_yaml.yml")"
		input_files_arr=(${INPUTFILES})
		for file in "${input_files_arr[@]}"; do
			if [ -f "$file" ]; then
				awk -vf2="$f2" '/#ADD_USER_YAML_HERE/{print f2;print;next}1' "${file}" > tmp && mv tmp "${file}"
#				echo -e "	YAML block for ${user} added to ignition file ${file}.."
			else
				echo "	Warning: ${file} does not exist or is inaccessible!"
			fi
		done
	done
	# Generate wavelet.conf, the core system configuration file.  This is not the same as the installer conf file.
	# TODO - do we want to calculate the subnet here or just guess?
	cat > "$scratchDir/wavelet.conf" <<-EOF
		DOMAIN=${DOMAIN}
		SVR_IP=${SVR_IP:-192.168.1.32}
		SVR_GW=${SVR_GW:-192.168.1.1}
		SVR_DNS=${SVR_DNS:-${SVR_IP}}
		SVR_HOSTNAME=svr.${DOMAIN:-wavelet.allethrium}
		TIME_ZONE=${TIME_ZONE:-America/New_York}
		DEVELOPER_MODE=${DEVELOPER_MODE:-0}
		# Wifi settings for specific AP MAC (BSSID) and Name (SSID)
		ENABLE_WIFI=${ENABLE_WIFI:-0}
		WIFI_SSID=${WIFI_SSID:-}
		WIFI_BSSID=${WIFI_BSSID:-}
		WIFI_IPADDR=${WIFI_IP_ADDR:-}
		# If an external registry is available, we populate here.  Implies external HTTPD server on port 8080 also.
		DEPLOYMENT_REGISTRY=${DEPLOYMENT_REGISTRY}
		DEPLOYMENT_IP=${DEPLOYMENT_IP}
		# This refers to the server's registry.
		REGISTRY=${SVR_IP:-192.168.1.32}
		# Additional system build state flags
		UG_BUILD_TYPE=${UG_BUILD_TYPE:-release}
		UG_VERSION=${UG_VERSION:-1.10.8}
		# Bootc flag used by wavelet_install_packages.sh at first boot.
		# Must match the install-media FCOS stream (next/F45 = 1, stable/F44 = 0).
		USE_BOOTC=${USE_BOOTC:-1}
		UNATTENDED_INSTALL=${UNATTENDED_INSTALL:-0}
	EOF
	echo "	Generating wavelet_keys.csv.."
	resolvContent="nameserver ${SVR_IP}\\nnameserver ${SVR_GW}\\nnameserver 9.9.9.9"
	# Build WiFi entries only if WiFi mode is enabled
	wifiEntries=""
	if [[ "${ENABLE_WIFI:-0}" == "1" ]]; then
		echo "	Generating Wi-Fi entries.."
		wifiEntries="file,/var/home/wavelet-root/config/wifi_adminuser,0640,true,,,WIFI_ADMIN_USER=${WIFI_DEVICE_USER}\nWIFI_ADMIN_PW=${WIFI_DEVICE_PASSWORD}\nWIFI_IPADDR=${WIFI_IP_ADDR}"
	else
		echo "	Disabling Wi-Fi mode.."
	fi
	cat > "$scratchDir/wavelet_keys.csv" <<-EOF
		type,path,mode,overwrite,owner,group,content
		file,/etc/systemd/logind.conf.d/inhibit-suspend.conf,0644,,,,[Login]\nHandleLidSwitch=ignore
		file,/var/secrets/ipaadmpw.secure,0600,true,,,${DOMAIN_ADMIN_PASSWORD:-DomainAdminPasswordGoesHere}
		${wifiEntries}
		file,/etc/resolv.conf,0644,true,,,${resolvContent}
		file,/etc/hostname,0644,true,,,svr.${DOMAIN:-wavelet.allethrium}
		file,/etc/hosts,0664,true,,,127.0.0.1      localhost localhost.localdomain localhost4 localhost4.localdomain4\n::1            localhost localhost.localdomain localhost6 localhost6.localdomain6\n${SVR_IP}  svr.${DOMAIN:-wavelet.allethrium}  svr
		dir,/var/home/wavelet/.config,0755,,wavelet,wavelet,
		dir,/var/home/wavelet/.config/systemd,0755,,wavelet,wavelet,
		dir,/var/home/wavelet/.config/systemd/user,0755,,wavelet,wavelet,
		dir,/var/home/wavelet/.config/systemd/user/default.target.wants,0755,,wavelet,wavelet,
		dir,/var/home/wavelet/config,0755,,wavelet,wavelet,
		dir,/var/home/wavelet/etcd,0700,,wavelet,wavelet,
		dir,/var/home/wavelet/.ssh/secrets,0700,,wavelet,wavelet,
		dir,/var/containers/registry,0700,,wavelet,wavelet,
		dir,/var/home/wavelet/http,0755,,wavelet,wavelet,
		dir,/var/home/wavelet/http-php/html,0755,,wavelet,wavelet,
		dir,/var/home/wavelet/.local/share/containers/storage/volumes,0755,,wavelet,wavelet,
		dir,/var/home/wavelet/http-php/nginx,0755,,wavelet,wavelet,
		dir,/var/home/wavelet/http/ignition,0755,,wavelet,wavelet,
		dir,/var/home/wavelet-root/config,0755,,wavelet-root,wavelet-root,
		dir,/var/home/wavelet-root/.ssh/secrets,0700,,wavelet-root,wavelet-root,
		dir,/var/roothome/logs,0700,,wavelet-root,wavelet-root,
		dir,/var/lib/tftpboot,0755,,root,root,
		dir,/etc/etcd,0700,,root,root,
		dir,/etc/systemd/resolved.conf.d,0755,,root,root,
		dir,/etc/ssh/ssh_config.d,0755,,root,root,
		dir,/usr/local/backgrounds/sway,0755,,root,root,
		dir,/var/lib/systemd/linger/wavelet,0755,,root,root,
		dir,/var/lib/systemd/linger/wavelet-root,0755,,root,root,
	EOF
	# Customize launching kernel args, this will accelerate the bootup as NetworkManager-wait-online won't hang for 30+s
	subnet="${SUBNET:-255.255.255.0}"
	echo "	Applying kernel args: ip=${SVR_IP}::${SVR_GW}:${subnet}:svr.${DOMAIN:-wavelet.allethrium}::none"
	sed -i "s|ip=192.168.1.32::192.168.1.1:255.255.255.0::none|ip=${SVR_IP}::${SVR_GW}:${subnet}::none|g" ${INPUTFILES}
	sed -i "s|hostname=svr.wavelet.allethrium|hostname=svr.${DOMAIN:-wavelet.allethrium}|g" ${INPUTFILES}
	# Transpile ONLY the server template to ignition.  server_custom.yml is the
	# live config used for the next boot; decoder_custom.yml is referenced by it
	# as a `local:` file and inlined into /home/wavelet/config/decoder_custom.yml,
	# where the PXE framework transpiles it to decoder.ign later for clients.
	echo "	Transpiling server_custom.yml to ignition with butane.."
	butane --pretty --files-dir "$scratchDir" server_custom.yml --output "$scratchDir/server.ign" \
		|| { echo -e "${RED}ERROR: butane failed on server_custom.yml.${NC}" >&2; exit 1; }
	ignition_file="$scratchDir/server.ign"
	echo -e "\n${GREEN} ***Customization complete, ignition file generated at ${ignition_file}..*** \n${NC}"
	# Restore the original working directory so subsequent code is deterministic.
	cd "$startDir" || echo -e "${RED}WARNING: could not restore working directory $startDir.${NC}" >&2
}

# User setup
init_users_yaml() {
	# Ensure nothing adds TABS in the cat command below, YAML won't transpile correctly without indentation being entirely spaces.
	cat <<EOF > "users_yaml"
    - name: USERNAMEGOESHERE
      password_hash: PASSWORDGOESHERE
      groups:
        #- GROUPGOESHERE
      ssh_authorized_keys:
        - PUBKEYGOESHERE
      home_dir: /home/USERHOMEDIR
EOF
}

ca_data_yaml() {
	cat <<EOF > "ca_data_yaml"
ignition:
  security:
    tls:
      certificate_authorities:
        # This is only for the server deploying against a local httpd/registry.
        - local: ca.crt
          verification:
            hash: ${caHash}
EOF
	# We do not need hash verification again here because if it were bad, ignition would fail with the CA above.
	cat <<EOF > "ca_file_yaml"
    - path: /etc/docker/certs.d/${DEPLOYMENT_IP}:5000/ca.crt
      mode: 0755
      contents:
        local: ca.crt
EOF
}

generate_user_yaml(){
	local name; local password_hash; local ssh_authorized_keys
	local uid
	name=$1
	uid=""
	password_hash="$(cat "${name}.pw.secure")"
	ssh_authorized_keys="$(cat "${name}-ssh.pub")"
	user_yaml="${name}_yaml.yml"
	if [[ "${name}" = "wavelet-root" ]]; then
	# echo -e "\n	wavelet-root user, setting UID to 9337"
		uid="9337"
		group1="wheel"
		group2="sudo"
		sed -i "s|#- GROUPGOESHERE|- $group1\n        #- GROUPGOESHERE|" "${user_yaml}"
		sed -i "s|#- GROUPGOESHERE|- $group2\n        #- GROUPGOESHERE|" "${user_yaml}"
	elif [[ "${name}" = "wavelet" ]]; then
	# echo -e "\n	wavelet user, setting UID to 1337"
		uid="1337"
	elif [[ "${name}" = "wavelet-present" ]]; then
	# echo -e "\n	wavelet user, setting UID to 1337"
		uid="1338"
	else
		# reset uid
		uid=""
		return 1
	fi
	if [[ -n ${uid} ]]; then
		echo -e
		sed -i "s|USERNAMEGOESHERE|USERNAMEGOESHERE\n      uid: $uid|" "${user_yaml}"
	fi
	# We use a pipe instead of a / here, because the pubkeys and passwords hashes may contain a / and therefore escape the rest of the data.
	# echo -e " 	Working on user ${name}\n"
	sed -i "s|#ADD_USER_YAMLHERE|""|" "${user_yaml}"
	sed -i "s|PASSWORDGOESHERE|$password_hash|" "${user_yaml}"
	sed -i "s|PUBKEYGOESHERE|$ssh_authorized_keys|" "${user_yaml}"
	sed -i "s|USERNAMEGOESHERE|$name|" "${user_yaml}"
	sed -i "s|USERHOMEDIR|$name|" "${user_yaml}"
}


standalone_deployment(){
	# Standalone: install everything, reboot, then the server generates its
	# own config from scratch on first boot.  wavelet_keys.csv is already
	# generated (with its header) by configure_ignition, so nothing to add here.
	echo "	STANDALONE deployment mode selected."
}

lan_deployment(){
	# inject CA for LAN httpd/registry into server ignition.
	# The CA lives on the conf partition (as ca.crt) and was copied into the
	# scratch dir by configure_ignition; it is referenced by the `local:` args.
	if [[ -f "$scratchDir/ca.crt" ]]; then
		# Compute SHA256 hash of the CA certificate for the ignition verification block.
		caHash="sha256-$(sha256sum "$scratchDir/ca.crt" | cut -d' ' -f1)"
		# Replace placeholders in server ignition file for certificateAuthorities
		ca_data_yaml
    	ca_data="$(cat "$scratchDir/ca_data_yaml")"
    	awk -vca_block="$ca_data" '/# Comment_tag_CA/{print ca_block;next}1' \
    		"$scratchDir/server_custom.yml" > "$scratchDir/tmp" && mv "$scratchDir/tmp" "$scratchDir/server_custom.yml"
    	sed -i "s|https://DEPLOYMENT_SERVER/ca.crt|https://$DEPLOYMENT_IP:8080/ca.crt|g" "$scratchDir/server_custom.yml"
    	ca_file="$(cat "$scratchDir/ca_file_yaml")"
    	awk -vca_file="$ca_file" '/    # Deployment server CA goes here/{print ca_file;next}1' \
    		"$scratchDir/server_custom.yml" > "$scratchDir/tmp" && mv "$scratchDir/tmp" "$scratchDir/server_custom.yml"
		rm -f "$scratchDir/ca_data_yaml" "$scratchDir/ca_file_yaml"
	fi
	sed -i "s|https://github.com/Allethrium/wavelet/archive/refs/heads/master.tar.gz|https://${DEPLOYMENT_IP%%:*}:8443/master.tar.gz|g" $INPUTFILES
	# Set UltraGrid to local LAN server, which ought to have both builds if build_registry.sh worked as it should.
	sed -i "s|https://github.com/CESNET/UltraGrid/releases/download/v1.10.5/UltraGrid-1.10.5-x86_64.AppImage|https://${DEPLOYMENT_IP%%:*}:8443/UltraGrid-1.10.5-x86_64.AppImage|g" $INPUTFILES
}

full_deployment(){
    # Full (offline) deployment.  We are already running in the preboot/live
    # environment, so there is no ISO to customize - we just wire the offline
    # loader configuration into the ignition YAML and the normal
    # `coreos-installer install --ignition=` path below performs the install.
    # The server_full.yml template is the offline variant of ignition_server.yml.
    echo "	Generating full-mode ignition (offline loader wired in, small initramfs).."
    # Copy the full-mode template over the server template; its contents already
    # point at the offline tarball and CA rather than remote URLs.
    if [[ -f "/mnt/conf/server_full.yml" ]]; then
        cp "/mnt/conf/server_full.yml" "$scratchDir/server_custom.yml"
    else
        echo -e "${RED}	ERROR: /mnt/conf/server_full.yml not found; cannot build full-mode ignition.${NC}" >&2
        exit 1
    fi
    # The full-mode server YAML references the offline tarball; substitute the
    # tarball name from the conf if provided.
    local tarball="${FULL_TARBALL:-master.tar.gz}"
    sed -i "s|armelvil-working.tar.gz|$tarball|g" "$scratchDir/server_custom.yml"
    # EFI BootNext is handled by set_efi_bootnext() in install_operatingSystem
    # after a successful install, so no post-install hook is needed here.
}

test_tools(){
	# Small function to test for necessary tools
	# Shove this into an array
	toolsArray=(
		sed
		mount
		butane
		tar
		gzip
		mkpasswd
		ssh-keygen
		coreos-installer
	)
    for i in "${toolsArray[@]}"; do
        if command -v "$i" >/dev/null 2>&1; then
            echo "	Tool $i available!"
        else
            echo "	ERROR:  Critical tool, $i, is unavailable!" >&2
            exit 1
        fi
    done
	echo "	Tool tests passed, continuing boot."
	echo -e "\033[33m*****\tTOOL TESTS PASSED, CONTINUING INSTALLATION	*****\033[0m" | systemd-cat -p 5 -t automated_coreos_deployment.sh
}

main(){
    # Ensure tools are available during the initial configuration process
    test_tools
    # Acquire the configuration file from the conf partition, and configure ignition.
    read_conf_partition
    configure_ignition
    # Finally, install to the detected permanent storage on this system:
    install_operatingSystem
}


####
#
# Main
#
####


for i in "$@"; do
		case "$i" in
			client)
				# For a normal client spinup, we are called with "client" arg, and run here.
				# The compiled decoder.ign was already fetched by automated_client_installer.yml
				# (from the server's ignition dir) to /home/decoder.ign during this live boot.
				ignition_file="/home/decoder.ign"
				install_operatingSystem
				;;
			*)
				main
				;;
	esac
done