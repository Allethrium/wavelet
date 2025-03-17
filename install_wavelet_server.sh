#!/bin/bash

# This script bootstraps your initial wavelet server based upon input variables.
# The server can run in authoritative mode for an isolated network, or subordinate mode if you are placing it on a network with an active DHCP server for instance.
# It's generally designed to be run isolated and handle its own DHCP/DNS.

RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"

client_networks(){
	echo -e "\nSystem configured to be run on a larger network.\n"
	echo -e "Please input the system's gateway IP address, and subnet mask\n"
	read -p "Gateway IPv4 Address: " GW
	read -p "Subnet Mask CIDR I.E 24 for class C network: " SN
	# Validate user input
	if ! [[ $GW =~ ^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; then
				echo -e "Invalid Gateway IPv4 Address format. Please use the format A.B.C.D."
				return
	fi
		if ! [[ $SN =~ ^[0-9]+$ ]]; then
		echo -e "Invalid Subnet Mask CIDR format. Please use only digits."
		return
	fi
	if ! [[ $SN -ge 16 && $SN -le 32 ]]; then
		echo -e "Subnet Mask CIDR value must be between 16 and 32."
		return
	fi
		grIP="${GW}/${SN}"
		if [[ SN > 28 ]]; then
				echo -e "Subnet mask is too small for a Wavelet system, we need at least 32 host IP's to be available!"
		elif [[ SN < 24 ]]; then
				echo -e "Subnet mask seems very large - please note this system would work best on a more isolated network in authoritative mode!\n
						effective operation cannot be guaranteed when taking into account issues on larger networks with congestion, security appliances etc.\n"
		else
				echo -e "Subnet mask selected, continuing.."
				hostname_domain
		fi
		#echo -e "IPv6 not supported at the current time."
	# SED for 192.168.1.1 and set ${GW}
	sed -i 's/192.168.1.1/${GW}/g' ${INPUTFILES}
	# SED for subnet mask and set appropriately
	sed -i 's/255.255.255.0/${SN}/g' ${INPUTFILES}
	# SED for nameserver and remove args
	sed -i 's/- nameserver/d' ${INPUTFILES}
	# SED to tell ignition that we aren't running in isolation mode, therefore DNSMasq should not be started via a FileExists arg in the systemD unit.
	sed -i 's/isolationMode.enabled/isolationMode.disabled/g' ${INPUTFILES}
	# FQDN would now be set from the DNS/DHCP server in the environment.  This also obviously disables network sense, TFTPBOOT and PXE.
	# The assumption here is that an engineer would have already configured these services elsewhere, I can write some automation scripts later
	# if this proves to be a need.
	dnsmasq_no_dhcp
}

dnsmasq_no_dhcp(){
	# This function should configure Server Ignition to pull a different dnsmasq.conf which provides PXEboot but disables DHCP functionality - if that is workable pending further testing.
	sed -i 's/Allethrium/wavelet/master/webfiles/root/etc/dnsmasq.conf/Allethrium/wavelet/master/webfiles/root/etc/dnsmasq_nodhcp.conf/g' ${INPUTFILES}
	echo -e "\n\n${RED}******** IMPORTANT ********\n\nYou must configure your pre-existing DHCP server to forward PXE boot requests to the wavelet server!\nPlease refer to the comment lines below for examples..\n${NC}"
	echo -e "\nDHCPD:\nEdit dhcpd.conf and ensure these lines are present:\nnext-server 192.168.0.20;\nfilename 'pxelinux.0';\n"
	echo -e "\nDNSMASQ:\n"
	echo -e "\nFor other DHCP servers, please refer to their respective documentation."
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
	# SED for 192.168.1.32 and replace with ${STATICIP} in server.ign, dnsmasq.conf, etcd, etc
	INPUTFILES="server_custom.yml decoder_custom.yml"
	sed -i "s/192.168.1.32/${STATICIP}/g" ${INPUTFILES}
	INPUTFILES=./webfiles/root/usr/local/bin/build_ug.sh
	sed -i "s/192.168.1.32/${STATICIP}/g" ${INPUTFILES}
	INPUTFILES=./webfiles/root/etc/dnsmasq.conf
	sed -i "s/192.168.1.32/${STATICIP}/g" ${INPUTFILES}
	# SED for svr.wavelet.local and replace with ${FQDN} in server.ign, dnsmasq.conf, etcd, etc
	sed -i "s/192.168.1.32/${FQDN}/g" ${INPUTFILES}
	INPUTFILES=./webfiles/root/etc/dnsmasq.conf
	sed -i "s/192.168.1.32\/${FQDN}/g" ${INPUTFILES}
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
		echo -e "wavelet-root user, setting UID to 9337"
		uid="9337"
		group1="wheel"
		group2="sudo"
		sed -i "s|#- GROUPGOESHERE|- $group1\n        #- GROUPGOESHERE|" ${user_yaml}
		sed -i "s|#- GROUPGOESHERE|- $group2\n        #- GROUPGOESHERE|" ${user_yaml}
	elif [[ "${name}" = "wavelet" ]]; then
		echo -e "wavelet user, setting UID to 1337"
		uid="1337"
	else 
		echo -e "User ID not preset, system will assign them, bear in mind this might go away if we get to implementing IdM"
	fi
	if [[ -n ${uid} ]]; then
		echo -e
		sed -i "s|USERNAMEGOESHERE|USERNAMEGOESHERE\n      uid: $uid|" ${user_yaml}
	fi
	# We use a pipe instead of a / here, because the pubkeys and passwords hashes may contain a / and therefore escape the rest of the data.
	echo -e "Working on user ${name}\n"
	sed -i "s|#ADD_USER_YAMLHERE|""|" ${user_yaml}
	sed -i "s|PASSWORDGOESHERE|$password_hash|" ${user_yaml}
	sed -i "s|PUBKEYGOESHERE|$ssh_authorized_keys|" "${user_yaml}"
	sed -i "s|USERNAMEGOESHERE|$name|" ${user_yaml}
	sed -i "s|USERHOMEDIR|$name|" ${user_yaml}
	echo -e "\nGenerated user YML\n"
	cat ${user_yaml}
	echo -e "\n\n"
}

set_pw(){
	local attempts=3
	local success=0
	local user=$1
	local tmp_pw=""

	while [[ ${success} -ne 1 ]] && [[ ${attempts} -gt 0 ]]; do
		echo -e >&2 "			${GREEN}Remaining attempts: ${attempts}${NC}"
		read -srp "		Please input a password for ${user}:`echo $'\n	-'`" tmp_pw
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
			read -srp "`echo $'\n'`	Please input the password again to verify for ${user}:`echo $'\n	-'`" tmp_pw2
			if [[ "${tmp_pw}" == "${tmp_pw2}" ]]; then
				echo -e >&2 "`echo $'\n-------->'`		${GREEN}Passwords match!  Continuing..${NC}"
				mkpasswd --method=yescrypt ${tmp_pw} > ${user}.pw.secure
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

enable_security(){
	echo -e "\nEnabling security layer flag in server ignition..\n"
	echo -e "Note: Security layer implies the following:\nLocal Domain Controller to handle authentication and certificates\nEAP-TTLS for WiFi\nTLS certificates on web server issued from Domain Controller\nEtcd secured with domain certificates\n"
	echo -e "These additional features may complicate troubleshooting and should only be used in a stable production build.  If you're running Wavelet in a lab, you may wish to disable them during your testing."
	repl="prod.security.enabled"
	sed -i "s|/var/prod.security.disabled|${repl}|g" ${INPUTFILES}
	echo -e "\nThe FreeIPA domain will control services and certificates.  Please ensure you store the password for the domain controller in a safe place, and in an organized fashion.\n"
	read -p "\nSet a password for the freeIPA Administrator account.  If you set less than 8 characters, the domain controller process will fail!!!" domain_pw
	sed -i "s|DomainAdminPasswordGoesHere|${domain_pw}|g" ${INPUTFILES}
}

customization(){
	echo -e "Generating ignition files with appropriate settings.."
	INPUTFILES="server_custom.yml decoder_custom.yml"
	touch rootpw.secure
	touch waveletpw.secure
	chmod 0600 *.secure
	unset tmp_rootpw
	unset tmp_waveletpw

	init_users_yaml
	# Define users, you can edit this to set more
	users=("wavelet-root" "wavelet")

	# Iterate over the array of users and set passwords for each
	for user in "${users[@]}"; do
		if [[ $(set_pw "${user}") -ne 0 ]]; then
			echo -e "Failed to set a password for ${user}."
			exit 1
		else
			echo -e "	Set password for ${user}"
			echo -e "	Generating SSH public key for ${user}..\n"
			ssh-keygen -t ed25519 -C "${user}@wavelet.local" -f ${user}-ssh
			echo -e "	Generating YAML block for user..\n"
			cp users_yaml ${user}_yaml.yml
			generate_user_yaml ${user}
			# Now we add the user YAML block to the server ignition, preserving the tag as we go..
			echo -e "	Adding generated YAML block to ignition file for ${user}..\n"
			f2="$(<${user}_yaml.yml)"
			input_files_arr=($INPUTFILES)
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

	echo -e "Ignition customization completed, and .ign files have been generated.\n"

	# We set DevMode disabled here, even though it's enabled by default in ignition
	sed -i "s|/var/developerMode.enabled|/var/developerMode.disabled|g" ${INPUTFILES}
	sed -i "s|DeveloperModeEnabled - will pull from working branch (default behavior)|DeveloperModeDisabled - pulling from master|g" ${INPUTFILES}
	# Check for developermode flag so we pull from working branch rather than continually pushing messy and embarassing broken commits to the main branch..
	if [[ "${developerMode}" -eq "1" ]]; then
		echo -e "${RED}Injecting dev branch into files..\n${NC}"
		repl="https://raw.githubusercontent.com/Allethrium/wavelet/armelvil-working"
		sed -i "s|https://github.com/Allethrium/wavelet/raw/master|${repl}|g" ${INPUTFILES}
		# Yep I set it enabled again here, if the devmode arg is on.
		sed -i "s|/var/developerMode.disabled|/var/developerMode.enabled|g" ${INPUTFILES}
		sed -i "s|DeveloperModeDisabled - pulling from master|DeveloperModeEnabled - will pull from working branch|g" ${INPUTFILES}
		sed -i "s|https://raw.githubusercontent.com/Allethrium/wavelet/master|${repl}|g" ${INPUTFILES}
	fi
	if [[ $(cat dev_flag) == "DEV" ]]; then
		echo -e "\n${RED}	Targeting UltraGrid continuous build for initial startup.\n	Please bear in mind that although this comes with additional features,\n	The continuous build might introduce experimental features, or less predictable behavior.\n${NC}"
		sed -i "s|CESNET/UltraGrid/releases/download/v1.9.8/UltraGrid-1.9.8-x86_64.AppImage|CESNET/UltraGrid/releases/download/continuous/UltraGrid-continuous-x86_64.AppImage|g" ${INPUTFILES}
	else
		echo -e "\n${GREEN}Tracking UltraGrid release build.\n${NC}"
	fi
	
	# WiFi settings
	# changed to mod ignition files w/ inline data for the scripts to call, this way I don't publish wifi secrets to github.
	INPUTFILES="server_custom.yml decoder_custom.yml"
	# Include flag to enable security layer
	echo -e "\n${RED}Enable security layer?${NC}"
	read -p "(Y/N)" confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || secActive=0; echo -e "\nSecurity layer not active.  This is NOT recommended for a production deployment!" || enable_security
	echo -e "Moving on to WiFi settings"
	echo -e "Security layer bit set to: ${secActive}"
	echo -e "\nIf your Wifi AP hasn't yet been configured, please do so now, as the installer will wait for your input\n"
	read -p "		Please input the SSID of your configured wireless network:  " wifi_ssid
	read -p "		Please input the first three elements of the WiFi BSSID / MAC address, colon delimited like so AA:BB:CC:  " wifi_bssid
	# We won't want to set a wifi PSK if we are using enterprise security on our devices.
	if [[ ${secActive} = 0 ]]; then
	read -p "		Please input the configured password for your WiFi SSID:  " wifi_password
	else
		wifi_password="Not used, security handled via RADIUS."
	fi

	repl=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<< "${wifi_ssid}")
	sed -i "s/SEDwaveletssid/${repl}/g" ${INPUTFILES}

	repl=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<< "${wifi_bssid}")
	sed -i "s/SEDwaveletbssid/${repl}/g" ${INPUTFILES}

	repl=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<< "${wifi_password}")
	sed -i "s/SEDwaveletwifipassword/${repl}/g" ${INPUTFILES}
	echo -e "\n${GREEN} ***Customization complete, moving to injecting configurations to CoreOS images for initial installation..*** \n${NC}"
}

