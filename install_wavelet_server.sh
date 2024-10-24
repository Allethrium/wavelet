#!/bin/bash

# This script bootstraps your initial wavelet server based upon input variables.
# The server can run in authoritative mode for an isolated network, or subordinate mode if you are placing it on a network with an active DHCP server for instance.
# It's generally designed to be run isolated and handle its own DHCP/DNS.

for i in "$@"
	do
		case $i in
			*d*)	echo -e "\nDev mode enabled, switching git tree to working branch\n"	;	developerMode="1"
			;;
			h)		echo -e "\nSimple command line switches:\n D for developer mode, will clone git from ARMELVIL working branch for non-release features.\n";	exit 0
			;;
			*)		echo -e "\nBad input argument, ignoring"
			;;
		esac
done

echo -e "Is the target network configured with an active gateway, and are you prepared to deal with downloading approximately 4gb of initial files?"
read -p "Continue? (Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit
echo -e "Continuing, copying base ignition files for customization.."
cp ./ignition_files/ignition_server.yml ./server_custom.yml
cp ./ignition_files/ignition_decoder.yml ./decoder_custom.yml
# IPv6 mode eventually? Just to be snazzy?
# remove old iso files
rm -rf $HOME/Downloads/wavelet_server.iso
rm -rf $HOME/Downloads/wavelet_decoder.iso

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
	echo -e "\n\n******** IMPORTANT ********\n\nYou must configure your pre-existing DHCP server to forward PXE boot requests to the wavelet server!\nPlease refer to the comment lines below for examples..\n"
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
INPUTFILES="server_custom.yml encoder_custom.yml decoder_custom.yml"
sed -i "s/192.168.1.32/${STATICIP}/g" ${INPUTFILES}
INPUTFILES=./webfiles/root/usr/local/bin/build_ug.sh
sed -i "s/192.168.1.32/${STATICIP}/g" ${INPUTFILES}
INPUTFILES=./webfiles/root/etc/dnsmasq.conf
sed -i "s/192.168.1.32/${STATICIP}/g" ${INPUTFILES}

# SED for svr.wavelet.local and replace with ${FQDN} in server.ign, dnsmasq.conf, etcd, etc
INPUTFILES="server_custom.yml encoder_custom.yml decoder_custom.yml"
sed -i "s/192.168.1.32/${FQDN}/g" ${INPUTFILES}
INPUTFILES=./webfiles/root/etc/dnsmasq.conf
sed -i "s/192.168.1.32\/${FQDN}/g" ${INPUTFILES}
customization
}

