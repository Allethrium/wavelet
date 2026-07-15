#!/bin/bash
# Updates wavelet modules automatically from Git repo.  Useful for installing updates to wavelet as long as no system packages are affected.
# Detects if we are on dev or master branch.  To switch, move that file flag someplace else.


detect_self(){
	# Detect_self in this case relies on the etcd type key
	printvalue=$(hostname)
	echo -e "Host type is: ${printvalue}\n"
	case "${printvalue}" in
		enc*)
			echo -e "I am an Encoder \n" && echo -e "Provisioning systemD units as an encoder.."
			event_client
			;;
		dec*)
			echo -e "I am a Decoder \n" && echo -e "Provisioning systemD units as a decoder.."
			event_client
			;;
		svr*)
			echo -e "I am a Server. Proceeding..."
			event_server
			;;
		*)
			echo -e "This device Hostname is not set approprately, exiting \n" && exit 0
			;;
	esac
}


event_client(){
	# retrieves git mirror tar.gz from server and extracts directly into system paths.
	curl -s -L -o "$setupPath/wavelet_files.tar.gz" "http://$(dnsdomainname):8080/ignition/wavelet_files_update.tar.gz" || {
		echo "Error downloading wavelet_files_update.tar.gz from server!"
		exit 1
	}
	mkdir -p "$setupPath/webfiles/root"
	tar xf "$setupPath/wavelet_files.tar.gz" -C "$setupPath/webfiles/root" --no-same-owner --strip-components=1

	extract_etc && extract_home && extract_usrlocalbin
	rm -rf "$setupPath/webfiles"
	exit 0
}