interactive_setup() {
	echo -e "Is the target network configured with an active gateway, and are you prepared to deal with downloading approximately 4gb of initial files?"
	read -p "Continue? (Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit
	echo -e "Will this system run on an isolated network?"
	read -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || client_networks || echo -e "${GREEN}System configured for isolated, authoritative mode." && isoMode="mode=iso"
	echo -e "Target UltraGrid Continuous build (best used with Developer Mode)?"
	read -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] && echo "DEV" > dev_flag || echo "" > dev_flag
	customization
}

automatic_setup() {
	# Streamlined automatic setup.  I need to work out how to define both users w/ different passwords in the forEach loop, though.
	if [[ -z ${PASSWORD} || -z ${wifi_ssid} || -z ${wifi_bssid} ]]; then
		echo "Automatic setup requires minimum valid arguments, please ensure you've provided a password, wifi SSID and BSSID at the minimum. more if you need further customizations."
		print_help
	fi
	INPUTFILES="server_custom.yml decoder_custom.yml"
	init_users_yaml
	users=("wavelet-root" "wavelet")
	for user in "${users[@]}"; do
		mkpasswd --method=yescrypt "${PASSWORD}" > ${user}.pw.secure
		ssh-keygen -t ed25519 -C "${user}@wavelet.local" -N '' <<< $'\ny' >/dev/null 2>&1
		cp users_yaml ${user}_yaml.yml
		generate_user_yaml ${user}
		echo -e "	Adding generated YAML block to ignition file for ${user}..\n"
		f2="$(<${user}_yaml.yml)"
		input_files_arr=($INPUTFILES)
		for file in "${input_files_arr[@]}"; do
			if [ -f "$file" ]; then
				awk -vf2="$f2" '/#ADD_USER_YAML_HERE/{print f2;print;next}1' "${file}" > tmp && mv tmp "${file}"
				echo -e "	YAML block for ${user} added to ignition file ${file}..\n"
			else
				echo "	Warning: ${file} does not exist or is inaccessible!"
			fi
		done
	done
	echo -e "Ignition customization completed, and .ign files have been generated."
	sed -i "s|/var/developerMode.enabled|/var/developerMode.disabled|g" ${INPUTFILES}
	sed -i "s|DeveloperModeEnabled - will pull from working branch (default behavior)|DeveloperModeDisabled - pulling from master|g" ${INPUTFILES}
	if [[ "${developerMode}" -eq "1" ]]; then
		echo -e "${RED}Injecting dev branch into files..\n${NC}"
		repl="https://raw.githubusercontent.com/Allethrium/wavelet/armelvil-working"
		sed -i "s|https://github.com/Allethrium/wavelet/raw/master|${repl}|g" ${INPUTFILES}
		sed -i "s|/var/developerMode.disabled|/var/developerMode.enabled|g" ${INPUTFILES}
		sed -i "s|DeveloperModeDisabled - pulling from master|DeveloperModeEnabled - will pull from working branch|g" ${INPUTFILES}
		sed -i "s|https://raw.githubusercontent.com/Allethrium/wavelet/master|${repl}|g" ${INPUTFILES}
	fi
	if [[ $(cat dev_flag) == "DEV" ]]; then
		echo -e "\n${RED}	Targeting UltraGrid continuous build for initial startup.\n	Please bear in mind that although this comes with additional features,\n	The continuous build might introduce experimental features, or less predictable behavior.\n${NC}"
		sed -i "s|CESNET/UltraGrid/releases/download/v1.9.8/UltraGrid-1.9.8-x86_64.AppImage|CESNET/UltraGrid/releases/download/continuous/UltraGrid-continuous-x86_64.AppImage|g" ${INPUTFILES}
	else
		echo -e "\n${GREEN}Tracking UltraGrid release build.\n${NC}"
	fi
	if [[ ${secActive} = 0 ]]; then
			echo "Security layer inactive.  This installation will not be hardened and is not recommended for a production deployment.  Use at your own risk."
	else
		wifi_password="DISABLED in secure mode, please check documentation."
		enable_security
	fi
		repl=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<< "${wifi_ssid}")
		sed -i "s/SEDwaveletssid/${repl}/g" ${INPUTFILES}
		repl=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<< "${wifi_bssid}")
		sed -i "s/SEDwaveletbssid/${repl}/g" ${INPUTFILES}
		repl=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<< "${wifi_password}")
		sed -i "s/SEDwaveletwifipassword/${repl}/g" ${INPUTFILES}
		echo -e "\n${GREEN} ***Customization complete, moving to injecting configurations to CoreOS images for initial installation..*** \n${NC}"
}


