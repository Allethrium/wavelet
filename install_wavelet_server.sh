#!/bin/bash

# This script bootstraps your initial wavelet server based upon input variables.
# Many functions rely on Wavelet running its own DHCP and domain server, it can be modified to work in a larger network
# This would require work to support a multitude of different environments, and is out of the current scope of the project.

RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"

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
	name=$1
	password_hash="$(cat "${user}.pw.secure")"
	ssh_authorized_keys="$(cat "${name}-ssh.pub")"
	user_yaml="${name}_yaml.yml"
	if [[ "${name}" = "wavelet-root" ]]; then
#		echo -e "\n	wavelet-root user, setting UID to 9337"
		uid="9337"
		group1="wheel"
		group2="sudo"
		sed -i "s|#- GROUPGOESHERE|- $group1\n        #- GROUPGOESHERE|" "${user_yaml}"
		sed -i "s|#- GROUPGOESHERE|- $group2\n        #- GROUPGOESHERE|" "${user_yaml}"
	elif [[ "${name}" = "wavelet" ]]; then
#		echo -e "\n	wavelet user, setting UID to 1337"
		uid="1337"
	elif [[ "${name}" = "wavelet-present" ]]; then
#		echo -e "\n	wavelet user, setting UID to 1337"
		uid="1336"
	else
		echo -e "			User ID not preset, system will assign them."
	fi
	if [[ -n ${uid} ]]; then
		echo -e
		sed -i "s|USERNAMEGOESHERE|USERNAMEGOESHERE\n      uid: $uid|" "${user_yaml}"
	fi
	# We use a pipe instead of a / here, because the pubkeys and passwords hashes may contain a / and therefore escape the rest of the data.
#	echo -e " 	Working on user ${name}\n"
	sed -i "s|#ADD_USER_YAMLHERE|""|" "${user_yaml}"
	sed -i "s|PASSWORDGOESHERE|$password_hash|" "${user_yaml}"
	sed -i "s|PUBKEYGOESHERE|$ssh_authorized_keys|" "${user_yaml}"
	sed -i "s|USERNAMEGOESHERE|$name|" "${user_yaml}"
	sed -i "s|USERHOMEDIR|$name|" "${user_yaml}"
}

customization(){
	echo -e "  \n	Generating ignition files with appropriate settings.."
	INPUTFILES="server_custom.yml decoder_custom.yml"
	DOMAIN_ADMIN_PASSWORD="DomainAdminPasswordGoesHere"
	serverHostName="svr.${domain:-wavelet.allethrium}"
	if [[ "$developerMode" -eq "1" ]]; then
		# Direct ignition sed
		echo -e "${RED}	Injecting dev branch into files..${NC}"
		repl="armelvil-working.tar.gz"
		sed -i "s|master.tar.gz|${repl}|g" ${INPUTFILES}
	fi

	if [[ "$dev_flag" == "DEV" ]]; then
		# Direct ignition sed
		echo -e "${RED}	Targeting UltraGrid continuous build.${NC}"
		if [[ "$registry" == "$svr_ip" ]]; then
            echo "	Standalone deployment selected.."
	        if [[ "$patchMode" == "ON" ]]; then
	            # update this properly
	            echo "	Pulling UG build artefact from branch repo https://github.com/armelvil/UltraGrid"
                sed -i "s|\/download\/v[^ ]*|\/download\/continuous\/UltraGrid-continuous-x86_64.AppImage|g" ${INPUTFILES}
            else
                echo "	Pulling UG build artefact from upstream https://github.com/CESNET/UltraGrid"
	            sed -i "s|\/download\/v[^ ]*|\/download\/continuous\/UltraGrid-continuous-x86_64.AppImage|g" ${INPUTFILES}
            fi
		else
            echo "	LAN deployment selected.."
			sed -i "s|UltraGrid-1.10.5-x86_64.AppImage|UltraGrid-continuous-x86_64.AppImage|g" ${INPUTFILES}
			# Add a check here against the web UltraGrid continuous branch, print download/update message if it's out of date!
			echo -e "\n	${GREEN}Please ensure this file is kept updated!${NC}"
        fi
	else
		echo -e "\n	${GREEN}Tracking UltraGrid release build.\n${NC}"
		releaseVer="1.10.6"
	fi
	# Set default values if none
	svr_ip="${svr_ip:-192.168.1.32}"
	gateway="${gateway:-192.168.1.1}"
	subnet="${subnet:-255.255.255.0}"
	resolvContent="nameserver ${svr_ip}\\nnameserver ${gateway}\\nnameserver 9.9.9.9"
	printf "	Isolation mode: Wavelet provides DHCP/DNS.\n"

	# wavelet.conf contains configuration data for the server in one declarative file, in one place.
	# It should not contain passwords or privileged data, as it resides in /etc/wavelet.conf with 644 perms.
	echo "	Generating wavelet.conf..."
	cat > ./ignition_files/wavelet.conf <<-EOF
DOMAIN=${domain}
SVR_IP=${svr_ip:-192.168.1.32}
SVR_GW=${gateway:-192.168.1.1}
# DNS is updated during install_hardening.sh, where the domain controller is spun up.
SVR_DNS=${svr_dns:-${svr_ip}}
SVR_HOSTNAME=${serverHostName}
TIME_ZONE=${timeZone:-America/New_York}
DEVELOPER_MODE=${developerMode:-0}
# Wifi settings for specific AP MAC (BSSID) and Name (SSID)
ENABLE_WIFI=${enableWifi:-0}
WIFI_SSID=${wifi_ssid:-}
WIFI_BSSID=${wifi_bssid:-}
WIFI_IPADDR=${WIFI_IP_ADDR:-}
# If an external registry is available, we populate here.  Implies external HTTPD server on port 8080 also.
DEPLOYMENT_REGISTRY=${DEPLOYMENT_REGISTRY}
DEPLOYMENT_IP=${DEPLOYMENT_IP}
# This refers to the server's registry.
REGISTRY=${svr_ip:-192.168.1.32}
# Additional system build state flags
UG_BUILD_TYPE=${dev_flag:-release}
# Bootc flag used by wavelet_install_packages.sh at first boot.
# Must match the install-media FCOS stream (next/F45 = 1, stable/F44 = 0).
USE_BOOTC=${USE_BOOTC:-0}
UNATTENDED_INSTALL=${UNATTENDED_INSTALL:-0}
EOF

	echo "	Generating wavelet_keys.csv.."
	# Build WiFi entries only if WiFi mode is enabled
	wifiEntries=""
	if [[ "$enableWifi" == "1" ]]; then
		echo "	Generating Wi-Fi entries.."
		wifiEntries="file,/var/home/wavelet-root/config/wifi_adminuser,0640,true,,,WIFI_ADMIN_USER=${wifi_deviceUser}\nWIFI_ADMIN_PW=${wifi_devicePassword}\nWIFI_IPADDR=${wifi_ipAddr}"
	else
		echo "	Disabling Wi-Fi mode.."
	fi
cat > ./ignition_files/wavelet_keys.csv <<-EOF
	type,path,mode,overwrite,owner,group,content
	file,/etc/systemd/logind.conf.d/inhibit-suspend.conf,0644,,,,[Login]\nHandleLidSwitch=ignore
	file,/var/secrets/ipaadmpw.secure,0600,true,,,${DOMAIN_ADMIN_PASSWORD:-DomainAdminPasswordGoesHere}
	${wifiEntries}
	file,/etc/resolv.conf,0644,true,,,${resolvContent}
	file,/etc/hostname,0644,true,,,${serverHostName}
	file,/etc/hosts,0664,true,,,127.0.0.1      localhost localhost.localdomain localhost4 localhost4.localdomain4\n::1            localhost localhost.localdomain localhost6 localhost6.localdomain6\n${svr_ip}  ${serverHostName}  ${serverHostName%%.*}
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
	echo "	Applying kernel args: ip=${svr_ip}::${gateway}:${subnet}:${serverHostName}::none"
	sed -i "s|ip=192.168.1.32::192.168.1.1:255.255.255.0::none|ip=${svr_ip}::${gateway}:${subnet}::none|g" ${INPUTFILES}
	sed -i "s|hostname=svr.wavelet.allethriudm|hostname=${serverHostName}|g" ${INPUTFILES}
	mkdir -p var
	for file in ${INPUTFILES}; do
	  cat $file > var/generated_$file
	done
	echo -e "\n${GREEN} ***Customization complete, moving to injecting configurations to CoreOS images for initial installation..*** \n${NC}"
}

