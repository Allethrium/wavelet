#!/bin/bash
# Updates wavelet modules automatically from Git repo.  Useful for installing updates to wavelet as long as no system packages are affected.
# Detects if we are on dev or master branch.  To switch, move that file flag someplace else.

detect_self(){
systemctl --user daemon-reload
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
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
	install_wavelet_modules
	extract_base
	extract_home && extract_usrlocalbin
}

extract_base(){
	tar xf /home/wavelet/wavelet-files.tar.xz -C /home/wavelet --no-same-owner
	cd /home/wavelet
	mv ./usrlocalbin.tar.xz /usr/local/bin/
}

extract_etc(){
	umask 022
	tar xf /etc/etc.tar.xz -C /etc --no-same-owner --no-same-permissions
	echo -e "System config files setup successfully..\n"
}

extract_home(){
	tar xf /home/wavelet/wavelethome.tar.xz -C /home/wavelet
	chown -R wavelet:wavelet /home/wavelet
	chmod 0755 /home/wavelet/http
	chmod -R 0755 /home/wavelet/http-php
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
	sed -i "s/!!hostnamegoeshere!!/${hostname}/g" /usr/local/bin/wavelet_network_sense.sh
	touch /var/extract.target
}

generate_tarfiles(){
	echo -e "Generating tar.xz files for upload to distribution server..\n"
	tar -cJf usrlocalbin.tar.xz --owner=root:0 -C /var/home/wavelet/wavelet-git/webfiles/root/usr/local/bin/ .
	tar -cJf wavelethome.tar.xz --owner=wavelet:1337 -C /var/home/wavelet/wavelet-git/webfiles/root/home/wavelet/ .
	echo -e "Packaging files together..\n"
	tar -cJf wavelet-files.tar.xz {./usrlocalbin.tar.xz,wavelethome.tar.xz}
	echo -e "Done."
	rm -rf {./usrlocalbin.tar.xz,wavelethome.tar.xz}
	mv /var/home/wavelet/wavelet-files.tar.xz /var/home/wavelet/http/ignition/ && chown wavelet:wavelet /var/home/wavelet/http/ignition/wavelet-files.tar.xz
	cp /usr/local/bin/wavelet_installer_xf.sh /home/wavelet/http/ignition && chmod 0644 /home/wavelet/http/ignition/wavelet_installer_xf.sh
}


#####
#
# Main
#
#####

echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
systemctl disable zincati.service --now
# Update with the server hostname - no other device should be doing network sense.
sed -i "s/hostnamegoeshere/$(hostname)/g" /usr/local/bin/wavelet_network_sense.sh
FILES=("/var/home/wavelet/wavelet-files.tar.xz" \
	"/usr/local/bin/wavelet_install_client.sh" \
	"/usr/local/bin/wavelet_installer_xf.sh" \
	"/etc/skel/.bashrc" \
	"/etc/skel/.bash_profile")
cp "${FILES[@]}" /var/home/wavelet/http/ignition/
chmod -R 0644 /var/home/wavelet/http/ignition/* && chown -R wavelet:wavelet /var/home/wavelet/http
restorecon -Rv /var/home/wavelet/http
#set -x
exec >/home/wavelet/update_wavelet_modules.log 2>&1
detect_self
echo -e "Update completed.  The system will automatically reboot in ten seconds!"
systemctl reboot