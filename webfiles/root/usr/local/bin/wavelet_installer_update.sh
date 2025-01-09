#!/bin/bash
# Updates wavelet modules automatically from Git repo.  Useful for installing updates to wavelet as long as no system packages are affected.
# Detects if we are on dev or master branch.  To switch, move that file flag someplace else.

detect_self(){
systemctl --user daemon-reload
	echo -e "Hostname is ${hostNamePretty} \n"
	case ${hostNamePretty} in
		enc*) 					echo -e "I am an Encoder \n" && echo -e "Provisioning systemD units as an encoder.."			;	event_encoder
		;;
		decX.wavelet.local)		echo -e "I am a Decoder, but my hostname is generic.  Randomizing my hostname, and rebooting"	;	event_decoder 
		;;
		dec*)					echo -e "I am a Decoder \n" && echo -e "Provisioning systemD units as a decoder.."				;	event_decoder
		;;
		svr*)					echo -e "I am a Server. Proceeding..."  														;	event_server
		;;
		*) 						echo -e "This device Hostname is not set approprately, exiting \n" && exit 0
		;;
	esac
}

event_encoder(){
	# retreives tar.xz from server
	wget https://192.168.1.32:8080/ignition/wavelet-files.tar.xz
	extract_base
	extract_home && extract_usrlocalbin
	exit 0
}

event_decoder(){
	# retreives tar.xz from server
	wget https://192.168.1.32:8080/ignition/wavelet-files.tar.xz
	extract_base
	extract_home && extract_usrlocalbin
	exit 0
}

event_server(){
	# The server requires some additional steps.
	install_wavelet_modules
	# Update with the server hostname - no other device should be doing network sense.
	sed -i "s/hostnamegoeshere/$(UG_HOSTNAME)/g" /usr/local/bin/wavelet_network_sense.sh
	FILES=("/var/home/wavelet/wavelet-files.tar.xz" \
		"/usr/local/bin/wavelet_install_client.sh" \
		"/usr/local/bin/wavelet_installer_xf.sh" \
		"/etc/skel/.bashrc" \
		"/etc/skel/.bash_profile")
	cp "${FILES[@]}" /var/home/wavelet/http/ignition/
	chmod -R 0644 /var/home/wavelet/http/ignition/* && chown -R wavelet:wavelet /var/home/wavelet/http
	# Ensure bashrc and profile have compatible filenames for decoder ignition
	mv /var/home/wavelet/http/ignition/.bashrc /var/home/wavelet/http/ignition/skel_bashrc.txt
	mv /var/home/wavelet/http/ignition/.bash_profile /var/home/wavelet/http/ignition/skel_profile.txt
	restorecon -Rv /var/home/wavelet/http
}

extract_base(){
	tar xf /var/home/wavelet/wavelet-files.tar.xz -C /home/wavelet --no-same-owner
	cd /var/home/wavelet
	mv ./usrlocalbin.tar.xz /usr/local/bin/
}

extract_etc(){
	umask 022
	tar xf /etc/etc.tar.xz -C /etc --no-same-owner --no-same-permissions
	echo -e "System config files setup successfully..\n"
}

extract_home(){
	tar xf /var/home/wavelet/wavelethome.tar.xz -C /home/wavelet
	chown -R wavelet:wavelet /home/wavelet
	chmod 0755 /var/home/wavelet/http
	chmod -R 0755 /var/home/wavelet/http-php
	echo -e "Wavelet homedir setup successfully..\n"
}

extract_usrlocalbin(){
	umask 022
	tar xf /usr/local/bin/usrlocalbin.tar.xz -C /usr/local/bin --no-same-owner
	chmod +x /usr/local/bin
	chmod 0755 /usr/local/bin/*
	echo -e "Wavelet application modules setup successfully..\n"
}

install_wavelet_modules(){
	gitcommand="/usr/bin/git"
	cd /var/home/wavelet
	if [[ -f /var/developerMode.enabled ]]; then
		echo -e "\n\n***WARNING***\n\nDeveloper Mode is ON\n\nCloning from development repository..\n"
		GH_BRANCH="armelvil-working"
	fi
	GH_REPO="https://github.com/Allethrium/wavelet"
	# Git complains about the directory already existing so we'll just work in a tmpdir for now..
	rm -rf /var/home/wavelet/wavelet-git
	mkdir -p /var/home/wavelet/wavelet-git
	echo -e "\nCommand is; ${gitcommand} clone -b ${GH_BRANCH} ${GH_REPO} /var/home/wavelet/wavelet-git\n"
	git clone -b ${GH_BRANCH} ${GH_REPO} /var/home/wavelet/wavelet-git && echo -e "Cloning git repository..\n"
	generate_tarfiles
	# This seems redundant, but works to ensure correct placement+permissions of wavelet modules
	extract_base
	extract_home
	extract_usrlocalbin
	hostname=$(hostname)
	echo -e "${hostname}" > /var/lib/dnsmasq/hostname.local
	# Perform any further customization required in our scripts, and clean up.
	sed -i "s/!!hostnamegoeshere!!/$(hostname)/g" /usr/local/bin/wavelet_network_sense.sh
	touch /var/extract.target
}

generate_tarfiles(){
	echo -e "\nGenerating tar.xz files for upload to distribution server.."
	cd /var/home/wavelet
	echo "Removing old archive.."
	rm -rf wavelet-files.tar.xz
	tar -cJf usrlocalbin.tar.xz --owner=root:0 -C /var/home/wavelet/wavelet-git/webfiles/root/usr/local/bin/ .
	tar -cJf wavelethome.tar.xz --owner=wavelet:1337 -C /var/home/wavelet/wavelet-git/webfiles/root/home/wavelet/ .
	echo -e "Packaging files together.."
	tar -cJf wavelet-files.tar.xz {./usrlocalbin.tar.xz,wavelethome.tar.xz}
	echo -e "Done."
	rm -rf {./usrlocalbin.tar.xz,wavelethome.tar.xz}
	setfactl -b wavelet-files.tar.xz
}


#####
#
# Main
#
#####

# One rather silly thing.. if this module is what gets updated... then that won't work until it is run again the next reboot.
hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)

echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
systemctl disable zincati.service --now

#set -x
exec >/var/home/wavelet/logs/update_wavelet_modules.log 2>&1
detect_self

echo -e "Update completed.  The system will automatically reboot in three seconds!"
sleep 3
systemctl reboot