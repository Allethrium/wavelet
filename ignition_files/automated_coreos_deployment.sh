#!/usr/bin/bash

# This script is a modification of that provided on:
# https://dustymabe.com/2020/04/04/automating-a-custom-install-of-fedora-coreos/
# It attempts to detect common block devices and configure the initial automation live installer for that device.

# 11/2026 Update - we now handle the ignition customization pass here

install_operatingSystem() {
    # Dynamically detect which device to install to.
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
        # Force the NEXT boot onto the installed disk so the machine cannot loop
        # back into PXE/USB after reboot.
        if ! set_efi_bootnext; then
            echo -e "${RED}
	######################################################
	#  INSTALL SUCCEEDED, BUT EFI BOOT HANDOFF FAILED.  #
	#  Power off, REMOVE THE USB MEDIA, then boot the   #
	#  installed disk (or select it from the boot menu). #
	######################################################${NC}" >&2
            # Never sleep blindly for minutes: at an unattended console that just
            # looks like a hang.  Short abortable window, then reboot regardless -
            # the install itself succeeded either way.
            echo -e "Rebooting in 15s (Ctrl-C drops you back to inspect the system)..." >&2
            sleep 15
        else
            echo -e "Installation successful. Rebooting into installed system..."
            sleep 5
        fi
    	/usr/bin/systemctl --no-block reboot
    fi
}