print_help(){
	echo -e "Initial wavelet install help prompts:"
	echo -e "Lab Mode: -l, --lab\nEnables a streamlined automatic setup for quicker testing"
	echo -e "Developer Mode: -d, --dev\nPulls from development branch on git."
	echo -e "-ugd=, --ugdev, --ugcontinuous=\nTargets the continuous build of UltraGrid for newer and possibly less stable features."
	echo -e "-p=, --pass=,--password=\nSets the wavelet-root password"
	echo -e "-ws=, --wifissid=\nSets the preconfigured WiFi SSID"
	echo -e "-wb=, --wifibssid=\nSets the preconfigured WiFi BSSID (WiFi Access Point's MAC address)"
	echo -e "-wp=, --wifipass=\nSets the preconfigured WiFi PSK for use in WPA2/WPA2 networks.  Less secure than enabling security layer."
	echo -e "-4=, --ip4subnet=\nDefines the target IP4 subnet in CIDR notation (I.E 192.168.0.0/24)"
	echo -e "-6=, --ip6subnet=\nDefines the target IP6 subnet in CIDR notation (I.E 2001:db8:1:2::/64)"
	echo -e "-ip=, --serverip=\nDefines the server static IP4 address (I.E 192.168.0.2)"	
	echo -e "-g=, --servergateway=\nDefines the server static IP4 gateway (I.E 192.168.0.1)"	
	echo -e "-dns=, --serverdns=\nDefines the server DNS forwarder (I.E 192.168.0.53)"	
	exit 0
}