automatic_setup() {
	if [[ -z ${PASSWORD} ]]; then
		echo "Automatic setup requires at minimum a password. WiFi parameters are optional; use --enablewifi to configure wireless later."
		print_help
	fi
	INPUTFILES="server_custom.yml decoder_custom.yml"
	init_users_yaml
	# wavelet-root has sudo and handles system management tasks out of the root account (root, shell)
	# wavelet handles userspace tasks which do not require root (shell)
	# TODO - implement no-password low-privilege presentation account
	# wavelet-present is the logged-on seat that provides a video output in the production system (no shell)
	users=("wavelet-root" "wavelet" "wavelet-present")
	for user in "${users[@]}"; do
		mkpasswd --method=yescrypt "${PASSWORD}" > "${user}.pw.secure"
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

	# Report WiFi mode status to the user
	if [[ "${enableWifi}" == "1" ]]; then
		echo -e "${GREEN}	WiFi mode ENABLED. Wireless configuration will be written to ignition files.${NC}"
	else
		echo -e "${RED}	WiFi mode DISABLED. The system will use wired networking only.${NC}"
	fi

  customization
}

print_help(){
	echo -e "Initial wavelet install help prompts:"
	echo -e "Developer Mode: -d, --dev\nPulls from development branch on git."
	echo -e "-ugd=, --ugdev, --ugcontinuous=\nTargets the continuous build of UltraGrid for newer and possibly less stable features."
	echo -e "-p=, --pass=,--password=\nSets the wavelet-root password"
	echo -e "--enablewifi\nEnable WiFi mode (required before using any -ws, -wb, -wip, -wp, -wap, -wau options)"
	echo -e "-ws=, --wifissid=\nSets the preconfigured WiFi SSID (requires --enablewifi)"
	echo -e "-wb=, --wifibssid=\nSets the preconfigured WiFi BSSID (WiFi Access Point's MAC address) (requires --enablewifi)"
	echo -e "-apip=, --wifiapip=\nSets the preconfigured WiFi IP (WiFi Access Point's IP address) (requires --enablewifi)"
	echo -e "-wp=, --wifipass=\nSets the preconfigured WiFi PSK for use in WPA2/WPA networks.  Legacy argument. (requires --enablewifi)"
	echo -e "-4=, --ip4subnet=\nDefines the target IP4 subnet in CIDR notation (I.E 192.168.0.0/24)"
	echo -e "-6=, --ip6subnet=\nDefines the target IP6 subnet in CIDR notation (I.E 2001:db8:1:2::/64)"
	echo -e "-ip=, --serverip=\nDefines the server static IP4 address (I.E 192.168.0.2)"	
	echo -e "-g=, --servergateway=\nDefines the server static IP4 gateway (I.E 192.168.0.1)"	
	echo -e "-dns=, --serverdns=\nDefines the server DNS forwarder (I.E 192.168.0.53)"
	echo -e "-c=, --config=\nDefines a configuration file instead of commandline parameters (see wavelet_example.conf)"
	exit 0
}

validate_ip_port(){
	# The registry is the IP address ONLY.
	local input="$1"
	local ip_part="${input%%:*}"
	local registry_port="$ip_part:5000"
	# Check for exactly one colon
	if ! ping -q -c 3 $ip_part > /dev/null; then
  		echo "		Issue pinging container registry! Aborting!"
  		exit 1
	fi
	if curl -sk -s https://$registry_port/v2 > /dev/null; then
		echo -e "${GREEN}	Registry running and responding to curl!${NC}"
		registry="$ip_part"
	else
		echo -e "${RED}	Registry not responding, please verify your settings..${NC}"
		exit 1
	fi
}

get_publicinterface(){
	# Tries to get the active network interface, may sometimes get it wrong.
	iface_route="$(ip -4 route show default | sort -nk1,1 | head -n1)"
	if [[ -z "$iface_route" ]]; then
		echo "	No default IPv4 route found. Cannot determine public interface."
		exit 1
	fi
	iface=$(echo "$iface_route" | awk '{print $5}')
	ip="$(nmcli -t -f IP4.ADDRESS dev show $iface | awk -F: '{print $2}' |cut -d'/' -f1 )"
	echo "	Main interface IP Address: $ip"
}

download_wavelet_git(){
	# Runs only if we are using LAN Deployment
	if [[ "${developerMode}" -eq "1" ]]; then
    	GH_BRANCH="armelvil-working"
	else
    	GH_BRANCH="master"
	fi

	# Fetch the commit SHA for the branch from GitHub API
	local branchInfo
	branchInfo=$(curl -s -L --max-time 30 "https://api.github.com/repos/Allethrium/wavelet/branches/$GH_BRANCH")
	local commitSha
	commitSha=$(echo "$branchInfo" | grep -oP '"sha":\s*"\K[0-9a-f]{40}' | head -1)
	if [[ -z "$commitSha" ]]; then
		echo "	Error: Could not fetch commit SHA for branch $GH_BRANCH from GitHub API!"
	fi
	echo "	Branch $GH_BRANCH commit SHA: $commitSha"

	# Check if we have a cached tarball with matching SHA
	local cached_tarball="$HOME/.config/var/www/${GH_BRANCH}_cached.tar.gz"
	local cached_sha_file="$HOME/.config/var/www/${GH_BRANCH}_sha256.txt"
	if [[ -f "$cached_tarball" ]] && [[ -f "$cached_sha_file" ]]; then
		cached_sha=$(cat "$cached_sha_file")
		if [[ "$cached_sha" == "$commitSha" ]]; then
			# Validate the cached tarball is a valid tar.gz archive
			if tar -tzf "$cached_tarball" > /dev/null 2>&1; then
				echo "	Using cached wavelet tarball with matching commit SHA: $commitSha"
				cp "$cached_tarball" "$HOME/.config/var/www/$GH_BRANCH.tar.gz"
				echo "	Acquired wavelet tarball from cache, proceeding.."
				return 0
			else
				echo "	Warning: Cached tarball is not a valid tar.gz archive, re-downloading..."
			fi
		fi
	fi

	# Download from GitHub
	local download_url="https://github.com/Allethrium/wavelet/archive/refs/heads/$GH_BRANCH.tar.gz"
	if curl -s -f -L -o "$HOME/.config/var/www/$GH_BRANCH.tar.gz" "$download_url"; then
		echo "	Acquired wavelet tarball, proceeding.."
	else
		echo "	Error downloading wavelet tarball!  aborting!"
		echo "	Please check this user's write permissions to ~/.config/var/www"
		exit 1
	fi

	# Validate the downloaded file is a valid tar.gz archive
	if ! tar -tzf "$HOME/.config/var/www/$GH_BRANCH.tar.gz" > /dev/null 2>&1; then
		echo "	Error: Downloaded file is not a valid tar.gz archive!"
		echo "	File size: $(wc -c < "$HOME/.config/var/www/$GH_BRANCH.tar.gz") bytes"
		echo "	First 200 bytes:"
		head -c 200 "$HOME/.config/var/www/$GH_BRANCH.tar.gz" | cat -v
		rm -f "$HOME/.config/var/www/$GH_BRANCH.tar.gz"
		exit 1
	fi

	# Compute SHA256 of the downloaded tarball
	local tarballSha256
	tarballSha256=$(sha256sum "$HOME/.config/var/www/$GH_BRANCH.tar.gz" | cut -d' ' -f1)
	echo "	Tarball SHA256: $tarballSha256"

	# Cache the tarball and its commit SHA
	cp "$HOME/.config/var/www/$GH_BRANCH.tar.gz" "$cached_tarball"
	echo "$commitSha" > "$cached_sha_file"
}