event_server(){
	# The server requires some additional steps.
	download_wavelet_git
	# Generate our installer files to the http/ignition dir for client booting
	install_wavelet_modules
	# Perform extraction for updated wavelet files from our generated tar to update our own files
    extract_home && extract_usrlocalbin
    rm -rf "$setupPath/etc.tar.xz"
	# Update with the server hostname - no other device should be doing network sense.
	sed -i "s/hostnamegoeshere/${hostNameSys}/g" "/usr/local/bin/wavelet_network_sense.sh"
	FILES=(
		"/usr/local/bin/wavelet_install_client.sh" \
		"/usr/local/bin/wavelet_install_packages.sh" \
		"/etc/skel/.bashrc" \
		"/etc/skel/.bash_profile"
		)
	cp "${FILES[@]}" "/var/home/wavelet/http/ignition/"
	# Ensure bashrc and profile have compatible filenames for decoder ignition
	mv "/var/home/wavelet/http/ignition/.bashrc" "/var/home/wavelet/http/ignition/skel_bashrc.txt"
	mv "/var/home/wavelet/http/ignition/.bash_profile" "/var/home/wavelet/http/ignition/skel_profile.txt"
	cp "/usr/local/backgrounds/sway/wavelet_test.png" "/var/home/wavelet/http/ignition/"
	# Ensure wavelet_decoder_keys.csv is available for ignition to be generated
	cp "/var/home/wavelet/config/wavelet_decoder_keys.csv" "/var/home/wavelet/http/ignition"
	echo "Regenerating ignition files for clients..(note; this will NOT update the customized decoder ignition (yet)"
	echo "This is because it needs secrets and other data from the initial configuration."
	butane --pretty --strict --files-dir /var/home/wavelet/http/ignition/ /var/home/wavelet/config/automated_installer.yml \
	    --output automated_installer.ign
	butane --pretty --strict --files-dir /var/home/wavelet/http/ignition/ /var/home/wavelet/config/decoder_custom.yml \
		--output /var/home/wavelet/http/ignition/decoder.ign
	chmod -R 0644 /var/home/wavelet/http/ignition/* && chown -R wavelet:wavelet "/var/home/wavelet/http"
	restorecon -R "/var/home/wavelet/http" > /dev/null
}

extract_etc(){
	umask 022
	shopt -s dotglob nullglob
	if [ -d "$setupPath/webfiles/root/etc" ]; then
		cp -a "$setupPath/webfiles/root/etc/"* /etc/ 2>/dev/null || true
	fi
	shopt -u dotglob nullglob
	echo -e "System config files setup successfully..\n"
	rm -rf "$setupPath/webfiles/root/etc"
}

extract_home(){
	shopt -s dotglob nullglob
	cp -a "$setupPath/webfiles/root/home/"* /var/home/ 2>/dev/null || true
	shopt -u dotglob nullglob
	chown -R wavelet:wavelet "/var/home/wavelet"
	chown -R wavelet-root:wavelet-root "/var/home/wavelet-root"
	chmod 0755 "/var/home/wavelet/http"
	chmod -R 0755 "/var/home/wavelet/http-php"
	echo -e "Wavelet homedir setup successfully..\n"
	rm -rf "$setupPath/webfiles/root/home"
}

extract_usrlocalbin(){
	# Save customized files to ensure no overwrite
	cp /usr/local/bin/ipa_link_up.sh /var/tmp
	umask 022
	shopt -s dotglob nullglob
	cp -a "$setupPath/webfiles/root/usr/local/bin/"* /usr/local/bin/
	shopt -u dotglob nullglob
	chmod +x "/usr/local/bin"
	chmod 0755 /usr/local/bin/*
	if touch "/var/wavelet_ramfs/test.txt"; then
		shopt -s dotglob nullglob
		cp -af /usr/local/bin/* "/var/wavelet_ramfs"
		shopt -u dotglob nullglob
	fi
	echo -e "Wavelet application modules setup successfullym ramdrive updated if it exists..\n"
    rm -rf "$setupPath/webfiles/root/usr/local/bin"
    cp "/var/tmp/ipa_link_up.sh" "/usr/local/bin"
}

download_wavelet_git(){
	# Runs only if we are using non-LAN Deployment, or we are updating the server
	if [[ -f "/var/developerMode.enabled" ]]; then
    	GH_BRANCH="armelvil-working"
  	else
		GH_BRANCH="master"
  	fi
  	mkdir -p "$setupPath/git"
	if curl -s -L -o "/var/tmp/wavelet_files.tar.gz" \
		"https://github.com/Allethrium/wavelet/archive/refs/heads/$GH_BRANCH.tar.gz"; then
		echo "		Acquired wavelet tarball, proceeding.."
		tar xf "/var/tmp/wavelet_files.tar.gz" -C "$setupPath/git" --no-same-owner --strip-components=1
		# Copy the original git tree w/ everything for client spinup.
		cp "/var/tmp/wavelet_files.tar.gz" "/var/home/wavelet/http/ignition/"
	else
		echo "		Error downloading wavelet tarball!  aborting!"
		echo "		Please check this user's write permissions to /var/www"
		exit 1
	fi
}

install_wavelet_modules(){
    # Generates the correct archive for the clients and server
    gitDir="$setupPath/git"
    tar cJf "$setupPath/etc.tar.xz" \
    	-C "$gitDir/webfiles/root/etc" --no-same-owner --no-same-permissions .
    tar cJf "$setupPath/wavelethome.tar.xz" \
    	-C "$gitDir/webfiles/root/home" --no-same-owner --no-same-permissions .
    tar cJf "$setupPath/usrlocalbin.tar.xz" \
    	-C "$gitDir/webfiles/root/usr/local/bin" --no-same-owner --no-same-permissions .
    # Drop install_packages into usrlocalbin as well as new decoder yml
    cp "$gitDir/ignition_files/wavelet_install_packages.sh" "/usr/local/bin"
    cp $gitDir/ignition_files/{automated_coreos_deployment.sh,wavelet_install_packages.sh} \
    	"/var/home/wavelet/http/ignition/"
    cp $gitDir/webfiles/root/usr/local/bin/{wavelet_install_client.sh,connectwifi.sh} \
    	"/var/home/wavelet/http/ignition/"
    # Generate our tar.gz for distribution.
    # This is the update file for already existing clients NOT the initial git archive!
    cd "$setupPath" || exit
    tar cf "/var/home/wavelet/http/ignition/wavelet_files_update.tar.gz" *.tar.xz
	# Perform any further customization required in our scripts, and clean up.
	sed -i "s/!!hostnamegoeshere!!/$(hostname)/g" "/usr/local/bin/wavelet_network_sense.sh"
	chown -R wavelet:wavelet "/var/home/wavelet/http/"
	touch "/var/extract.target"
}


#####
#
# Main
#
#####


hostNameSys=$(hostname)

setupPath="/var/home/wavelet/config/setup"
mkdir -p "$setupPath"

echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
systemctl disable zincati.service --now

exec >"/var/home/wavelet/logs/update_wavelet_modules.log" 2>&1
detect_self

echo -e "Update completed!"
rm -rf "$setupPath/wavelet_files.tar.gz"