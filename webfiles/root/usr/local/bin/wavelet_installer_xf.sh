#!/bin/bash
# Runs RPM-OStree overlay 
# Then extracts the downloaded tar files to their appropriate directories.  Should be one of the first things to run on initial boot.
# All wavelet modules, including the web server code, are deployed on all devices, however only the server has the web servers enabled.

detect_self(){
systemctl --user daemon-reload
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*)                   echo -e "I am an Encoder \n" && echo -e "Provisioning systemD units as an encoder.."            ;   event_decoder
	;;
	decX.wavelet.local)     echo -e "I am a Decoder, but my hostname is generic.  Randomizing my hostname, and rebooting"   ;   event_decoder 
	;;
	dec*)                   echo -e "I am a Decoder \n" && echo -e "Provisioning systemD units as a decoder.."              ;   event_decoder
	;;
	svr*)                   echo -e "I am a Server. Proceeding..."                                                          ;   event_server
	;;
	*)                      echo -e "This device Hostname is not set approprately, exiting \n" && exit 0
	;;
	esac
}

event_decoder(){
	rpm_overlay_install_decoder
	exit 0
}

event_server(){
	# Generate RPM Container overlay
	cp /usr/local/bin/wavelet_install_ug_depends.sh	/home/wavelet/containerfiles/
	cp /usr/local/bin/wavelet_pxe_grubconfig.sh		/home/wavelet/containerfiles/
	rpm_overlay_install
	# generate a hostname file so that dnsmasq's dhcp-script call works properly
	hostname=$(hostname)
	echo -e "${hostname}" > /var/lib/dnsmasq/hostname.local
	# Perform any further customization required in our scripts
	sed -i "s/!!hostnamegoeshere!!/${hostname}/g" /usr/local/bin/wavelet_network_sense.sh
	get_ipValue
	sed -i "s/SVR_IPADDR/${IPVALUE}/g" /etc/dnsmasq.conf
	sleep 1
	echo -e "\nInitial config completed, issue systemctl reboot to continue..\n"
}

get_ipValue(){
	# Gets the current IP address for this host
	IPVALUE=$(ip a | grep 192.168.1 | awk '/inet / {gsub(/\/.*/,"",$2); print $2}')
	if [[ "${IPVALUE}" == "" ]] then
			# sleep for five seconds, then call yourself again
			echo -e "\nIP Address is null, sleeping and calling function again\n"
			sleep 5
			get_ipValue
		else
			echo -e "\nIP Address is not null, testing for validity..\n"
			valid_ipv4() {
				local ip=$1 regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
				if [[ $ip =~ $regex ]]; then
					echo -e "\nIP Address is valid, continuing..\n"
					return 0
				else
					echo "\nIP Address is not valid, sleeping and calling function again\n"
					get_ipValue
				fi
			}
			valid_ipv4 "${IPVALUE}"
	fi
}

rpm_overlay_install(){
	echo -e "Installing via container and applying as Ostree overlay..\n"
	DKMS_KERNEL_VERSION=$(uname -r)
	podman build -t localhost/coreos_overlay --build-arg DKMS_KERNEL_VERSION=${DKMS_KERNEL_VERSION} -v /:/:z -f /home/wavelet/containerfiles/Containerfile.coreos.overlay
	podman tag localhost/coreos_overlay localhost:5000/coreos_overlay:latest
	touch /var/rpm-ostree-overlay.complete
	touch /var/rpm-ostree-overlay.rpmfusion.repo.complete && \
	touch /var/rpm-ostree-overlay.rpmfusion.pkgs.complete
	rpm-ostree --bypass-driver rebase ostree-unverified-image:containers-storage:localhost:5000/coreos_overlay
	#rpm-ostree --bypass-driver --experimental rebase ostree-unverified-image:containers-storage:localhost:5000/coreos_overlay
	#podman push localhost:5000/coreos_overlay:latest --tls-verify=false
	echo -e "\nRPM package updates completed, finishing installer task..\n"
}

rpm_overlay_install_decoder(){
	# This differs from the server in that we don't need to build the container,
	# and we pull the already generated overlay from the server registry
	echo -e "Installing via container and applying as Ostree overlay..\n"
	DKMS_KERNEL_VERSION=$(uname -r)
	rpm-ostree --bypass-driver --experimental rebase ostree-unverified-image:containers-storage:192.168.1.32:5000/coreos_overlay
	touch /var/rpm-ostree-overlay.complete
	touch /var/rpm-ostree-overlay.rpmfusion.repo.complete && \
	touch /var/rpm-ostree-overlay.rpmfusion.pkgs.complete && \
	touch /var/rpm-ostree-overlay.dev.pkgs.complete
	echo -e "RPM package updates completed, finishing installer task..\n"
}

####
#
#
# Main
#
#
####

# Perhaps add a checksum to make sure nothing's been tampered with here..
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
systemctl disable zincati.service --now
# Debug flag
# set -x
exec >/home/wavelet/installer.log 2>&1
detect_self