check_and_update_ultragrid_continuous(){
	# Checks the UltraGrid continuous build checksum against a cached local copy.
	# Downloads and overwrites the local file if the local checksum differs or file is missing.
	local ug_release_repo="${UG_RELEASE_REPO:-armelvil/UltraGrid}"
	local ug_download_url="https://github.com/${ug_release_repo}/releases/download/continuous/UltraGrid-continuous-x86_64.AppImage"
	local ug_cached_checksum="/var/home/wavelet/config/.ultragrid_continuous.sha256"
	local ug_local_file="${WAVELET_HTTP_DIR:-/home/wavelet/http}/UltraGrid-continuous-x86_64.AppImage"
	local local_sha256=""

	# Check if the local file exists and compute its checksum
	if [[ ! -f "$ug_local_file" ]]; then
		echo -e "	${GREEN}	UltraGrid continuous build not found locally. Downloading...${NC}"
		mkdir -p "$(dirname "$ug_local_file")"
		curl -sL --max-time 120 -o "$ug_local_file" "$ug_download_url"
		if [[ $? -ne 0 ]]; then
			echo -e "	${RED}	Error downloading UltraGrid continuous build! Aborting.${NC}"
			exit 1
		fi
		chmod +x "$ug_local_file"
		local_sha256=$(sha256sum "$ug_local_file" | cut -d' ' -f1)
		echo "$local_sha256" > "$ug_cached_checksum"
		echo -e "	${GREEN}	UltraGrid continuous build downloaded and cached with checksum: ${local_sha256}${NC}"
		return 0
	fi

	# Compute local checksum and compare with cached checksum
	local_sha256=$(sha256sum "$ug_local_file" | cut -d' ' -f1)

	if [[ -f "$ug_cached_checksum" ]]; then
		cached_sha256=$(cat "$ug_cached_checksum")
		echo -e "	Local checksum:  ${local_sha256}"
		echo -e "	Cached checksum: ${cached_sha256}"
		if [[ "$local_sha256" == "$cached_sha256" ]]; then
			echo -e "	${GREEN}	UltraGrid continuous build is verified and up to date.${NC}"
			return 0
		fi
	fi

	echo -e "	${RED}	UltraGrid checksum mismatch or no cached checksum! New version available. Downloading...${NC}"
	curl -sL --max-time 120 -o "$ug_local_file" "$ug_download_url"
	if [[ $? -ne 0 ]]; then
		echo -e "	${RED}	Error downloading UltraGrid continuous build! Aborting.${NC}"
		exit 1
	fi
	chmod +x "$ug_local_file"
	local_sha256=$(sha256sum "$ug_local_file" | cut -d' ' -f1)
	echo "$local_sha256" > "$ug_cached_checksum"
	echo -e "	${GREEN}	UltraGrid continuous build updated successfully with new checksum: ${local_sha256}${NC}"
}

parse_config_file() {
	local config_file="$1"
	if [[ ! -f "$config_file" ]]; then
		echo -e "${RED}Error: Config file $config_file not found.${NC}"
		exit 1
	fi
	echo "	Parsing configuration from $config_file..."
	while IFS='=' read -r key value; do
		[[ "$key" =~ ^[[:space:]]*# ]] && continue
		[[ -z "$key" ]] && continue
		key=$(echo "$key" | xargs)
		value=$(echo "$value" | xargs)
		value="${value#\"}"
		value="${value%\"}"
		value="${value#\'}"
		value="${value%\'}"
		case "$key" in
			PASSWORD) PASSWORD="$value" ;;
			DOMAIN) domain="$value" ;;
			SVR_IP|SERVER_IP) svr_ip="$value" ;;
			SVR_GW|SERVER_GATEWAY) svr_gw="$value" ;;
			SVR_DNS|SERVER_DNS) svr_dns="$value" ;;
			TIME_ZONE|TIMEZONE) timeZone="$value" ;;
			DEVELOPER_MODE|DEV_MODE) developerMode="$value" ;;
			ENABLE_WIFI) enableWifi="$value" ;;
			WIFI_SSID) wifi_ssid="$value" ;;
			WIFI_BSSID) wifi_bssid="$value" ;;
			WIFI_PASSWORD) wifi_password="$value" ;;
			WIFI_DEVICE_USER) wifi_deviceUser="$value" ;;
			WIFI_DEVICE_PASSWORD) wifi_devicePassword="$value" ;;
			WIFI_IP_ADDR) wifi_ipAddr="$value" ;;
			DEPLOYMENT_REGISTRY) DEPLOYMENT_REGISTRY="$value" ;;
			DEPLOYMENT_IP) DEPLOYMENT_IP="$value" ;;
			PATCH_MODE) patchMode="$value" ;;
			UG_BUILD_TYPE|UGDEV) dev_flag="DEV" ;;
			USE_BOOTC) USE_BOOTC="$value" ;;
			CODEC_TEST) codec_testing="1";;
		esac
	done < "$config_file"
}

#
## These functions are for build_full_iso mode
#