# user stuff
init_users_yaml() {
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
		admin="wheel"
		sed -i "s|#- GROUPGOESHERE|- $admin|" ${user_yaml}
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
		echo -e >&2 "Please input a password for ${user}:  "
		echo -e >&2 "Remaining attempts: ${attempts}"
		read -s tmp_pw
		if [[ "${tmp_pw}" == "" ]]; then
			echo -e >&2 "Password may not be empty."
			if [[ ${attempts} -eq 0 ]]; then
				echo -e "Maximum attempts exceeded, exiting."
				success=0
				break 1
			fi
			((attempts--))
			continue
		fi

		local matchattempts=3
		while [[ ${success} -ne 1 ]] && [[ ${matchattempts} -gt 0 ]]; do
			echo -e >&2 "Please input the password again to verify for ${user}: "
			read -s  tmp_pw2
			if [[ "${tmp_pw}" == "${tmp_pw2}" ]]; then
				echo -e >&2 "Passwords match!  Continuing.."
				mkpasswd --method=yescrypt ${tmp_pw} > ${user}.pw.secure
				success=1
				break 2
			else
				echo -e >&2 "\nPasswords do not match! Trying again..\n"
				((matchattempts--))
				echo -e >&2 "Remaining attempts: ${matchattempts}"
				if [[ ${success} -ne 1 ]] && [[ ${matchattempts} -eq 0 ]]; then
					echo -e >&2 "Maximum attempts reached, exiting.."
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
	for user in ${users[@]}; do
		if [[ $(set_pw "${user}") -ne 0 ]]; then
			echo -e "Failed to set a password for ${user}."
			exit 1
		else
			echo -e "Set password for ${user}"
			echo -e "Generating SSH public key for ${user}..\n"
			ssh-keygen -t ed25519 -C "${user}@wavelet.local" -f ${user}-ssh
			echo -e "Generating YAML block for user..\n"
			cp users_yaml ${user}_yaml.yml
			generate_user_yaml ${user}

			# Now we add the user YAML block to the server ignition, preserving the tag as we go..
			echo -e "Adding generated YAML block to ignition file for ${user}..\n"
			f2="$(<${user}_yaml.yml)"
			input_files_arr=($INPUTFILES)
			for file in "${input_files_arr[@]}"; do
				if [ -f "$file" ]; then
					awk -vf2="$f2" '/#ADD_USER_YAML_HERE/{print f2;print;next}1' "${file}" > tmp && mv tmp "${file}"
					echo -e "YAML block for ${user} added to ignition file ${file}..\n"
				else
					echo "Warning: ${file} does not exist or is inacessible!"
				fi
			done
		fi
	done

	echo -e "Ignition customization completed, and .ign files have been generated."

	# We set DevMode disabled here, even though it's enabled by default in ignition
	sed -i "s|/var/developerMode.enabled|/var/developerMode.disabled|g" ${INPUTFILES}
	sed -i "s|DeveloperModeEnabled - will pull from working branch (default behavior)|DeveloperModeDisabled - pulling from master|g" ${INPUTFILES}

	# Check for developermode flag so we pull from working branch rather than continually pushing messy and embarassing broken commits to the main branch..
	if [[ "${developerMode}" -eq "1" ]]; then
		echo -e "Injecting dev branch into files..\n"
		repl="https://raw.githubusercontent.com/Allethrium/wavelet/armelvil-working"
		sed -i "s|https://github.com/Allethrium/wavelet/raw/master|${repl}|g" ${INPUTFILES}
		# Yepm I set it enabled again here, if the devmode arg is on.
		sed -i "s|/var/developerMode.disabled|/var/developerMode.enabled|g" ${INPUTFILES}
		sed -i "s|DeveloperModeDisabled - pulling from master|DeveloperModeEnabled - will pull from working branch|g" ${INPUTFILES}
		sed -i "s|https://raw.githubusercontent.com/Allethrium/wavelet/master|${repl}|g" ${INPUTFILES}
	fi

	# WiFi settings
	# changed to mod ignition files w/ inline data for the scripts to call, this way I don't publish wifi secrets to github.
	INPUTFILES="server_custom.yml decoder_custom.yml"
	echo -e "Moving on to WiFi settings"
	echo -e "If your Wifi AP hasn't yet been configured, please do so now, as the installer will wait for your input\n"
	read -p "Please input the SSID of your configured wireless network:  " wifi_ssid
	read -p "Please input the first three elements of the WiFi BSSID / MAC address, colon delimited like so AA:BB:CC:  " wifi_bssid
	read -p "Please input the configured password for your WiFi SSID:  " wifi_password

		repl=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<< "${wifi_ssid}")
		sed -i "s/SEDwaveletssid/${repl}/g" ${INPUTFILES}

		repl=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<< "${wifi_bssid}")
		sed -i "s/SEDwaveletbssid/${repl}/g" ${INPUTFILES}

		repl=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<< "${wifi_password}")
		sed -i "s/SEDwaveletwifipassword/${repl}/g" ${INPUTFILES}
}


####
#
# Main
#
####
#set -x
echo -e "Will this system run on an isolated network?"
read -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || client_networks || echo -e "System configured for isolated, authoritative mode." && isoMode="mode=iso"
customization
echo -e "Calling coreos_installer.sh to generate ISO images.  You will then need to burn them to USB/SD cards."
./coreos_installer.sh "${developerMode}" "${isoMode}"
