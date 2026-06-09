#!/bin/bash

# This script bootstraps your initial wavelet server based upon input variables.
# Many functions rely on Wavelet running its own DHCP and domain server, it can be modified to work in a larger network
# This would require work to support a multitude of different environments, and is out of the current scope of the project.

RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"

client_networks(){
	echo -e "\nSystem configured to be run on a larger (client/corporate) network.\n"
	echo -e "Please input the system's gateway IP address, subnet mask (CIDR), and your corporate DNS resolver.\n"
	read -p "Gateway IPv4 Address: " GW
	read -p "Subnet Mask CIDR (e.g. 24 for a /24): " SN
	read -p "Primary DNS resolver IPv4 (e.g. 192.0.2.53): " svr_dns
	# Validate user input
	if ! [[ "${GW}" =~ ^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; then
				echo -e "Invalid Gateway IPv4 Address format. Please use the format A.B.C.D."
				return
	fi
	if ! [[ "${svr_dns}" =~ ^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; then
			echo -e "Invalid DNS IPv4 Address format."
			return
	fi
	if ! [[ "${SN}" =~ ^[0-9]+$ ]]; then
		echo -e "Invalid Subnet Mask CIDR format. Please use only digits."
		return
	fi
	if ! [[ "${SN}" -ge 16 && "${SN}" -le 32 ]]; then
		echo -e "Subnet Mask CIDR value must be between 16 and 32."
		return
	fi
	grIP="${GW}/${SN}"
	if [[ "${SN}" -gt 28 ]]; then
		echo -e "Subnet mask is too small for a Wavelet system, we need at least 32 host IPs to be available!"
	elif [[ "${SN}" -lt 24 ]]; then
		echo -e "Subnet mask seems very large - Wavelet would work best on an isolated network in authoritative mode!\n"
	else
		echo -e "Subnet mask selected, continuing.."
		hostname_domain
	fi
	corporateMode="1"
	# Apply gateway and subnet to ignition templates
	sed -i "s/192.168.1.1/${GW}/g" ${INPUTFILES}
	sed -i "s/255.255.255.0/${SN}/g" ${INPUTFILES}
	# Remove any placeholder nameserver kernel args if present in templates
	sed -i "s/- nameserver/d" ${INPUTFILES}
}

hostname_domain(){
	echo -e "\n"
	echo -e "An isolated network appliance should be labeled as per your organization's location, department, room number.\n"
	echo -e "A non-isolated appliance should be labeled in accordance with your organizations standards.\n"
	read -p "Please input the system's target Domain and desired fully qualified hostname: " FQDN
	read -p "Please input the system's desired static IP address.  This is highly recommended." STATICIP
	if [[ $STATICIP = "" ]]; then
		echo -e "Preference for DHCP noted, we will attempt to utilize hostnames instead of IP addresses.  \n
		Please note this will result in unreliable operation if your DHCP server is improperly configured, slow, or ever unreachable to the Wavelet system. \n"
	else
		echo -e "Static IP stored"
	fi
	# SED for 192.168.1.32 and replace with ${STATICIP} in server.ign, etcd, etc
	INPUTFILES="server_custom.yml decoder_custom.yml"
	sed -i "s/192.168.1.32/${STATICIP}/g" ${INPUTFILES}
	# SED for svr.wavelet.allethrium in decoder.ign and replace with FQDN
	sed -i "s/svr.wavelet.allethrium\/$FQDN/g" ${INPUTFILES}
	INPUTFILES=./webfiles/root/usr/local/bin/wavelet_build.sh
	sed -i "s/192.168.1.32/${STATICIP}/g" ${INPUTFILES}
	# SED for svr.wavelet.allethrium and replace with ${FQDN} in server.ign, etcd, etc
	sed -i "s/192.168.1.32/${FQDN}/g" ${INPUTFILES}
	customization
}

# user stuff
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

generate_user_yaml(){
	local name=$1
	local password_hash="$(cat ${user}.pw.secure)"
	local ssh_authorized_keys=$(cat ${name}-ssh.pub)
	local user_yaml="${name}_yaml.yml"
	if [[ "${name}" = "wavelet-root" ]]; then
		echo -e "\n	wavelet-root user, setting UID to 9337"
		uid="9337"
		group1="wheel"
		group2="sudo"
		sed -i "s|#- GROUPGOESHERE|- $group1\n        #- GROUPGOESHERE|" "${user_yaml}"
		sed -i "s|#- GROUPGOESHERE|- $group2\n        #- GROUPGOESHERE|" "${user_yaml}"
	elif [[ "${name}" = "wavelet" ]]; then
		echo -e "\n	wavelet user, setting UID to 1337"
		uid="1337"
	else 
		echo -e "			User ID not preset, system will assign them."
	fi
	if [[ -n ${uid} ]]; then
		echo -e
		sed -i "s|USERNAMEGOESHERE|USERNAMEGOESHERE\n      uid: $uid|" "${user_yaml}"
	fi
	# We use a pipe instead of a / here, because the pubkeys and passwords hashes may contain a / and therefore escape the rest of the data.
	echo -e " 	Working on user ${name}\n"
	sed -i "s|#ADD_USER_YAMLHERE|""|" "${user_yaml}"
	sed -i "s|PASSWORDGOESHERE|$password_hash|" "${user_yaml}"
	sed -i "s|PUBKEYGOESHERE|$ssh_authorized_keys|" "${user_yaml}"
	sed -i "s|USERNAMEGOESHERE|$name|" "${user_yaml}"
	sed -i "s|USERHOMEDIR|$name|" "${user_yaml}"
}

set_pw(){
	local attempts=3
	local success=0
	local user=$1
	local tmp_pw=""
	while [[ ${success} -ne 1 ]] && [[ ${attempts} -gt 0 ]]; do
		echo -e >&2 "			${GREEN}Remaining attempts: ${attempts}${NC}"
		read -srp "		Please input a password for ${user}:$(echo $'\n	-')" tmp_pw
		if [[ "${tmp_pw}" == "" ]]; then
			echo -e >&2 "		Password may not be empty."
			if [[ ${attempts} -eq 0 ]]; then
				echo -e "		${RED}Maximum attempts exceeded, exiting.${NC}"
				success=0
				break 1
			fi
			((attempts--))
			continue
		fi
		local matchattempts=3
		while [[ ${success} -ne 1 ]] && [[ ${matchattempts} -gt 0 ]]; do
			read -srp "`echo $'\n'`	Please input the password again to verify for ${user}:$(echo $'\n	-')" tmp_pw2
			if [[ "${tmp_pw}" == "${tmp_pw2}" ]]; then
				echo -e >&2 "`echo $'\n-------->'`		${GREEN}Passwords match!  Continuing..${NC}"
				mkpasswd --method=yescrypt "${tmp_pw}" > "${user}.pw.secure"
				success=1
				break 2
			else
				echo -e >&2 "\n		Passwords do not match! Trying again..\n"
				((matchattempts--))
				echo -e >&2 "			${RED}Remaining attempts: ${matchattempts}${NC}"
				if [[ ${success} -ne 1 ]] && [[ ${matchattempts} -eq 0 ]]; then
					echo -e >&2 "		${RED}Maximum attempts exceeded.  Please start again to set this user's password.${NC}"
					success=0
				fi
			fi
		done # Inner loop
	done # Outer loop
	if [[ $success == 1 ]]; then
		echo "0"
		exit 0
	else
		echo "1"
		exit 1
	fi
}

customization(){
	echo -e "  \n	Generating ignition files with appropriate settings.."
	INPUTFILES="server_custom.yml decoder_custom.yml"
	touch rootpw.secure
	touch waveletpw.secure
	chmod 0600 ./*.secure
	unset tmp_rootpw
	unset tmp_waveletpw
	# We now generate vars for our CSV key file
	# This is much cleaner than a large ignition file
    DOMAIN_ADMIN_PASSWORD="DomainAdminPasswordGoesHere"
    serverHostName="svr.${domain:-wavelet.allethrium}"
    if [[ "${developerMode}" -eq "1" ]]; then
        # Direct ignition sed
		echo -e "${RED}	Injecting dev branch into files..${NC}"
		repl="armelvil-working.tar.gz"
		sed -i "s|master.tar.gz|${repl}|g" ${INPUTFILES}
        developerFileName="developerMode.enabled"
        developerFileContent="DeveloperModeEnabled - will pull from working branch"
    else
        developerFileContent="DeveloperModeDisabled - will pull from master branch"
 	fi

	if [[ "$dev_flag" == "DEV" ]]; then
        # Direct ignition sed
		echo -e "${RED}		Targeting UltraGrid continuous build.\n		The continuous build might introduce experimental features, or less predictable behavior.\n${NC}"
		if [[ "$registry" == "$svr_ip" ]]; then
            echo "    Standalone deployment selected.."
	        if [[ "$patchMode" == "ON" ]]; then
	            # update this properly
	            echo "      Pulling UG build artefact from branch repo https://github.com/armelvil/UltraGrid"
                sed -i "s|\/download\/v[^ ]*|\/download\/continuous\/UltraGrid-continuous-x86_64.AppImage|g" ${INPUTFILES}
            else
                echo "      Pulling UG build artefact from upstream https://github.com/CESNET/UltraGrid"
	            sed -i "s|\/download\/v[^ ]*|\/download\/continuous\/UltraGrid-continuous-x86_64.AppImage|g" ${INPUTFILES}
            fi
		else
            echo "		LAN deployment selected.."
			sed -i "s|UltraGrid-1.10.5-x86_64.AppImage|UltraGrid-continuous-x86_64.AppImage|g" ${INPUTFILES}
			# Add a check here against the web UltraGrid continuous branch, print download/update message if it's out of date!
			echo -e "\n		${GREEN}Please ensure this file is kept updated!${NC}"
        fi
	else
		echo -e "\n		${GREEN}Tracking UltraGrid release build.\n${NC}"
		releaseVer="1.10.1"
	fi
	echo "      Generating wavelet_keys.csv"
	# Set default values if none
	svr_ip="${svr_ip:-192.168.1.32}"
	gateway="${gateway:-192.168.1.1}"
	subnet="${subnet:-255.255.255.0}"
	# Detect corporate mode (set by client_networks() or environment)
	if [[ "${WAVELET_CORPORATE:-0}" == "1" || "${corporateMode:-0}" == "1" ]]; then
		corporateMode=1
	fi
	if [[ "${corporateMode:-0}" == "1" ]]; then
		modeFilePath="/var/corporateMode.enabled"
		resolvContent="nameserver ${svr_dns:-9.9.9.9}\\nnameserver 9.9.9.9"
		printf "      Corporate mode: external DHCP/DNS assumed. Using DNS: %s\n" "${svr_dns:-9.9.9.9}"
	else
		modeFilePath="/var/isolationMode.enabled"
		resolvContent="nameserver ${svr_ip}\\nnameserver ${gateway}\\nnameserver 9.9.9.9"
		printf "      Isolation mode: Wavelet provides DHCP/DNS.\n"
	fi
	echo "      Appending remaining keys to wavelet_keys.csv.."
	# Build WiFi entries only if WiFi mode is enabled
	wifiEntries=""
	noWifiFlag=""
	if [[ "${enableWifi}" == "1" ]]; then
		wifiEntries="file,/var/home/wavelet/config/wifi_ssid,0600,true,,,${wifi_ssid}
file,/var/home/wavelet/config/wifi_bssid,0600,true,,,${wifi_bssid}
file,/var/home/wavelet/config/wifi_pw,0600,true,,,${wifi_password}
file,/var/home/wavelet-root/config/wifi_adminuser,0640,true,,,${wifi_deviceUser}
file,/var/home/wavelet-root/config/wifi_adminpw,0640,true,,,${wifi_devicePassword}
file,/var/home/wavelet-root/config/wifi_ipaddr,0640,true,,,${wifi_ipAddr}"
	else
		noWifiFlag="file,/var/no.wifi,0644,true,,,true"
	fi
cat >> ./ignition_files/wavelet_keys.csv << EOF
file,${modeFilePath},0644,,,,enabled
file,/etc/systemd/logind.conf.d/inhibit-suspend.conf,0644,,,,[Login]\nHandleLidSwitch=ignore
file,/var/secrets/ipaadmpw.secure,0600,true,,,${DOMAIN_ADMIN_PASSWORD:-DomainAdminPasswordGoesHere}
${noWifiFlag}
${wifiEntries}
file,/var/home/wavelet/config/networkdevice_userpass,0600,true,,,${NETWORK_DEVICE_PASSWORD:-password}
file,/var/${developerFileName},0644,true,,,${developerFileContent}
file,/var/timezone.txt,0600,true,,,${timeZone}
file,/etc/resolv.conf,0644,true,,,${resolvContent}
file,/etc/hostname,0644,true,,,${serverHostName}
file,/var/serverhostname.txt,0644,true,,,${serverHostName}
file,/etc/hosts,0664,true,,,127.0.0.1      localhost localhost.localdomain localhost4 localhost4.localdomain4\n::1            localhost localhost.localdomain localhost6 localhost6.localdomain6\n${svr_ip}  ${serverHostName}  ${serverHostName%%.*}
dir,/home/wavelet/.config,0755,,wavelet,wavelet,
dir,/home/wavelet/.config/systemd,0755,,wavelet,wavelet,
dir,/home/wavelet/.config/systemd/user,0755,,wavelet,wavelet,
dir,/home/wavelet/.config/systemd/user/default.target.wants,0755,,wavelet,wavelet,
dir,/home/wavelet/config,0755,,wavelet,wavelet,
dir,/home/wavelet/etcd,0755,,wavelet,wavelet,
dir,/home/wavelet/.ssh/secrets,0755,,wavelet,wavelet,
dir,/home/wavelet/config,0755,,wavelet,wavelet,
dir,/var/containers/registry,0700,,wavelet,wavelet,
dir,/home/wavelet/http,0755,,wavelet,wavelet,
dir,/home/wavelet/http-php/html,0755,,wavelet,wavelet,
dir,/home/wavelet/.local/share/containers/storage/volumes,0755,,wavelet,wavelet,
dir,/home/wavelet/http-php/nginx,0755,,wavelet,wavelet,
dir,/home/wavelet/http/ignition,0755,,wavelet,wavelet,
dir,/home/wavelet-root/config,0755,,wavelet-root,wavelet-root,
dir,/home/wavelet-root/.ssh/secrets,0755,,wavelet-root,wavelet-root,
dir,/var/lib/tftpboot,0755,,root,root,
dir,/etc/systemd/resolved.conf.d,0755,,,root,
dir,/etc/ssh/ssh_config.d,0755,,,root,
dir,/usr/local/backgrounds/sway,0755,,,root,
dir,/var/lib/systemd/linger/wavelet,0755,,,root,
dir,/var/lib/systemd/linger/wavelet-root,0755,,,root,
EOF
	# Customize launching kernel args, this will accelerate the bootup as NetworkManager-wait-online won't hang for 30+s
	echo "      Applying kernel args: ip=${svr_ip}::${gateway}:${subnet}:${serverHostName}::on"
	sed -i "s|ip=192.168.1.32::192.168.1.1:255.255.255.0:svr.wavelet.allethrium::on|ip=${svr_ip}::${gateway}:${subnet}:${serverHostName}::on|g" ${INPUTFILES}
	mkdir -p var
	for file in ${INPUTFILES}; do
	  cat $file > var/generated_$file
	done
	echo -e "\n${GREEN} ***Customization complete, moving to injecting configurations to CoreOS images for initial installation..*** \n${NC}"
}

interactive_setup() {
	echo -e "Is the target network configured with an active gateway, and are you prepared to deal with downloading approximately 4gb of initial files?"
	read -p "Continue? (Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit
	if [[ "${WAVELET_CORPORATE:-0}" == "1" ]]; then
		echo -e "Corporate Mode requested via environment. Skipping isolated prompt and configuring for client/corporate network."
		client_networks
	else
		echo -e "Will this system run on an isolated network?"
		read -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || client_networks || echo -e "${GREEN}System configured for isolated, authoritative mode." && isoMode="mode=iso"
	fi
	echo -e "Target UltraGrid Continuous build (best used with Developer Mode)?"
	read -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] && dev_flag="DEV"

	# WiFi mode prompt
	echo -e "\nEnable WiFi mode? This will configure the system to connect to a WiFi access point."
	read -p "(Y/N): " confirm
	if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
		enableWifi="1"
		echo -e "\nPlease input your WiFi configuration:"
		read -p "WiFi SSID: " wifi_ssid
		read -p "WiFi BSSID (MAC address, e.g. AA:BB:CC:DD:EE:FF): " wifi_bssid
		read -p "WiFi PSK password: " wifi_password
		read -p "WiFi Access Point IP address: " wifi_ipAddr
		read -p "WiFi AP admin username: " wifi_deviceUser
		read -p "WiFi AP admin password: " wifi_devicePassword
	else
		echo -e "\nWiFi mode disabled. The system will use wired networking."
	fi

	# domainname
	# Iterate over the array of users and set passwords for each
	init_users_yaml
	# Define users, you can edit this to set more
	users=("wavelet-root" "wavelet")
	for user in "${users[@]}"; do
		if [[ $(set_pw "${user}") -ne 0 ]]; then
			echo -e "Failed to set a password for ${user}."
			exit 1
		else
			echo -e "	Set password for ${user}"
			echo -e "	Generating SSH public key for ${user}..\n"
			ssh-keygen -t ed25519 -C "${user}@wavelet.allethrium" -f "${user}-ssh"
			echo -e "	Generating YAML block for user..\n"
			cp users_yaml "${user}_yaml.yml"
			generate_user_yaml "${user}"
			# Now we add the user YAML block to the server ignition, preserving the tag as we go..
			echo -e "\nAdding generated YAML block to ignition file for ${user}..\n"
			f2="$(<${user}_yaml.yml)"
			input_files_arr="(${INPUTFILES})"
			for file in "${input_files_arr[@]}"; do
				if [ -f "$file" ]; then
					awk -vf2="$f2" '/#ADD_USER_YAML_HERE/{print f2;print;next}1' "${file}" > tmp && mv tmp "${file}"
					echo -e "	YAML block for ${user} added to ignition file ${file}..\n"
				else
					echo "	Warning: ${file} does not exist or is inaccessible!"
				fi
			done
		fi
	done
	customization
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
		echo -e "	Adding generated YAML block to ignition file for ${user}.."
		f2="$(<${user}_yaml.yml)"
		input_files_arr=(${INPUTFILES})
		for file in "${input_files_arr[@]}"; do
			if [ -f "$file" ]; then
				awk -vf2="$f2" '/#ADD_USER_YAML_HERE/{print f2;print;next}1' "${file}" > tmp && mv tmp "${file}"
				echo -e "	YAML block for ${user} added to ignition file ${file}.."
			else
				echo "	Warning: ${file} does not exist or is inaccessible!"
			fi
		done
	done

	# Report WiFi mode status to the user
	if [[ "${enableWifi}" == "1" ]]; then
		echo -e "\n${GREEN}	WiFi mode ENABLED. Wireless configuration will be written to ignition files.${NC}"
	else
		echo -e "\n${RED}	WiFi mode DISABLED. The system will use wired networking only.${NC}"
	fi

  customization
}

print_help(){
	echo -e "Initial wavelet install help prompts:"
	echo -e "Lab Mode: -l, --lab\nEnables a streamlined automatic setup for quicker testing"
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
		echo -e "${GREEN}		Registry running and responding to curl!${NC}"
		registry="$ip_part"
	else
		echo -e "${RED}		Registry not responding, please verify your settings..${NC}"
		exit 1
	fi
}

get_publicinterface(){
	# Tries to get the active network interface, may sometimes get it wrong.
	iface_route="$(ip -4 route show default | sort -nk1,1 | head -n1)"
	if [[ -z "$iface_route" ]]; then
		echo "No default IPv4 route found. Cannot determine public interface."
		exit 1
	fi
  iface=$(echo "$iface_route" | awk '{print $5}')
	ip="$(nmcli -t -f IP4.ADDRESS dev show $iface | awk -F: '{print $2}' |cut -d'/' -f1 )"
}

download_wavelet_git(){
	# Runs only if we are using LAN Deployment
	if [[ "${developerMode}" -eq "1" ]]; then
    GH_BRANCH="armelvil-working"
  else
    GH_BRANCH="master"
  fi
	if curl -s -L -o "$HOME/.config/var/www/$GH_BRANCH.tar.gz" \
		"https://github.com/Allethrium/wavelet/archive/refs/heads/$GH_BRANCH.tar.gz"; then
			echo "		Acquired wavelet tarball, proceeding.."
	else
			echo "		Error downloading wavelet tarball!  aborting!"
			echo "		Please check this user's write permissions to ~/.config/var/www"
			exit 1
	fi
}


####
#
# Main
#
####


waveletdir="$(pwd)"
#exec >$waveletdir/logs/server_bootstrap.log 2>&1
secActive=0
echo "Input Args: "; echo "${@}"
timeZone=""

for i in "$@"
	do
		case $i in
			-l|--lab)
				echo "Labmode enabled, skipping prompts.  Please ensure your commandline contains all necessary arguments!"; labMode="True";
				;;
			-d|--dev)
				echo -e "${RED}Dev mode enabled, switching git tree to working branch${NC}"	;	developerMode="1";
				;;
			-h|--help)
				print_help;	exit 0
				;;
			-p=*|--password=*|--pass=*)
				PASSWORD=${i#*=}; echo -e "Password defined for BOTH user accounts in labmode as: ${PASSWORD}";
				;;
			-ws=*|--wifissid=*)
				wifi_ssid=${i#*=}; echo -e "WiFi SSID defined as: ${wifi_ssid}";
				;;
			-wb=*|--wifibssid=*)
				wifi_bssid=${i#*=}; echo -e "WiFi BSSID/MAC defined as: ${wifi_bssid}";
				;;
			-wip=*|--wifiapip=*)
				wifi_ipAddr=${i#*=}; echo -e "WiFi Access Point IP defined as: ${wifi_ipAddr}"
				;;
			-wp=*|--wifipass=*)
				wifi_password=${i#*=}; echo -e "WiFi WPA PSK defined as: ${wifi_password} (will have no effect with Security layer active!)";
				;;
			-wap=*|--wifiappass=*)
				wifi_devicePassword=${i#*=}; echo -e "WiFi AP Password: ${wifi_devicePassword}";
				;;
			-wau=*|--wifiapuser=*)
				wifi_deviceUser=${i#*=}; echo -e "WiFi AP User: ${wifi_deviceUser}";
				;;
			--enablewifi)
				enableWifi="1"; echo -e "WiFi mode enabled. WiFi parameters will be written to ignition files.";
				;;
			--domain=*)
				domain=${i#*=}; echo -e "Target domain: ${domain}";
				;;
			-ugd|--ugdev|--ugcontinuous)
				dev_flag="DEV";
				;;
			-4=*|--ip4subnet=*)
				ip4=${i#*=}; echo -e "WIP! IPv4 Subnet (CIDR) defined as: ${ip4}";
				;;
			-6=*|--ipv6subnet=*)
				ip6=${i#*=}; echo -e "WIP! IPv6 Subnet fefined as: ${ip6}";
				;;
			-ip=*|--serverip=*)
				svr_ip=${i#*=}; echo -e "WIP! Server Static IPv4 defined as ${svr_ip}}";
				;;
			-g=*|--servergateway=*)
				svr_gw=${i#*=}; echo -e "WIP! Server IPv4 gateway defined as ${svr_gw}";
				;;
			-dns=*|--serverdns=*)
				svr_dns=${i#*=}; echo -e "WIP! Server IPv4 dns defined as ${svr_dns}";
				;;
     	    -reg=*|--localregistry=*)
				registry=${i#*=}; echo -e "Local registry defined as IP ${registry}";
				;;
            -b|--patched)
            	patchMode="ON"; echo -e "Pulling from patched UG branch";
            	;;
            -t=*|--timezone=*)
            	timeZone=${i#*=}; echo -e "Timezone set to $timeZone (default to America/New_York if empty)";
            	;;
			*)
				echo "bad input argument: $i";
				;;
		esac
done
if [[ -z "$timeZone" ]]; then
	timeZone="America/New_York"
fi
requiredOptions=("PASSWORD" "domain" "svr_gw")
for opt in "${requiredOptions[@]}"; do
	echo "Required option $opt set!"
	if [[ -z "${!opt}" ]]; then
		echo -e "\n\n${RED} ERROR:	The install option '$opt' must be defined!
		\n	Aborting installation, as process will fail without these data.${NC}\n\n"
		exit 1
	fi
done

if [[ $domain == *".local" ]]; then
	echo -e "\n${RED}.local TLD domain is reserved for mDNS, please select another domain or subdomain, preferably one from your organization's domain"
	echo -e "${RED}Failure to do this may result in unpredictable behavior with local name resolution.${NC}"
	exit 1
fi

echo -e "\n	Copying base ignition files for customization.."
cp ignition_files/ignition_server.yml ./server_custom.yml
cp ignition_files/ignition_decoder.yml ./decoder_custom.yml
ls -l ./*.yml
# remove old iso files
rm -rf "${HOME}"/Downloads/wavelet_server.iso
rm -rf "${HOME}"/Downloads/wavelet_decoder.iso

if [[ -n "$registry" ]]; then
  echo "	We have defined a local registry for faster setup.  Wavelet will pull OCI layers from this registry."
  echo "	NOTE:  Installation will FAIL with an out of date Server/Client image, or if it does not exist!"
  echo "	NOTE:  The registry must be accessible from the wavelet subnet!"
  echo "	NOTE:  Activating the registry option implies a functional local HTTPD server as well - please ensure it's operational!"
  echo "	This means this install option should be activated on the deployment machine you intend to serve the images"
  # We would verify the registry format here to ensure it's a valid type, script will break if not valid format
  # These get an IP from the local interface, useful in automation later
  #get_publicinterface
  validate_ip_port "$registry"
  INPUTFILES="server_custom.yml decoder_custom.yml"
  rm -f ignition_files/wavelet_keys.csv
  echo "type,path,mode,overwrite,owner,group,content" >> ignition_files/wavelet_keys.csv
  echo "file,/var/wavelet_registry.txt,0644,true,,,${registry}" >> ignition_files/wavelet_keys.csv
  echo "file,/var/wavelet_registry_hostname.txt,0644,true,,,${ip} $(hostname)"  >> ignition_files/wavelet_keys.csv
  echo "file,/var/httpd_lan.txt,0644,true,,,${registry}:8080"  >> ignition_files/wavelet_keys.csv
  sed -i "s|192.168.1.32:5000|$registry|g" $INPUTFILES
  sed -i "s|192.168.1.32:8080|${registry%%:*}:8080|g" $INPUTFILES
  sed -i "s|https://github.com/Allethrium/wavelet/archive/refs/heads/master.tar.gz|http://${registry%%:*}:8080/master.tar.gz|g" $INPUTFILES
  # Set UltraGrid to local LAN server, which ought to have both builds if build_registry.sh worked as it should.
  sed -i "s|https://github.com/CESNET/UltraGrid/releases/download/v1.10.5/UltraGrid-1.10.5-x86_64.AppImage|http://${registry%%:*}:8080/UltraGrid-1.10.5-x86_64.AppImage|g" $INPUTFILES
  download_wavelet_git
else
  echo "  Local registry option not defined, running standalone setup.."
  registry="${svr_ip}"
  INPUTFILES="server_custom.yml decoder_custom.yml"
  rm -f ignition_files/wavelet_keys.csv
  # We still set the registry values, however they are always going to be the wavelet server IP in this case.
  echo "type,path,mode,overwrite,owner,group,content" >> ignition_files/wavelet_keys.csv
  echo "file,/var/wavelet_registry.txt,0644,true,,,${registry}" >> ignition_files/wavelet_keys.csv
  echo "file,/var/wavelet_registry_hostname.txt,0644,true,,,${ip} svr.$domain"  >> ignition_files/wavelet_keys.csv
  echo "file,/var/httpd_lan.txt,0644,true,,,${httpd_lan:-192.168.1.32:8080}"  >> ignition_files/wavelet_keys.csv
  sed -i "s|192.168.1.32:5000|$registry|g" $INPUTFILES
  sed -i "s|192.168.1.32:8080|${registry%%:*}:8080|g" $INPUTFILES
  # Note the nameserver must later be removed because it will interfere with DNS during spinup
  echo "    Setting nameserver to gateway 9.9.9.9 for simple DNS resolution during initial setup.."
  sed -i "s|#nameserver|- nameserver=9.9.9.9|g" $INPUTFILES
fi

if [[ ${labMode} == "True" ]]; then
	automatic_setup
else
	interactive_setup
fi

echo "	Removing old ignition files and cleaning up.."
mv ${INPUTFILES} ignition_files/
rm -rf ignition_files/*.ign
rm -rf *.secure
rm -rf users_yaml dev.flag
rm -rf *.yml
echo -e "${GREEN}	Calling coreos_installer.sh to generate ISO images."
echo -e "	You will need to burn the generated server ISO to USB/SD cards for initial boot.${NC}"
./coreos_installer.sh "${developerMode}" "${isoMode}"