build_full_iso_main(){
	waveletdir="$(pwd)"
    if [[ "$1" == */ ]]; then
        waveletdir="${1%/*}"
    elif [[ -n "$1" ]]; then
        waveletdir="$1"
    fi

    #TODO - use installer vars for all these now
    SRC_ISO="${SRC_ISO:-$HOME/Downloads/wavelet_server.iso}"
    OUT_ISO="${2:-$HOME/Downloads/wavelet_server_full.iso}"

    if [[ ! -f "$SRC_ISO" ]]; then
        echo -e "${RED}	Source ISO not found: $SRC_ISO${NC}"
        echo "	Generate it first with: ./install_wavelet_server.sh -c=<wavelet.conf>"
        exit 1
    fi

    # Generate the full-mode ignition
    STOCK_ISO="$(ls "$HOME/.config/var/www"/fedora-coreos-*-live-iso.x86_64.iso 2>/dev/null | sort -V | tail -n1)"
    if [[ -z "$STOCK_ISO" ]]; then
        STOCK_ISO="$(ls "$HOME/Downloads"/fedora-coreos-*-live-iso.x86_64.iso 2>/dev/null | sort -V | tail -n1)"
    fi
    if [[ -z "$STOCK_ISO" ]]; then
        echo -e "${RED}	Stock CoreOS live ISO not found (fedora-coreos-*-live-iso.x86_64.iso).${NC}"
        echo "	It is normally downloaded to ~/.config/var/www by build_registry.sh / coreos_installer.sh."
        exit 1
    fi

    USE_BOOTC="${USE_BOOTC:-}"
    if [[ -z "$USE_BOOTC" ]]; then
        fcos_version="$(basename "$STOCK_ISO" | sed -n 's/^fedora-coreos-\([0-9]*\)\..*/\1/p')"
        if (( fcos_version >= 45 )); then
            USE_BOOTC=1
        else
            USE_BOOTC=0
        fi
    fi
    echo "	Detected FCOS $(basename "$STOCK_ISO" | grep -oP 'fedora-coreos-\K[0-9.]+') - USE_BOOTC=$USE_BOOTC (overlay suffix: $([[ "$USE_BOOTC" == 1 ]] && echo _bootc || echo none))"

    if ! ls "$HOME/.config/var/www"/*.tar.gz >/dev/null 2>&1 || \
       ! ls "$HOME/.config/var/www"/UltraGrid-*.AppImage >/dev/null 2>&1; then
        echo -e "${RED}	Wavelet tarball or UltraGrid AppImage missing from ~/.config/var/www.${NC}"
        exit 1
    fi

    echo "	Generating full-mode ignition (offline loader wired in, small initramfs).."
    generate_full_ignition "$waveletdir" || {
        echo -e "${RED}	Butane failed to transpile server_full.yml. Aborting.${NC}"
        exit 1
    }

    echo "	Customizing stock CoreOS ISO with full-mode ignition.."
    rm -f "$HOME/Downloads/wavelet_server_full_tmp.iso" "$OUT_ISO"
    # Same live karg coreos_installer.sh applies (static IP for the live env)
    liveKarg="--live-karg-append ip=192.168.1.32::192.168.1.1:255.255.255.0:svr::none"
    DEST_DEVICE="${DEST_DEVICE:-/dev/nvme0n1}"

    BOOTNEXT_HOOK="$(mktemp /tmp/wavelet_bootnext.XXXXXX.sh)"
    cat > "$BOOTNEXT_HOOK" <<'EOF'
    #!/bin/bash
    set -euo pipefail
    echo "	Setting EFI BootNext to the installed disk.."
    if ! command -v efibootmgr >/dev/null 2>&1; then
        echo "	efibootmgr not available (BIOS install?) - skipping."
        exit 0
    fi
    esp_uuid="$(blkid -s PARTUUID -o value /dev/disk/by-partlabel/EFI-SYSTEM 2>/dev/null || true)"
    if [[ -z "$esp_uuid" ]]; then
        echo "	WARNING: could not resolve installed ESP PARTUUID; BootNext not set."
        exit 0
    fi
    next_entry="$(efibootmgr -v 2>/dev/null | sed -n "s/^Boot\([0-9A-Fa-f]\{4\}\).*${esp_uuid}.*/\1/p" | head -n1)"
    if [[ -z "$next_entry" ]]; then
        echo "	WARNING: no efibootmgr entry references ESP PARTUUID $esp_uuid."
        exit 0
    fi
    if efibootmgr --bootnext "$next_entry" >/dev/null 2>&1; then
        echo "	EFI BootNext set to Boot$next_entry (installed disk)."
    else
        echo "	WARNING: failed to set EFI BootNext (firmware may boot the USB again)."
    fi
    exit 0
EOF
    coreos-installer iso customize \
        --dest-device "$DEST_DEVICE" \
        --dest-ignition "$waveletdir/ignition_files/server_full.ign" \
        --post-install "$BOOTNEXT_HOOK" \
        ${liveKarg} \
        -o "$HOME/Downloads/wavelet_server_full_tmp.iso" "$STOCK_ISO" || {
        rm -f "$BOOTNEXT_HOOK"
        echo -e "${RED}	coreos-installer failed. Aborting.${NC}"
        exit 1
    }
    rm -f "$BOOTNEXT_HOOK"
    SRC_ISO="$HOME/Downloads/wavelet_server_full_tmp.iso"

    echo -e "\n **	Building FULL wavelet server ISO (no internet required at install site) **\n"
    echo "	Source ISO: $SRC_ISO"
    echo "	Output ISO: $OUT_ISO"

    mkdir -p "$ISO_ROOT/offline"

    save_iso_images

    if ! download_offline_artifacts; then
        echo -e "${RED}	Failed to download offline artifacts (tarball/AppImage). Aborting.${NC}"
        exit 1
    fi

    if ! save_registry_images "$ISO_ROOT/offline/images"; then
        echo -e "${RED}	One or more images could not be saved, ISO would be incomplete. Aborting.${NC}"
        exit 1
    fi

    if ! stage_offline_artifacts "$waveletdir" "$ISO_ROOT/offline"; then
        echo -e "${RED}	Failed to stage offline artifacts. Aborting.${NC}"
        exit 1
    fi

    # Ensure we have disk space on this machine to properly generate the ISO.
    tmp_bytes=$(( $(stat -c%s "$SRC_ISO") ))
    offline_bytes=$(( $(du -sb "$ISO_ROOT/offline" | cut -f1) ))
    needed_bytes=$(( tmp_bytes + offline_bytes + tmp_bytes / 10 ))
    out_fs="$(df --output=target "$(dirname "$OUT_ISO")" | tail -n1)"
    avail_bytes="$(df -B1 --output=avail "$(dirname "$OUT_ISO")" | tail -n1)"
    needed_gib=$(( needed_bytes / 1024 / 1024 / 1024 ))
    avail_gib=$(( avail_bytes / 1024 / 1024 / 1024 ))
    echo "	Free space check: need ~${needed_gib}GiB, ${avail_gib}GiB available on ${out_fs}"
    if (( avail_bytes < needed_bytes )); then
        echo -e "${RED}	Not enough free space on ${out_fs} for the output ISO (need ~${needed_gib}GiB, have ${avail_gib}GiB).${NC}"
        echo "	Free up space, or point OUT_ISO at another filesystem:"
        echo "	  OUT_ISO=/path/on/bigger/disk/wavelet_server_full.iso $0"
        rm -f "$HOME/Downloads/wavelet_server_full_tmp.iso"
        exit 1
    fi

    append_offline_partition "$SRC_ISO" "$OUT_ISO" || {
        echo -e "${RED}	xorriso failed to build output ISO. Aborting.${NC}"
        exit 1
    }
    rm -f "$HOME/Downloads/wavelet_server_full_tmp.iso"

    size_gib=$(( $(stat -c%s "$OUT_ISO") / 1024 / 1024 / 1024 ))
    echo -e "\n${GREEN}	Full ISO generated: $OUT_ISO (${size_gib}GiB)${NC}"
    echo -e "\n	Deployment instructions:"
    echo "	  1. Flash $OUT_ISO to USB"
    echo "	  2. Boot the target machine from the USB and LEAVE THE USB PLUGGED IN."
    echo "	  3. First boot installs to disk fully offline (all images are embedded)."
    echo "	  4. When prompted on the console, confirm the machine is on its own isolated network."
    echo "	  5. After provisioning completes, the USB may be removed."

}

cleanup(){
    [[ -n "$ISO_ROOT" && -d "$ISO_ROOT" ]] && rm -rf "$ISO_ROOT"
}
trap cleanup EXIT

check_required_tools(){
    local missing=()
    for cmd in podman xorriso butane coreos-installer; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Missing required tools: ${missing[*]}${NC}"
        echo -e "${GREEN}Fedora/RHEL: sudo dnf install podman xorriso butane coreos-installer${NC}"
        echo -e "${GREEN}Debian/Ubuntu: sudo apt install podman xorriso butane coreos-installer${NC}"
        exit 1
    fi
}