set_efi_bootnext(){
    # Attempt handing the firmware off to the freshly installed disk.
    if ! command -v efibootmgr >/dev/null 2>&1; then
        echo -e "efibootmgr not available - skipping BootNext."
        return 0
    fi
    # coreos-installer has only just written the partition table; the by-partlabel
    # symlink is created asynchronously by udev and may not exist yet.
    udevadm settle --timeout=30 >/dev/null 2>&1
    partprobe "$install_device" >/dev/null 2>&1 || true
    local esp_uuid esp_part
    esp_part="$(lsblk -no name,partlabel -lp "$install_device" 2>/dev/null | awk '$2=="EFI-SYSTEM"{print $1; exit}')"
    [[ -n "$esp_part" ]] && esp_uuid="$(blkid -s PARTUUID -o value "$esp_part" 2>/dev/null || true)"
    if [[ -z "$esp_uuid" ]]; then
        echo -e "${RED}	ERROR: could not resolve the installed ESP PARTUUID on $install_device.
	BootNext not set; remove the USB media before next boot attempt.${NC}" >&2
        lsblk -o name,label,partlabel,partuuid "$install_device" >&2 || true
        return 1
    fi
    echo -e "	Installed ESP: $esp_part (PARTUUID $esp_uuid)"
    # Both textual representations the firmware may have written into NVRAM.
    local uuid_upper="${esp_uuid^^}"
    local swapped=""
    swapped="$(efi_mixed_endian_guid "$uuid_upper")"
    local efv next_entry
    efv="$(efibootmgr -v 2>/dev/null)"
    if [[ -n "$swapped" ]]; then
        next_entry="$(printf '%s\n' "$efv" | grep -i -m1 -e "$uuid_upper" -e "$swapped" | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\).*/\1/p')"
    else
        next_entry="$(printf '%s\n' "$efv" | grep -i -m1 -e "$uuid_upper" | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\).*/\1/p')"
    fi
    local bootorder new_order="$next_entry" entry
    bootorder="$(efibootmgr 2>/dev/null | sed -n 's/^BootOrder: //p')"
    for entry in ${bootorder//,/ }; do
        [[ "${entry^^}" == "${next_entry^^}" ]] && continue
        new_order="$new_order,$entry"
    done
    local ok=0
    if efibootmgr --bootnext "$next_entry" >/dev/null 2>&1; then
        echo -e "	EFI BootNext set to Boot$next_entry (installed disk)."
        ok=1
    else
        echo -e "${RED}	WARNING: failed to set EFI BootNext (firmware may boot the wrong device).${NC}" >&2
    fi
    if [[ -n "$bootorder" ]] && efibootmgr --bootorder "$new_order" >/dev/null 2>&1; then
        echo -e "	EFI BootOrder now: $new_order"
        ok=1
    else
        echo -e "${RED}	WARNING: could not persist BootOrder; with the USB left in place the
	next reboot may return to the installer.${NC}" >&2
    fi
    [[ $ok -eq 1 ]] && return 0
    return 1
}

efi_mixed_endian_guid(){
    local uuid="$1" g1 g2 g3 g4 g5
    IFS='-' read -r g1 g2 g3 g4 g5 <<< "$uuid"
    [[ -z "$g5" ]] && return 1
    local sw1 sw2 sw3
    sw1="$(printf '%s' "$g1" | sed -E 's/(..)(..)(..)(..)/\4\3\2\1/')"
    sw2="$(printf '%s' "$g2" | sed -E 's/(..)(..)/\2\1/')"
    sw3="$(printf '%s' "$g3" | sed -E 's/(..)(..)/\2\1/')"
    printf '%s-%s-%s-%s-%s\n' "$sw1" "$sw2" "$sw3" "$g4" "$g5"
}

read_conf_partition(){
    echo "Mounting configuration partition, and searching for configuration file.."
    local conf_dir="/mnt/conf"
    local conf_label="${CONF_PART_LABEL:-CONF}"
    local conf_dev confs conf_file
    # Locate the bootable/conf partition by filesystem label (fall back to a
    # label match over all block devices if `blkid -L` is unavailable).
    conf_dev="$(blkid -L "$conf_label" 2>/dev/null || true)"
    if [[ -z "$conf_dev" ]]; then
        conf_dev="$(lsblk -o name,label -lpn | awk -v l="$conf_label" '$2==l {print $1; exit}')"
    fi
    if [[ -z "$conf_dev" ]]; then
        echo -e "${RED}	ERROR: No partition labelled '$conf_label' found.${NC}" >&2
        exit 1
    fi
    mkdir -p "$conf_dir"
    if ! mountpoint -q "$conf_dir"; then
        if ! mount -o rw "$conf_dev" "$conf_dir"; then
            echo -e "${RED}	ERROR: Could not mount $conf_dev on $conf_dir.${NC}" >&2
            exit 1
        fi
    fi
    echo "	Mount located, contents: "
    ls -laht /mnt/conf
    # set logging on the configuration dir
    # Collect any .conf files; if several exist, select the most recently modified.
    mapfile -t confs < <(find "$conf_dir" -maxdepth 1 -name '*.conf' -type f 2>/dev/null)
    if [[ ${#confs[@]} -eq 0 ]]; then
        echo -e "${RED}	ERROR: No .conf file found on $conf_dev.${NC}" >&2
        exit 1
    fi
    conf_file="$(printf '%s\n' "${confs[@]}" | xargs ls -t 2>/dev/null | head -n1)"
    echo "	Sourcing latest configuration file: $conf_file"
    source "$conf_file"
    if [[ "$completeTools" == 1 ]]; then
    	# We have missing tools in our env
    	for t in "${missingToolsArray[@]}"; do
    		if command -v "/mnt/conf/bin/$t" >/dev/null 2>&1; then
				echo "	Tool $t available"
				[ -x "/mnt/conf/bin/$t" ] && ln -sf "/mnt/conf/bin/$t" "/usr/local/bin/$t"
			else
				echo "	Tools $i is still missing or, unexecutable.  Check install environment for that tool."
			fi
    	done
    fi
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
		automated_client_installer.yml
		ignition_server.yml
		ignition_decoder.yml
		ca.crt
	)
	local bin_files=(
    	bin/wavelet_install_packages.sh
   		bin/automated_coreos_deployment.sh
	)
	for f in "${conf_files[@]}"; do
		if [[ -f "/mnt/conf/$f" ]]; then
			cp "/mnt/conf/$f" "$scratchDir/$f"
		fi
	done
	for f in "${bin_files[@]}"; do
		if [[ -f "/mnt/conf/$f" ]]; then
			cp "/mnt/conf/$f" "$scratchDir/${f#bin/*}"
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
	if [[ -z "$ROOT_PASSWORD" ]]; then
		echo "${RED}	ERROR: wavelet-root password defaulting to 'testlab123' - please ensure this is changed!"
		ROOT_PASSWORD="testlab123"
	fi
	if [[ -z "$WAVELET_PASSWORD" ]]; then
		echo "${RED}	ERROR: wavelet password defaulting to 'testlab123' - please ensure this is changed!"
		WAVELET_PASSWORD="testlab123"
	fi
	for user in "${users[@]}"; do
		if [[ $user == "wavelet-root" ]]; then
			/mnt/conf/bin/mkpasswd --method=yescrypt "${ROOT_PASSWORD}" > "${user}.pw.secure" || \
				{ echo -e "${RED}ERROR: mkpasswd failed for ${user} (empty password?).${NC}" >&2; exit 1; }
		else
			/mnt/conf/bin/mkpasswd --method=yescrypt "${WAVELET_PASSWORD}" > "${user}.pw.secure" || \
				{ echo -e "${RED}ERROR: mkpasswd failed for ${user} (empty password?).${NC}" >&2; exit 1; }
		fi
		ssh-keygen -t ed25519 -C "${user}@wavelet.allethrium" -N '' <<< $'\ny' >/dev/null 2>&1
		cp users_yaml "${user}_yaml.yml"
		if generate_user_yaml "${user}"; then
			echo "User YAML block generated."
		else
			echo "${RED}	ERR:  Could not generate valid YAML for user $user!"
			exit 1
		fi
		input_files_arr=(${INPUTFILES})
		for file in "${input_files_arr[@]}"; do
			[ -f "$file" ] || { echo "Warning: $file missing"; continue; }
			awk -v ins="${user}_yaml.yml" '/#ADD_USER_YAML_HERE/{while ((getline l < ins) > 0) print l; close(ins); print; next}1' \
				"${file}" > tmp && mv tmp "${file}"
			grep -q "name: ${user}" "${file}" || {
				echo -e "${RED}ERROR: failed to inject user '${user}' into ${file}.${NC}" >&2
				exit 1
			}
		done
	done
	# All users injected - drop the now-redundant marker so the YAML stays clean.
	for file in ${INPUTFILES}; do
		[ -f "$file" ] && sed -i "/#ADD_USER_YAML_HERE/d" "$file"
	done
	# Generate wavelet.conf, the core system configuration file.  This is not the same as the installer conf file.
	# TODO - do we want to calculate the subnet here or just guess?
    # Generate the /etc/wavelet.conf file, this is injected into ignition in all modes.
    echo "	Generating wavelet.conf for server.."
	cat > "$scratchDir/wavelet.conf" <<-EOF
		DOMAIN=$DOMAIN
		SVR_IP=$SVR_IP
		SVR_GW=$SVR_GW
		# DNS is updated during install_hardening.sh, where the domain controller is spun up.
		SVR_DNS=${SVR_DNS:-$SVR_GW}
		SVR_HOSTNAME=svr.$DOMAIN
		TIME_ZONE=America/New_York
		DEVELOPER_MODE=$DEVELOPER_MODE
		# Wifi settings for specific AP MAC (BSSID) and Name (SSID)
		ENABLE_WIFI=$ENABLE_WIFI
		WIFI_SSID=$WIFI_SSID
		WIFI_BSSID=$WIFI_BSSID
		WIFI_IPADDR=$WIFI_IP_ADDR
		# If an external registry is available, populate here.  Implies external HTTPD server on port 8080 also.
		DEPLOYMENT_REGISTRY=$DEPLOYMENT_REGISTRY
		DEPLOYMENT_IP=$DEPLOYMENT_IP
		# This refers to the server's registry.
		REGISTRY=$SVR_IP
		# Additional system build state flags
		UG_BUILD_TYPE=$UG_BUILD_TYPE
		UG_VERSION=${UG_VERSION:-1.10.0}
		# Bootc flag used by wavelet_install_packages.sh at first boot.
		# Must match the install-media FCOS stream (next/F45 = 1, stable/F44 = 0).
		USE_BOOTC=$USE_BOOTC
		UNATTENDED_INSTALL=0
		DEPLOYMENT_MODE=$DEPLOYMENT_MODE
	EOF
	echo "	Generating wavelet_keys.csv.."
	resolvContent="nameserver ${SVR_IP}\\nameserver ${SVR_GW}\\nameserver 9.9.9.9"
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
	sed -i "s|ip=192.168.1.32::192.168.1.1:255.255.255.0::none|ip=${SVR_IP}::${SVR_GW}:${subnet}::none rd.net.timeout.carrier=3000 rd.net.timeout.ifup=5|g" ${INPUTFILES}
	sed -i "s|hostname=svr.wavelet.allethrium|hostname=svr.${DOMAIN:-wavelet.allethrium}|g" ${INPUTFILES}
	# Transpile ONLY the server template to ignition.
	echo "	Transpiling server_custom.yml to ignition with butane.."
	/mnt/conf/bin/butane --pretty --files-dir "$scratchDir" server_custom.yml --output "$scratchDir/server.ign" \
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
	sed -i "s|#ADD_USER_YAML_HERE|""|" "${user_yaml}"
	sed -i "s|PASSWORDGOESHERE|$password_hash|" "${user_yaml}"
	sed -i "s|PUBKEYGOESHERE|$ssh_authorized_keys|" "${user_yaml}"
	sed -i "s|USERNAMEGOESHERE|$name|" "${user_yaml}"
	sed -i "s|USERHOMEDIR|$name|" "${user_yaml}"
}


standalone_deployment(){
	# Standalone: the server will download everything from the internet in the next stage
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
	# Github names the .tar as the branch name, however locally or on LAN deployment, we always use wavelet_files.tar.gz
	sed -i "s|https://github.com/Allethrium/wavelet/archive/refs/heads/master.tar.gz|https://${DEPLOYMENT_IP%%:*}:8443/wavelet_files.tar.gz|g" $INPUTFILES
	# Set UltraGrid to local LAN server, which ought to have both builds if build_registry.sh worked as it should.
	sed -i "s|https://github.com/CESNET/UltraGrid/releases/download/v1.10.5/UltraGrid-1.10.5-x86_64.AppImage|https://${DEPLOYMENT_IP%%:*}:8443/UltraGrid-continuous-x86_64.AppImage|g" $INPUTFILES
}

full_deployment(){
    # Full (offline) deployment.  We are already running in the preboot/live
    # environment, so there is no ISO to customize - we just wire the offline
    # loader configuration into the ignition YAML and the normal
    # `coreos-installer install --ignition=` path below performs the install.
    # The server_full.yml template is the offline variant of ignition_server.yml.
    echo "	Generating full-mode ignition.."
    # Copy the full-mode template over the server template; its contents already
    # point at the offline tarball and CA rather than remote URLs.
    if [[ -f "/mnt/conf/server_full.yml" ]]; then
        cp "/mnt/conf/server_full.yml" "$scratchDir/server_custom.yml"
    else
        echo -e "${RED}	ERROR: /mnt/conf/server_full.yml not found; cannot build full-mode ignition.${NC}" >&2
        exit 1
    fi
    # DEPLOYMENT_REGISTRY must be set to the local server as in standalone generation
    # this is because the OCI archives are all copied in from USB.
    DEPLOYMENT_REGISTRY="svr.$DOMAIN"
}

test_tools(){
	# Small function to test for necessary tools
	completeTools=1
	missingToolsArray=()
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
            echo "	Tool $i available"
        else
            echo "	ERROR:  Critical tool, $i, is unavailable!" >&2
            completeTools=0
            missingToolsArray+=("$i")
        fi
    done
	echo "	Tool tests completed, missing tools will be appended from conf partition, continuing boot."
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


RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"


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