####
#
# Main
#
####

secActive=0
echo "Input Args: ${@}"

for i in "$@"
	do
		case $i in
			-l|--lab)																		echo "Labmode enabled, skipping prompts.  Please ensure your commandline contains all necessary arguments!"; labMode="True";
			;;
			-d|--dev)																		echo -e "${RED}Dev mode enabled, switching git tree to working branch${NC}"	;	developerMode="1";
			;;
			-h|--help)																	print_help;	exit 0
			;;
			-p=*|--password=*|--pass=*)									PASSWORD=${i#*=}; echo -e "Password defined for BOTH user accounts in labmode as: ${PASSWORD}";
			;;
			-s|--sec|--security)												echo -e "WIP! Security layer is enabled!"; secActive=1
			;;
			-ws=*|--wifissid=*)													wifi_ssid=${i#*=}; echo -e "WiFi SSID defined as: ${wifi_ssid}";
			;;
			-wb=*|--wifibssid=*)												wifi_bssid=${i#*=}; echo -e "WiFi BSSID/MAC defined as: ${wifi_bssid}";
			;;
			-wp=*|--wifipass=*)													wifi_password=${i#*=}; echo -e "WiFi WPA PSK defined as: ${wifi_password} (will have no effect with Security layer active!)";
			;;
			-ugd|--ugdev|--ugcontinuous)								dev_flag="DEV";
			;;
			-4=*|--ip4subnet=*)													ip4=${i#*=}; echo -e "WIP! IPv4 Subnet (CIDR) defined as: ${ip4}";
			;;
			-6=*|--ipv6subnet=*)												ip6=${i#*=}; echo -e "WIP! IPv6 Subnet fefined as: ${ip6}";
			;;
			-ip=*|--serverip=*)													svr_ip=${i#*=}; echo -e "WIP! Server Static IPv4 defined as ${svr_ip}}";
			;;		
			-g=*|--servergateway=*)											svr_gw=${i#*=}; echo -e "WIP! Server IPv4 gateway defined as ${svr_gw}";
			;;		
			-dns=*|--serverdns=*)												svr_dns=${i#*=}; echo -e "WIP! Server IPv4 dns defined as ${svr_dns}";
			;;											
			*)																					echo "bad input argument: $i";
			;;
		esac
done

echo -e "\nCopying base ignition files for customization.."
cp ignition_files/ignition_server.yml server_custom.yml
cp ignition_files/ignition_decoder.yml decoder_custom.yml
# remove old iso files
rm -rf $HOME/Downloads/wavelet_server.iso
rm -rf $HOME/Downloads/wavelet_decoder.iso

if [[ ${labMode} == "True" ]]; then
	automatic_setup
else
	interactive_setup
fi

echo "Removing old ignition files and cleaning up.."
rm -rf ignition/*.ign
rm -rf *.secure
rm -rf users_yaml dev.flag
echo -e "${GREEN}Calling coreos_installer.sh to generate ISO images.  You will then need to burn them to USB/SD cards.${NC}"
./coreos_installer.sh "${developerMode}" "${isoMode}"