# Check tooling before any work so we fail fast and clean
check_required_tools

generate_full_ignition(){
    # Produces ignition_files/server_full.yml + server_full.ign.
	local waveletdir="$1"
	cp "$waveletdir/ignition_files/server_custom.yml" "$waveletdir/ignition_files/server_full.yml"
	# Remove the two 3-line "path:/mode:/contents: source: https..." entries
	sed -i '/# Wavelet master zipfile/,/source: https:\/\/[^ ]*\.tar\.gz/d' \
		"$waveletdir/ignition_files/server_full.yml"
	sed -i '/# UltraGrid executable/,/source: https:\/\/[^ ]*\.AppImage/d' \
		"$waveletdir/ignition_files/server_full.yml"
	# Ensure FULL_ISO_MODE=1 is in the wavelet.conf that ignition writes.
    local conf_src="$waveletdir/ignition_files/wavelet.conf"
    local conf_tmp
    conf_tmp="$(mktemp "$waveletdir/ignition_files/wavelet.conf.XXXXXX")"
    if [[ -f "$conf_src" ]]; then
        if grep -q '^FULL_ISO_MODE=' "$conf_src"; then
            sed 's/^FULL_ISO_MODE=.*/FULL_ISO_MODE=1/' "$conf_src" > "$conf_tmp"
        else
            cp "$conf_src" "$conf_tmp"
            echo "FULL_ISO_MODE=1" >> "$conf_tmp"
        fi
		# Bootc-era FCOS is the only target for the full ISO.
        if grep -q '^USE_BOOTC=' "$conf_tmp"; then
            sed -i 's/^USE_BOOTC=.*/USE_BOOTC=1/' "$conf_tmp"
        else
            echo "USE_BOOTC=1" >> "$conf_tmp"
        fi
        # Replace the file in place (the YAML references it by name)
        mv "$conf_tmp" "$conf_src"
    else
        echo -e "${RED}	ERROR: wavelet.conf not found at $conf_src - cannot set FULL_ISO_MODE${NC}"
        return 1
    fi
	# Transpile (same --files-dir mechanism)
	butane --pretty --files-dir "$waveletdir/ignition_files/" \
        "$waveletdir/ignition_files/server_full.yml" \
        --output "$waveletdir/ignition_files/server_full.ign"
}

save_iso_images(){
	# Save the newest coreos installer image set (.iso/.img + .sig) to the installer drive.
	mkdir -p "$ISO_ROOT/offline/iso"
	curl -fsSL https://fedoraproject.org/fedora.gpg | gpg --import
	local newest_ver=""
	# Determine the newest base version across cached coreos images.
	for file in ~/.config/var/www/fedora-coreos-*; do
		[[ -f "$file" ]] || continue
		[[ "$file" == *.sig ]] && continue
		local ver
		ver="$(basename "$file" | sed -n 's/^fedora-coreos-\([0-9.]*\)\..*/\1/p')"
		[[ -n "$ver" ]] || continue
		# version-sort comparison keeps only the highest cached version.
		if [[ -z "$newest_ver" ]] || [[ "$(printf '%s\n%s\n' "$ver" "$newest_ver" | sort -V | tail -n1)" == "$ver" ]]; then
			newest_ver="$ver"
		fi
	done
	[[ -n "$newest_ver" ]] || { echo -e "${RED}	No cached fedora-coreos image found in ~/.config/var/www.${NC}"; return 1; }
	echo "	Copying newest cached CoreOS image set (version $newest_ver).."
	for file in ~/.config/var/www/fedora-coreos-${newest_ver}.*; do
		[[ -f "$file" ]] || continue
		case "$file" in
			*.img|*.iso)
				 if [[ ! -f "${file}.sig" ]]; then
					echo "	ERROR: no .sig file provided with this img, cannot verify file integrity!"
					exit 1
				fi
				if ! gpg --verify "$file.sig" "$file" >/dev/null 2>&1; then
					echo "ERROR: Signature verification failed" >&2
					exit 1
				fi
				# copy to ISO
				cp "$file" "$ISO_ROOT/offline/iso"; cp "${file}.sig" "$ISO_ROOT/offline/iso"
				;;
		esac
	done
}

save_registry_images(){
    # Save every image the server will need into $ISO_ROOT/offline/images/
    # Naming: images/<name>.oci.tar  (loaded later with 'podman load')
    local dest="$1"
    mkdir -p "$dest"

    # Base images the server pushes into its local registry (match
    # build_registry.sh pull_registry_images and install_packages.sh sourceList)
    local images=(
        "quay.io/coreos/etcd:v3.6.4"
        "quay.io/coreos/coreos-installer:release"
        "registry.fedoraproject.org/fedora:latest"
        "docker.io/library/nginx:alpine"
        "docker.io/library/php:fpm"
        "docker.io/redis:latest"
        "docker.io/library/httpd:latest"
        "docker.io/library/registry:latest"
        "quay.io/freeipa/freeipa-server:almalinux-10"
    )
    # Locally built images (exist as localhost/<name> after build_registry.sh)
    # Bootc pathway (FCOS >=45 / USE_BOOTC=1) builds the overlays with a
    # _bootc suffix (docs/UPDATE_TO_BOOTC.md).
    local overlay_suffix=""
    if [[ "${USE_BOOTC:-0}" == "1" ]]; then
        overlay_suffix="_bootc"
    fi
    local built_images=(
        "coreos_overlay_client${overlay_suffix}"
        "coreos_overlay_server${overlay_suffix}"
        "tftpd"
        "tftpboot"
        "isc-kea"
        "radiusd"
        "php-fpm-redis"
    )

    local failed=0
    echo "	Saving base images as OCI archives.."
    for img in "${images[@]}"; do
        # Prefer the localhost/<shortname> tag build_registry.sh created, so the
        # archive round-trips with the tag the server expects; fall back to source ref.
        local short="${img##*/}"
        short="${short%%:*}"
        local ref="localhost/$short"
        podman image exists "$ref" || ref="$img"
        if ! podman image exists "$ref"; then
            echo -e "${RED}	Image $img not present in local podman store (run build_registry.sh first).${NC}"
            failed=1
            continue
        fi
        echo "	  -> $ref  =>  $short.oci.tar"
        podman save --format oci-archive -o "$dest/$short.oci.tar" "$ref" || failed=1
    done

    echo "	Saving built overlay/service images as OCI archives.."
    for name in "${built_images[@]}"; do
        if podman image exists "localhost/$name"; then
            echo "	  -> localhost/$name  =>  $name.oci.tar"
            # oci-archive keeps the gzip-compressed layer blobs small for the USB.
            podman save --format oci-archive -o "$dest/$name.oci.tar" "localhost/$name" || failed=1
        else
            echo -e "${RED}	Image localhost/$name not present (run build_registry.sh first).${NC}"
            failed=1
        fi
    done
    return $failed
}

