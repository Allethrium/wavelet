#!/bin/bash

# This script bootstraps your initial wavelet server based upon input variables.
# The server can run in authoritative mode for an isolated network, or subordinate mode if you are placing it on a network with an active DHCP server for instance.
# It's generally designed to be run isolated and handle its own DHCP/DNS.
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
		grIP="${GW}/${SN}"
			if [[ SN > 28 ]]; then
					echo -e "Subnet mask is too small for a Wavelet system, we need at least 32 host IP's to be available!"
			elif [[ SN < 24 ]]; then
					echo -e "Subnet mask seems very large - please note this system would work best on a more isolated network in authoritative mode! \n
							effective operation cannot be guaranteed when taking into account issues on larger networks with congestion, security appliances etc. \n"
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
	# Yes, I know this is terribly insecure, however if attackers are watching what you're doing on the bootstrap server you may have bigger problems..
	# Sick of typing this is for now..
	#read -p "Please input a password for the wavelet-root user: "  wvltroot_pw
	#read -p "Please input a password for the Wavelet user: " wavelet_pw
	wvltroot_pw="TestLab032023@"
	wavelet_pw="WvltU$R60C"
	rootpw=$(mkpasswd --method=yescrypt ${wvltroot_pw})
	waveletpw=$(mkpasswd --method=yescrypt ${wavelet_pw})
	echo -e "Password hashes generated..\n"
	
	repl=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<<"$rootpw")
	sed -i "s/waveletrootpassword/${repl}/g" ${INPUTFILES}
        echo -e "${rootpw} injected .. \n" 
	echo -e "root pw injected..\n"
	
	repl=$(sed -e 's/[&\\/]/\\&/g; s/$/\\/' -e '$s/\\$//' <<<"$waveletpw")
	sed -i "s/waveletuserpassword/${repl}/g" ${INPUTFILES}
	
	echo -e "user pw injected..\n"
	
	echo -e "Generating SSH Public Key and injecting to Ignition file.."
	ssh-keygen -t ed25519 -C "wavelet@wavelet.local" -f wavelet
	pubkeys=$(cat wavelet.pub)
	sed -i "s/PUBKEYGOESHERE/${pubkeys}/g" ${INPUTFILES}
	echo -e "Ignition customization completed, and .ign files have been generated."
}

wifi_setup(){
	INPUTFILES=./webfiles/root/usr/local/bin/decoderhostname.sh
	echo -e "please input your WiFi network and credentials \n
	Performance highly dependent on AP model, we tested on Ruckus AP's with good results.\n
	Note the AP needs to be configured seperately by hand, this script won't do that for you!\n"
	read -p "Configured WiFi SSID: " SSID
	read -p "Configured WiFi WPA2/WPA3 Password: " WIFIPW
	# WIFICRYPT=$(echo ${WIFIPW} | openssl enc -aes-256-cbc -md sha512 -a -pbkdf2 -iter 100000 -salt -pass pass:'SuperSecretPassword!111one')
	# Currently this can't be considered secure because the WiFi Password is in plain text all over the place..
	sed -i 's/Wavelet-wifi5g/$SSID/g' ${INPUTFILES}
	sed -i 's/a-secure-password/$WIFICRYPT/g' ${INPUTFILES}
}

# Main
echo -e "Will this system run on an isolated network?"
read -p "(Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || client_networks
echo -e "System configured for isolated, authoritative mode."
		# we still need to generate credentials here
		customization

echo -e "Calling coreos_installer.sh to generate ISO images.  You will then need to burn them to USB/SD cards."
./coreos_installer.sh
