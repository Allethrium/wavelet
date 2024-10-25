#!/bin/bash
# Runs RPM-OStree overlay 
# Then extracts the downloaded tar files to their appropriate directories.  Should be one of the first things to run on initial boot.
# All wavelet modules, including the web server code, are deployed on all devices, however only the server has the web servers enabled.

detect_self(){
systemctl --user daemon-reload
UG_HOSTNAME=$(hostname)
	echo -e "Hostname is $UG_HOSTNAME \n"
	case $UG_HOSTNAME in
	enc*)                   echo -e "I am an Encoder \n" && echo -e "Provisioning systemD units as an encoder.."							;	event_decoder
	;;
	decX.wavelet.local)     echo -e "I am a Decoder, but my hostname is generic.  An additional reboot will occur after build_ug firstrun"	;	event_decoder 
	;;
	dec*)                   echo -e "I am a Decoder \n" && echo -e "Provisioning systemD units as a decoder.."								;	event_decoder
	;;
	svr*)                   echo -e "I am a Server. Proceeding..."																			;	event_server
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
	get_ipValue
	sed -i "s/SVR_IPADDR/${IPVALUE}/g" /etc/dnsmasq.conf
	# Generate and enable systemd units which will be enabled
	# Therefore, they will start on next boot, run, and disable themselves
	# None of them should require a further reboot
	echo -e "\
		[Unit]
		Description=Install Dependencies
		ConditionPathExists=/var/rpm-ostree-overlay.rpmfusion.pkgs.complete
        After=multi-user.target
        [Service]
        Type=oneshot
        ExecStart=/usr/bin/bash -c "/usr/local/bin/wavelet_install_ug_depends.sh"
        ExecStartPost=systemctl disable wavelet_install_depends.service
        [Install]
        WantedBy=multi-user.target" > /etc/systemd/system/wavelet_install_depends.service
	echo -e "\
		[Unit]
		Description=Install PXE support
		ConditionPathExists=/var/wavelet_depends.complete
		After=multi-user.target
        [Service]
        Type=oneshot
        ExecStart=/usr/bin/bash -c "/usr/local/bin/wavelet_pxe_grubconfig.sh"
        ExecStartPost=systemctl disable wavelet_install_pxe.service
        [Install]
        WantedBy=multi-user.target" > /etc/systemd/system/wavelet_install_pxe.service
    systemctl daemon-reload
    # From here, the system will reboot.
    # wavelet_install_depends.service will then run, and force enable wavelet_install_pxe.service
    # wavelet_pxe_install.service will complete the root portion of the server spinup, allowing build_ug.sh to run in userspace.
    systemctl enable wavelet_install_depends.service
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
	podman build -t localhost/coreos_overlay --build-arg DKMS_KERNEL_VERSION=${DKMS_KERNEL_VERSION} -f /home/wavelet/containerfiles/Containerfile.coreos.overlay
	podman tag localhost/coreos_overlay localhost:5000/coreos_overlay:latest
	touch /var/rpm-ostree-overlay.complete
	touch /var/rpm-ostree-overlay.rpmfusion.repo.complete
	touch /var/rpm-ostree-overlay.rpmfusion.pkgs.complete
	rpm-ostree rebase ostree-unverified-image:containers-storage:localhost:5000/coreos_overlay
	#rpm-ostree --bypass-driver --experimental rebase ostree-unverified-image:containers-storage:localhost:5000/coreos_overlay
	# Push image to container registry
	# We use zstd for better compression and we have no need to encrypt the layers.  This might help on network traffic for the
	podman push localhost:5000/coreos_overlay:latest 192.168.1.32:5000/coreos_overlay --tls-verify=false --compression-format=zstd:chunked --compression-level=16 --force-compression
	echo -e "\nRPM package updates completed, finishing installer task..\n"
}

rpm_overlay_install_decoder(){
	# This differs from the server in that we don't need to build the container,
	# We pull the client installer module and run it to generate the wavelet files in /usr/local/bin
	dmidecode | grep "Manufacturer" | cut -d ':' -f 2 | head -n 1
	echo -e "\nDownloading client installer module..\n"
	curl -o /usr/local/bin/wavelet_install_client.sh http://192.168.1.32:8080/ignition/wavelet_install_client.sh
	chmod 0755 /usr/local/bin/wavelet_install_client.sh && /usr/local/bin/wavelet_install_client.sh
	systemctl enable wavelet_install_client.service --now
	# and we pull the already generated overlay from the server registry
	# This is the slowest part of the process, can we speed it up by compressing the overlay?
	echo -e "Installing via container and applying as Ostree overlay..\n"
	# We need to pull the container from the server registry first, apparently manually?  Probably https issue here.
	podman pull 192.168.1.32:5000/coreos_overlay --tls-verify=false
	rpm-ostree rebase ostree-unverified-image:containers-storage:192.168.1.32:5000/coreos_overlay
	touch /var/rpm-ostree-overlay.complete
	touch /var/rpm-ostree-overlay.rpmfusion.repo.complete && \
	touch /var/rpm-ostree-overlay.rpmfusion.pkgs.complete && \
	touch /var/rpm-ostree-overlay.dev.pkgs.complete
	echo -e "\
[Unit]
Description=Install Client Dependencies
ConditionPathExists=/var/rpm-ostree-overlay.rpmfusion.pkgs.complete
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c "/usr/local/bin/wavelet_install_client.sh"
[Install]
WantedBy=multi-user.target" > /etc/systemd/system/wavelet_install_client.service
	echo -e "RPM package updates completed, finishing installer task..\n"
	sleep 2
	systemctl reboot
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