download_offline_artifacts(){
    # Fetch the wavelet tarball and UltraGrid AppImage from their internet sources
    local conf="$waveletdir/ignition_files/wavelet.conf"
    local branch="master"
    if [[ -f "$conf" ]] && grep -q '^DEVELOPER_MODE=1' "$conf"; then
        branch="armelvil-working"
    fi

    mkdir -p "$HOME/.config/var/www"
    # Wavelet tarball (reuse a valid cached copy if present)
    local tarball="$HOME/.config/var/www/$branch.tar.gz"
    if [[ -f "$tarball" ]] && tar -tzf "$tarball" >/dev/null 2>&1; then
        echo "	Using cached wavelet tarball for branch $branch.."
    else
        local download_url="https://github.com/Allethrium/wavelet/archive/refs/heads/$branch.tar.gz"
        echo "	Downloading wavelet tarball (branch $branch) from GitHub.."
        if ! curl -s -f -L -o "$tarball" "$download_url"; then
            echo -e "${RED}	Error downloading wavelet tarball! Aborting.${NC}"
            return 1
        fi
        if ! tar -tzf "$tarball" >/dev/null 2>&1; then
            echo -e "${RED}	Downloaded wavelet tarball is not a valid archive! Aborting.${NC}"
            rm -f "$tarball"
            return 1
        fi
    fi

    # UltraGrid continuous AppImage
    local ug_repo="${UG_RELEASE_REPO:-armelvil/UltraGrid}"
    local ug_url="https://github.com/${ug_repo}/releases/download/continuous/UltraGrid-continuous-x86_64.AppImage"
    local ug_file="$HOME/.config/var/www/UltraGrid-continuous-x86_64.AppImage"
    if [[ -f "$ug_file" ]]; then
        echo "	Using cached UltraGrid AppImage.."
    else
        echo "	Downloading UltraGrid continuous build from GitHub ($ug_repo).."
        if ! curl -sL --max-time 120 -o "$ug_file" "$ug_url"; then
            echo -e "${RED}	Error downloading UltraGrid continuous build! Aborting.${NC}"
            rm -f "$ug_file"
            return 1
        fi
        chmod +x "$ug_file"
    fi
    return 0
}

