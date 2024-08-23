#!/bin/bash

# This script bootstraps your initial wavelet server based upon input variables.
# The server can run in authoritative mode for an isolated network, or subordinate mode if you are placing it on a network with an active DHCP server for instance.
# It's generally designed to be run isolated and handle its own DHCP/DNS.

for i in "$@"
	do
		case $i in
			D)	echo -e "\nDev mode enabled, switching git tree to working branch\n."
				developerMode="1"
			;;
			h)	echo -e "\nSimple command line switches:\n-D for developer mode, will clone git from ARMELVIL working branch for non-release features.\n"
				exit 0
			;;
			*)	echo -e "\nBad input argument, ignoring"
			;;
		esac
done

echo -e "Is the target network configured with an active gateway, and are you prepared to deal with downloading approximately 4gb of initial files?"
read -p "Continue? (Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit
echo -e "Continuing, copying base ignition files for customization.."
cp ./ignition_files/ignition_server.yml ./server_custom.yml
cp ./ignition_files/ignition_decoder.yml ./decoder_custom.yml
cp ./ignition_files/ignition_encoder.yml ./encoder_custom.yml
# IPv6 mode eventually? Just to be snazzy?
# remove old iso files
rm -rf $HOME/Downloads/wavelet_server.iso
rm -rf $HOME/Downloads/wavelet_decoder.iso
rm -rf $HOME/Downloads/wavelet_encoder.iso

client_networks(){
	echo -e "System configured to be run on a larger network."
		echo -e "Please input the system's gateway IP address, and subnet mask.."
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
	# SED for FQDN and replace
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

customization(){
	echo -e "Generating ignition files with appropriate settings.."
	INPUTFILES="server_custom.yml encoder_custom.yml decoder_custom.yml"
	touch rootpw.secure
	touch waveletpw.secure
	chmod 0600 *.secure
	unset tmp_rootpw
	unset tmp_waveletpw
	echo -e 'Please input a password for the wavelet-root user: '
	read -s  tmp_rootpw
	echo -e 'Please input a password for the wavelet user: '
	read -s  tmp_waveletpw
	mkpasswd --method=yescrypt "${tmp_rootpw}" > rootpw.secure
	mkpasswd --method=yescrypt "${tmp_waveletpw}" > waveletpw.secure
	unset tmp_rootpw tmp_waveletpw
	echo -e "Password hashes generated..\n"
	
	repl=$(cat rootpw.secure)
	sed -i "s|waveletrootpassword|${repl}|g" ${INPUTFILES}
	echo -e "Root password hash injected..\n" 
	echo -e "root pw injected..\n"
	
	repl=$(cat waveletpw.secure)
	sed -i "s|waveletuserpassword|${repl}|g" ${INPUTFILES}
	
	echo -e "user password hash injected..\n"
	
	echo -e "Generating SSH Public Key and injecting to Ignition file.."
	ssh-keygen -t ed25519 -C "wavelet@wavelet.local" -f wavelet
	pubkey=$(cat wavelet.pub)
	sed -i "s|PUBKEYGOESHERE|${pubkey}|g" ${INPUTFILES}
	echo -e "Ignition customization completed, and .ign files have been generated."

	if [[ "${developerMode}" -eq "1" ]]; then
		echo -e "Injecting dev branch into files..\n"
		repl="https://raw.githubusercontent.com/Allethrium/wavelet/armelvil-working"
		sed -i "s|https://github.com/Allethrium/wavelet/raw/master|${repl}|g" ${INPUTFILES}
		sed -i "s|DEV_OFF|DEV_ON|g" ${INPUTFILES}
	fi

	# WiFi settings
	# changed to mod ignition files w/ inline data for the scripts to call, this way I don't publish wifi secrets to github.
	INPUTFILES="server_custom.yml encoder_custom.yml decoder_custom.yml"
	echo -e "Moving on to WiFi settings"
	echo -e "If your Wifi AP hasn't yet been configured, please do so now, as the installer will wait for your input\n"
	read -p "Please input the SSID of your configured wireless network: " wifi_ssid
	read -p "Please input the first three elements of the WiFi BSSID / MAC address, colon delimited like so AA:BB:CC:" wifi_bssid
	read -p "Please input the configured password for your WiFi SSID: " wifi_password

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

echo -e "Will this system run on an isolated network?"
read -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || client_networks
echo -e "System configured for isolated, authoritative mode."
customization
echo -e "Calling coreos_installer.sh to generate ISO images.  You will then need to burn them to USB/SD cards."
./coreos_installer.sh
