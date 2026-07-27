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
	cat <<EOF > users_yaml
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
	# TODO ensure this data object is available on the local httpd server after build_registry.sh
	# TODO ensure this works.
	cat <<EOF > ca_data_yaml
ignition:
  security:
    tls:
      certificate_authorities:
        # This is only for the server deploying against a local httpd/registry.
        - local: ca.crt
          verification:
            hash: ${caHash}
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
# This refers to the server's registry.
REGISTRY=${svr_ip:-192.168.1.32}
# Additional system build state flags
UG_BUILD_TYPE=${dev_flag:-release}
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
	dir,/etc/systemd/resolved.conf.d,0755,,root,root,
	dir,/etc/ssh/ssh_config.d,0755,,root,root,
	dir,/usr/local/backgrounds/sway,0755,,root,root,
	dir,/var/lib/systemd/linger/wavelet,0755,,root,root,
	dir,/var/lib/systemd/linger/wavelet-root,0755,,root,root,
EOF

	# Customize launching kernel args, this will accelerate the bootup as NetworkManager-wait-online won't hang for 30+s
	echo "	Applying kernel args: ip=${svr_ip}::${gateway}:${subnet}:${serverHostName}::on"
	sed -i "s|ip=192.168.1.32::192.168.1.1:255.255.255.0:svr.wavelet.allethrium::on|ip=${svr_ip}::${gateway}:${subnet}:${serverHostName}::on|g" ${INPUTFILES}
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
	users=("wavelet-root" "wavelet")
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
	if curl -s http://$registry_port/v2 > /dev/null; then
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
		exit 1
	fi
	echo "	Branch $GH_BRANCH commit SHA: $commitSha"
	# Check if we have a cached tarball with matching SHA
	local cached_tarball="$HOME/.config/var/www/${GH_BRANCH}_cached.tar.gz"
	local cached_sha_file="$HOME/.config/var/www/${GH_BRANCH}_sha256.txt"
	if [[ -f "$cached_tarball" ]] && [[ -f "$cached_sha_file" ]]; then
		cached_sha=$(cat "$cached_sha_file")
		if [[ "$cached_sha" == "$commitSha" ]]; then
			echo "	Using cached wavelet tarball with matching commit SHA: $commitSha"
			cp "$cached_tarball" "$HOME/.config/var/www/$GH_BRANCH.tar.gz"
			echo "	Acquired wavelet tarball from cache, proceeding.."
			return 0
		fi
	fi

	# Determine download source: local deployment server (HTTPS) or GitHub (HTTPS)
	local download_url
	if [[ -n "$DEPLOYMENT_REGISTRY" ]]; then
		download_url="https://${DEPLOYMENT_REGISTRY%%:*}:8443/${GH_BRANCH}.tar.gz"
		# Use --insecure for self-signed certificate on local deployment server
		if curl -s -k -L -o "$HOME/.config/var/www/$GH_BRANCH.tar.gz" "$download_url"; then
			echo "	Acquired wavelet tarball from local deployment server, proceeding.."
		else
			echo "	Error downloading wavelet tarball from local deployment server!  aborting!"
			echo "	Please check this user's write permissions to ~/.config/var/www"
			exit 1
		fi
	else
		download_url="https://github.com/Allethrium/wavelet/archive/refs/heads/$GH_BRANCH.tar.gz"
		if curl -s -L -o "$HOME/.config/var/www/$GH_BRANCH.tar.gz" "$download_url"; then
			echo "	Acquired wavelet tarball, proceeding.."
		else
			echo "	Error downloading wavelet tarball!  aborting!"
			echo "	Please check this user's write permissions to ~/.config/var/www"
			exit 1
		fi
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
			PATCH_MODE) patchMode="$value" ;;
			UG_BUILD_TYPE|UGDEV) dev_flag="DEV" ;;
			CODEC_TEST) codec_testing="1";;
		esac
	done < "$config_file"
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
	validate_ip_port "$DEPLOYMENT_REGISTRY"
	INPUTFILES="server_custom.yml decoder_custom.yml"
	rm -f ignition_files/wavelet_keys.csv
	echo "type,path,mode,overwrite,owner,group,content" >> ignition_files/wavelet_keys.csv
	sed -i "s|192.168.1.32:5000|$DEPLOYMENT_REGISTRY|g" $INPUTFILES
	sed -i "s|192.168.1.32:8080|${DEPLOYMENT_REGISTRY%%:*}:8443|g" $INPUTFILES
	sed -i "s|https://github.com/Allethrium/wavelet/archive/refs/heads/master.tar.gz|https://${DEPLOYMENT_REGISTRY%%:*}:8443/master.tar.gz|g" $INPUTFILES
	# Set UltraGrid to local LAN server, which ought to have both builds if build_registry.sh worked as it should.
	sed -i "s|https://github.com/CESNET/UltraGrid/releases/download/v1.10.5/UltraGrid-1.10.5-x86_64.AppImage|https://${DEPLOYMENT_REGISTRY%%:*}:8443/UltraGrid-1.10.5-x86_64.AppImage|g" $INPUTFILES

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
    	ca_block="$(cat ca_data_yaml)"
    	awk -vca_block="$ca_block" '/# Comment_tag_CA/{print ca_block;next}1' \
    		./server_custom.yml > tmp && mv tmp ./server_custom.yml
    	sed -i "s|https://DEPLOYMENT_SERVER/ca.crt|https://$DEPLOYMENT_REGISTRY:8080/ca.crt|g" ./server_custom.yml
	fi
	download_wavelet_git
else
	echo "	Local registry option not defined, running standalone setup.."
	registry="$SVR_IP"
	INPUTFILES="server_custom.yml decoder_custom.yml"
	rm -f ignition_files/wavelet_keys.csv
	echo "type,path,mode,overwrite,owner,group,content" >> ignition_files/wavelet_keys.csv
	sed -i "s|192.168.1.32:5000|$registry|g" $INPUTFILES
	sed -i "s|192.168.1.32:8080|${registry%%:*}:8080|g" $INPUTFILES
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
echo -e "${GREEN}	Calling coreos_installer.sh to generate ISO images."
echo -e "	You will need to burn the generated server ISO to USB/SD cards for initial boot.${NC}"
./coreos_installer.sh "${developerMode}"