stage_offline_artifacts(){
    local src_dir="$1"
    local dest="$2"
    mkdir -p "$dest/rpms"
    local branch="master"
    local conf="$src_dir/ignition_files/wavelet.conf"
    if [[ -f "$conf" ]] && grep -q '^DEVELOPER_MODE=1' "$conf"; then
        branch="armelvil-working"
    fi
    local tarball="$HOME/.config/var/www/$branch.tar.gz"
    if [[ ! -f "$tarball" ]]; then
        echo -e "${RED}	Wavelet tarball missing at $tarball (download step failed?).${NC}"
        return 1
    fi
    echo "	Staging $(basename "$tarball").."
    cp "$tarball" "$dest/wavelet.tar.gz"
    # UltraGrid AppImage - downloaded by download_offline_artifacts() above.
    local appimage="$HOME/.config/var/www/UltraGrid-continuous-x86_64.AppImage"
    if [[ ! -f "$appimage" ]]; then
        echo -e "${RED}	UltraGrid AppImage missing at $appimage (download step failed?).${NC}"
        return 1
    fi
    echo "	Staging $(basename "$appimage").."
    cp "$appimage" "$dest/UltraGrid.AppImage"
    # FFmpeg RPMs
    if ls "$HOME/.config/var/www"/rpms/*.rpm >/dev/null 2>&1; then
        echo "	Staging FFmpeg RPMs.."
        cp "$HOME/.config/var/www"/rpms/*.rpm "$dest/rpms/" || return 1
    else
        echo -e "${RED}	No FFmpeg RPMs found in ~/.config/var/www/rpms.${NC}"
        return 1
    fi
    return 0
}

append_offline_partition(){
    # Append the offline tree as a SEPARATE PARTITION on the USB image,
    # with its own filesystem label "wavelet-offline".  This is where install_packages.sh will look on 1st boot.
    local in_iso="$1"
    local out_iso="$2"
    local part_img
    part_img="$(dirname "$out_iso")/wavelet-offline-part.img"
    # Size: the offline tree + 10% margin, rounded up to whole MiB.
    local offline_bytes size_mib
    offline_bytes="$(du -sb "$ISO_ROOT/offline" | cut -f1)"
    size_mib=$(( (offline_bytes + offline_bytes / 10) / 1024 / 1024 + 1 ))
    echo "	Creating ${size_mib}MiB ext4 partition image for offline data.."
    rm -f "$part_img"
    if ! mkfs.ext4 -L wavelet-offline -F -d "$ISO_ROOT/offline" "$part_img" "${size_mib}M" 2>&1 | tail -n 3; then
        echo -e "${RED}	mkfs.ext4 failed for offline partition image. Aborting.${NC}"
        rm -f "$part_img"
        return 1
    fi
    echo "	Appending offline partition to ISO with xorriso (rewrites the image, may take a while).."
    rm -f "$out_iso"
    if ! xorriso \
        -indev "$in_iso" \
        -outdev "$out_iso" \
        -boot_image any keep \
        -append_partition 2 0x83 "$part_img" \
        2>&1 | tail -n 5; then
        echo -e "${RED}	xorriso failed to append offline partition. Aborting.${NC}"
        rm -f "$part_img"
        return 1
    fi
    rm -f "$part_img"
    [[ -f "$out_iso" ]]
}

#
## previous in coreos_installer.sh
#

coreos_installer(){
	for i in "$@"
		do
			case $i in
				"mode=iso")
					echo -e "	Running in network isolation mode, enabling kargs for faster provisioning..\n"
					isoMode="1"
					;;
				deploy=*)
					DEPLOYMENT_SERVER="${i#*=}"
					;;
				*)
					echo -e "	Initial Setup mode running, configuring Server ISO File..\n"
					;;
			esac
	done

	if [[ ! -f "$HOME/Downloads" ]]; then
		mkdir -p "$HOME/Downloads"
	fi

	# Legacy code
	echo "	Removing old customized ISO files if they exist.."
		rm -rf "${HOME}"/Downloads/wavelet_server.iso
		rm -rf "${HOME}"/Downloads/wavelet_decoder.iso

	echo -e "\n	**	Note: Put the drive controller for target devices in AHCI mode from BIOS setup!\n	**	RAID or other modes have been observed to interfere with the imaging process.\n"
	# automated_installer process now autodetects the system's drive for installation - this arg is just here as a placeholder now.
	DESTINATION_DEVICE="/dev/nvme0n1"
	FILEPREFIX="fedora-coreos-"

	REGISTRY_DIR=""
	if [[ -n "$DEPLOYMENT_SERVER" ]]; then
		# A deployment server already has the ISO available, we use that
		REGISTRY_DIR="${HOME}/.config/var/www"
		echo "	Deployment mode active, checking for files in httpd resource directory: $REGISTRY_DIR"
	else
		echo "	Deployment mode not active, checking for files in current dir.."
		REGISTRY_DIR="$(pwd)"
	fi

	# Check if valid CoreOS raw.xz files already exist in the registry directory
	if ls "$REGISTRY_DIR"/fedora-coreos-*-live-iso.x86_64.iso > /dev/null 2>&1; then
		EXISTING_FILES=($(ls "$REGISTRY_DIR"/fedora-coreos-*-live-iso.x86_64.iso 2>/dev/null))
	else
		EXISTING_FILES=()
	fi

	# Check for any other CoreOS files that might be older builds or different formats
	OTHER_COREOS_FILES=()
	if ls "$REGISTRY_DIR"/$FILEPREFIX* > /dev/null 2>&1; then
		# Get all fedora-coreos-* files
		for f in "$REGISTRY_DIR"/$FILEPREFIX*; do
			if [[ -f "$f" ]]; then
				basename_f=$(basename "$f")
				# Check if it's a metal.x86_64.raw.xz file
				if [[ "$basename_f" == *"live-iso.x86_64.iso"* ]]; then
					# It's a valid raw.xz file, already in EXISTING_RAW_XZ_FILES
					continue
				else
					# It's an older build or different format (e.g., .iso, .img, etc.)
					OTHER_COREOS_FILES+=("$f")
				fi
			fi
		done
	fi

	DOWNLOAD_NEEDED=0
	if [[ ${#EXISTING_FILES[@]} -eq 0 ]]; then
		echo -e "\n	No valid CoreOS raw.xz files found in registry, downloading CoreOS metal raw image from internet, please be patient while this task executes..\n"
		DOWNLOAD_NEEDED=1
	else
		echo "	Valid CoreOS images/components already exist in the registry."
	fi

	# Download if needed
	if [[ $DOWNLOAD_NEEDED -eq 1 ]]; then
		# Using the podman container for consistency with build_registry.sh
		# Downloading raw.xz is typically better for automated disk imaging than ISO
		REGISTRY_REF="quay.io/coreos/coreos-installer:latest"
		podman run --security-opt label=disable \
			--pull=always \
			--rm \
			-v /tmp:/data -w /data \
			"$REGISTRY_REF" download -s stable -a x86_64 -p metal -f raw.xz

		# Move the downloaded ISO to the registry directory for future use
		DOWNLOADED_FILE=$(ls /tmp/fedora-coreos-*-live-iso.x86_64.iso 2>/dev/null | head -n1)
		if [[ -n "$DOWNLOADED_FILE" ]]; then
			mv "$DOWNLOADED_FILE" "$REGISTRY_DIR/" 2>/dev/null || true

			# Notify about older builds if they exist
			if [[ ${#OTHER_COREOS_FILES[@]} -gt 0 ]]; then
				echo -e "\n	**	Note: Older CoreOS build(s) or files exist in the registry:"
				for old_file in "${OTHER_COREOS_FILES[@]}"; do
					echo "	   - $(basename "$old_file")"
				done
				echo "	Consider cleaning up older builds if they are no longer needed."
			fi
		fi
	fi

	# Find Image file and generate ignition files utilizing Butane
	# Look for ISO files in the registry directory or current directory
	IMAGEFILE=""
	if [[ -n "$REGISTRY_DIR" && -d "$REGISTRY_DIR" ]]; then
		IMAGEFILE="$(ls "$REGISTRY_DIR"/*.iso 2>/dev/null | head -n1)"
	fi
	if [[ -z "$IMAGEFILE" ]]; then
		IMAGEFILE="$(ls *.iso 2>/dev/null | head -n1)"
	fi

	if [[ -z "$IMAGEFILE" ]]; then
		echo "	Error: No ISO files found in registry directory ($REGISTRY_DIR) or current directory."
		exit 1
	fi

	echo "	Generating Ignition files with Butane"
	# Generate butane setting files-dir to current path
	# This is so that we can utilize the local files argument in server_custom.yml to inject the necessary files from /ignition subdir
	echo "	Generating server.ign.."
	embedDir="./ignition_files/"
	ymlSource="./ignition_files/server_custom.yml"
	outputIgn="./ignition_files/server.ign"
	output="$(butane --pretty --files-dir "$embedDir" "$ymlSource" --output "$outputIgn")"
	echo "	Customizing ISO files with Ignition"
	# This will only want to be switched on if we are using an isolated system, it will significantly speed up boot time;
	if [[ "${isoMode}" = "1" ]]; then
		# ip<client-IP-number>:[<server-id>]:<gateway-IP-number>:<netmask>:<client-hostname>:<interface>:{dhcp|dhcp6|auto6|on|any|none|off}
		liveKarg="--live-karg-append ip=192.168.1.32::192.168.1.1:255.255.255.0:svr::none"
	fi
	echo -e "\n	ISO files output to ${HOME}/Downloads..\n"
	# Generate Server ISO
	echo "	Provision Server ISO"
	liveKarg="--live-karg-append ip=192.168.1.32::192.168.1.1:255.255.255.0:svr::none"
	coreos-installer iso customize \
		--dest-device ${DESTINATION_DEVICE} \
		--dest-ignition ./ignition_files/server.ign ${liveKarg} \
		-o ${HOME}/Downloads/wavelet_server.iso ${IMAGEFILE}

	echo "	Done, please note customized yml and transpiled files will remain in the /ignition_files/ folder for inspection and debugging purposes."
	# removes generated user YAML blocks to keep everything clean
	#rm -rf ./*.yml
	echo -e "\n 	Image(s) generated,\n	If this is initial setup, please write wavelet_server.iso to a suitable boot media."
	echo "	You may then proceed to launch installation by booting from it on your target machine."
}

####
#
# Main
#
####


waveletdir="$(pwd)"
# We generally want stdout here instead of a log.
#exec >$waveletdir/logs/server_bootstrap.log 2>&1
secActive=0
echo "	Input Args: "; echo "	${*}"
timeZone=""

for i in "$@"
	do
		case $i in
			-d|--dev)
				echo -e "${RED}Dev mode enabled, switching git tree to working branch${NC}"	;	developerMode="1"
				;;
			-h|--help)
				print_help;	exit 0
				;;
			-p=*|--password=*|--pass=*)
				# TODO - split to SU and wavelet user options so we get different passwords.  LATER.  right now we are still labbing!
				PASSWORD=${i#*=}; echo -e "	Password defined for BOTH user accounts as: ${PASSWORD}";
				;;
			-ws=*|--wifissid=*)
				wifi_ssid=${i#*=}; echo -e "	WiFi SSID defined as: ${wifi_ssid}";
				;;
			-wb=*|--wifibssid=*)
				wifi_bssid=${i#*=}; echo -e "	WiFi BSSID/MAC defined as: ${wifi_bssid}";
				;;
			-wip=*|--wifiapip=*)
				wifi_ipAddr=${i#*=}; echo -e "	WiFi Access Point IP defined as: ${wifi_ipAddr}"
				;;
			-wp=*|--wifipass=*)
				wifi_password=${i#*=}; echo -e "	WiFi WPA PSK defined as: ${wifi_password} (will have no effect with Security layer active!)";
				;;
			-wap=*|--wifiappass=*)
				wifi_devicePassword=${i#*=}; echo -e "WiFi AP Password: ${wifi_devicePassword}";
				;;
			-wau=*|--wifiapuser=*)
				wifi_deviceUser=${i#*=}; echo -e "WiFi AP User: ${wifi_deviceUser}";
				;;
			-enablewifi)
				enableWifi="1"; echo -e "	WiFi mode enabled. WiFi parameters will be written to ignition files.";
				;;
			-domain=*)	domain=${i#*=}; echo -e "Target domain: ${domain}";
				;;
			-ugd|--ugdev|--ugcontinuous)	dev_flag="DEV";
				;;
			-4=*|--ip4subnet=*)
				ip4=${i#*=}; echo -e "	WIP! IPv4 Subnet (CIDR) defined as: ${ip4}";
				;;
			-6=*|--ipv6subnet=*)
				ip6=${i#*=}; echo -e "	WIP! IPv6 Subnet fefined as: ${ip6}";
				;;
			-ip=*|--serverip=*)
				svr_ip=${i#*=}; echo -e "	WIP! Server Static IPv4 defined as ${svr_ip}}";
				;;
			-g=*|--servergateway=*)
				svr_gw=${i#*=}; echo -e "	WIP! Server IPv4 gateway defined as ${svr_gw}";
				;;
			-dns=*|--serverdns=*)
				svr_dns=${i#*=}; echo -e "	WIP! Server IPv4 dns defined as ${svr_dns}";
				;;
     	    -reg=*|--localregistry=*)
				registry=${i#*=}; echo -e "	Local registry defined as IP ${registry}";
				;;
            -b|--patched)
            	patchMode="ON"; echo -e "	Pulling from patched UG branch";
            	;;
            -t=*|--timezone=*)
            	timeZone=${i#*=}; echo -e "	Timezone set to $timeZone (default to America/New_York if empty)";
            	;;
			-c=*|--config=*)
				configFile=${i#*=}; echo -e "	Extracting configuration from defined config file: ${configFile}"
				;;
			-u=*|--unattend=*)
				UNATTENDED_INSTALL="1"
				echo "	Unattend flag enabled, server will not wait to setup DHCP, DNS and IdM services during bootstrap!"
				;;
			--full=*|--build_full_iso)
				echo "	Building full offline installation!"
				build_full_iso
				;;
			*)
				echo "bad input argument: $i";
				;;
		esac
done
if [[ -z "$timeZone" ]]; then
	timeZone="America/New_York"
fi

if [[ -z "$configFile" ]]; then
	requiredOptions=("PASSWORD" "domain" "svr_gw")
else
	# Parse the configFile for all options
	parse_config_file "$configFile"
	requiredOptions=() # Options already set via config file
fi

# Test for required options from either the configFile or direct args.
if [[ ${#requiredOptions[@]} -gt 0 ]]; then
	for opt in "${requiredOptions[@]}"; do
		echo "Required option $opt set!"
		if [[ -z "${!opt}" ]]; then
			echo -e "\n\n${RED} ERROR:	The install option '$opt' must be defined!
			\n	Aborting installation, as process will fail without these data.${NC}\n\n"
			exit 1
		fi
	done
fi

if [[ $domain == *".local" ]]; then
	echo -e "\n${RED}.local TLD domain is reserved for mDNS, please select another domain or subdomain, preferably one from your organization's domain"
	echo -e "${RED}Failure to do this may result in unpredictable behavior with local name resolution.${NC}"
	exit 1
fi

echo -e "\n	Copying base ignition files for customization.."
cp ignition_files/ignition_server.yml ./server_custom.yml
cp ignition_files/ignition_decoder.yml ./decoder_custom.yml
#ls -l ./*.yml
# remove old iso files
rm -rf "${HOME}"/Downloads/wavelet_server.iso
rm -rf "${HOME}"/Downloads/wavelet_decoder.iso

if [[ -n "$DEPLOYMENT_REGISTRY" ]]; then
	echo "	We have defined a local registry for faster setup.  Wavelet will pull OCI layers from this registry."
	echo "	NOTE:  The registry must be accessible from the wavelet subnet until the server is provisioned."
	# We would verify the registry format here to ensure it's a valid type, script will break if not valid format
	# These get an IP from the local interface, useful in automation later
	get_publicinterface
	if [[ -z "$DEPLOYMENT_IP" ]]; then
		# We specified a registry, but not a deployment registry IP.  resolve ithere
		Echo "	Determining deployment IP address from registry argument.."
		# make sure we get the IP address from the correct subnet if we have a server on multiple subnets
		DEPLOYMENT_IP="$result"
	fi
	validate_ip_port "$DEPLOYMENT_IP"
	INPUTFILES="server_custom.yml decoder_custom.yml"
	rm -f ignition_files/wavelet_keys.csv
	echo "type,path,mode,overwrite,owner,group,content" >> ignition_files/wavelet_keys.csv
	sed -i "s|https://github.com/Allethrium/wavelet/archive/refs/heads/master.tar.gz|https://${DEPLOYMENT_IP%%:*}:8443/master.tar.gz|g" $INPUTFILES
	# Set UltraGrid to local LAN server, which ought to have both builds if build_registry.sh worked as it should.
	sed -i "s|https://github.com/CESNET/UltraGrid/releases/download/v1.10.5/UltraGrid-1.10.5-x86_64.AppImage|https://${DEPLOYMENT_IP%%:*}:8443/UltraGrid-1.10.5-x86_64.AppImage|g" $INPUTFILES

	# Add CA certificate to wavelet_keys.csv for CoreOS to trust the deployment server's self-signed certificate
	if [[ -f "$HOME/.config/var/ssl/certs/ca.crt" ]]; then
		# Add the CA to ignition folder
		cp "$HOME/.config/var/ssl/certs/ca.crt" "ignition_files/ca.crt"
		cp "$HOME/.config/var/ssl/certs/ca.crt" "$HOME/.config/var/www/ca.crt"
		# Compute SHA256 hash of the CA certificate
		caHash="sha256-$(sha256sum "$HOME/.config/var/ssl/certs/ca.crt" | cut -d' ' -f1)"
		# Generate base64-encoded data URI for the CA certificate
		ca_base64=$(base64 -w 0 "$HOME/.config/var/ssl/certs/ca.crt")
		ca_data_uri="data:text/plain;base64,${ca_base64}"
		# Replace placeholders in server ignition file for certificateAuthorities
		ca_data_yaml
    	ca_data="$(cat ca_data_yaml)"
    	awk -vca_block="$ca_data" '/# Comment_tag_CA/{print ca_block;next}1' \
    		./server_custom.yml > tmp && mv tmp ./server_custom.yml
    	sed -i "s|https://DEPLOYMENT_SERVER/ca.crt|https://$DEPLOYMENT_IP:8080/ca.crt|g" ./server_custom.yml
    	ca_file="$(cat ca_file_yaml)"
    	awk -vca_file="$ca_file" '/    # Deployment server CA goes here/{print ca_file;next}1' \
    		./server_custom.yml > tmp && mv tmp ./server_custom.yml
		rm -f {ca_data_yaml,ca_file_yaml}
	fi
	download_wavelet_git
else
	echo "	Local registry option not defined, running standalone setup.."
	registry="$SVR_IP"
	INPUTFILES="server_custom.yml decoder_custom.yml"
	rm -f ignition_files/wavelet_keys.csv
	echo "type,path,mode,overwrite,owner,group,content" >> ignition_files/wavelet_keys.csv
	# Note the nameserver must later be removed because it will interfere with DNS during spinup
	echo "	Setting nameserver to gateway 9.9.9.9 for simple DNS resolution during initial setup.."
	sed -i "s|#nameserver|- nameserver=9.9.9.9|g" $INPUTFILES
	# Remove the security.tls.certificateAuthorities section for standalone setup
	# The server will use its domain CA (FreeIPA) that gets provisioned during the second boot
	sed -i '/^security:/,/^storage:/d' $INPUTFILES
	# Also remove any orphaned 'ignition:' lines that might be left
	sed -i '/^ignition:/d' $INPUTFILES
fi

echo "	Dev mode is now enabled by default due to the need for running a patched UltraGrid AppImage.."
dev_flag="DEV";

if [[ -n "$configFile" ]]; then
	automatic_setup
else
	echo -e "${RED}Error: Lab mode (--lab) or a configuration file (--config=<file>) must be provided.${NC}"
	print_help
	exit 1
fi

echo "	Removing old ignition files and cleaning up.."
mv ${INPUTFILES} ignition_files/
rm -rf ignition_files/*.ign
rm -rf *.secure
rm -rf users_yaml dev.flag
rm -rf *.yml
if [[ -n "$DEPLOYMENT_REGISTRY" ]]; then
	coreos_installer "${developerMode}" "deploy=$DEPLOYMENT_REGISTRY"
else
	coreos_installer "${developerMode}"
fi