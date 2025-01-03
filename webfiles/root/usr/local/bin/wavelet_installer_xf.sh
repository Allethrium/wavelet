#!/bin/bash
# Runs RPM-OStree overlay 
# Should be one of the first things to run on initial boot in place of a more commonly used direct systemd unit.
# All wavelet modules, including the web server code, are deployed on all devices.

detect_self(){
systemctl --user daemon-reload
# This might be of use if we need some custom kernels or decide to start building addition ostree overlays
platform=$(dmidecode | grep "Manufacturer" | cut -d ':' -f 2 | head -n 1)
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
	# First we'd need to determine our architecture.
	arch=$(uname -m)
	case ${arch} in
		"x86_64")	echo -e "AMD64 architecture, checking if we are a Microsoft Surface for custom kernel..\n";		determine_ifSurface
		;;
		"arm")		echo -e "aarch64 architecture, switching to ARM ostree..";										rpm_ostree_ARM
		;;
		"riscV")	echo -e "RISC-V architecture, switching to RISCV ostree..";										rpm_ostree_RISCV
		;;
		*)			echo -e "Architecture obsolete or unsupported, exiting..\n"
	esac
}

set_ethernet_mtu(){
	# Jumbo packets would be nice, but this breaks UG on the wireless clients.
	for interface in $(nmcli con show | grep ethernet | awk '{print $3}'); do
			nmcli con mod ${interface} mtu 9000
	done
}

event_server(){
	#	Server can only be x86.  I haven't had access to another platform with video hardware support + enough number crunching power to do the task.
	#	Suggestions which aren't too exotic are welcome!
	# Generate RPM Container overlay
	cp /usr/local/bin/wavelet_install_ug_depends.sh	/home/wavelet/containerfiles/
	cp /usr/local/bin/wavelet_pxe_grubconfig.sh		/home/wavelet/containerfiles/
	# old etcd setup previously in build_ug.sh
	#echo -e "Pulling etcd and generating systemd services.."
	#cd /home/wavelet/.config/systemd/user/
	#/bin/podman pull quay.io/coreos/etcd:v3.5.9
	#/bin/podman create --name etcd-member --net=host \
   #quay.io/coreos/etcd:v3.5.9 /usr/local/bin/etcd              \
   #--data-dir /etcd-data --name wavelet_svr                  \
   #--initial-advertise-peer-urls http://192.168.1.32:2380 \
   #--listen-peer-urls http://192.168.1.32:2380           \
   #--advertise-client-urls http://192.168.1.32:2379       \
   #--listen-client-urls http://192.168.1.32:2379,http://127.0.0.1:2379        \
	#   --initial-cluster wavelet_svr=http://192.168.1.32:2380 \
	#   --initial-cluster-state new
	#/bin/podman generate systemd --files --name etcd-member --restart-policy=always -t 2
	#sleep 1
	# Quadlet Etcd service, I have decided it's more appropriate to move this back to a system service
	# This is because it would only run when a user is logged on
	# We will likely want to secure the server console in prod deployment.
	# Make etcd datadir and copy nonsecure yaml to conf file, and update with server IP address.  We are using network=host in the container.
	mkdir -p /var/lib/etcd-data
	# Copy nonsecure conf file.  The secure file would be added by the wavelet_install_hardening.sh module if hardening is enabled.
	cp /etc/etcd/etcd.yaml.conf /etc/etcd/etcd.conf
	ip=$(hostname -I | cut -d " " -f 1)
	echo "${ip}" > /var/home/wavelet/etcd_ip
	sed -i "s|svrIP|${ip}|g" /etc/etcd/etcd.conf

	# Old systemd method
	echo -e "[Unit]
Description=Run single node etcd
After=network-online.target
Wants=network-online.target

[Service]
ExecStartPre=-mkdir -p /var/lib/etcd-data
ExecStartPre=-/bin/podman kill etcd
ExecStartPre=-/bin/podman rm etcd
ExecStartPre=-/bin/podman pull quay.io/coreos/etcd:v3.5.9
ExecStart=/bin/podman run --name etcd \
	--volume /var/lib/etcd-data:/etcd-data:Z \
	--net=host quay.io/coreos/etcd /usr/local/bin/etcd \
	--data-dir /etcd-data \
	--name wavelet_svr \
	--initial-advertise-peer-urls http://${ip}:2380 \
	--listen-peer-urls http://${ip}:2380 \
	--advertise-client-urls http://${ip}:2379 \
	--listen-client-urls http://${ip}:2379,http://127.0.0.1:2379 \
	--initial-cluster wavelet_svr=http://${ip}:2380 \
	--initial-cluster-state new
ExecStop=/bin/podman stop etcd

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/etcd-container.service

	# Quadlet
	echo -e "[Unit]
Description=etcd service
Documentation=https://github.com/etcd-io/etcd
Documentation=man:etcd
After=network.target

[Container]
Environment=ETCD_DATA_DIR=/etcd-data
Environment=ETCD_CONFIG_FILE=/etc/etcd/etcd.conf
Image=quay.io/coreos/etcd:v3.5.9
ContainerName=etcd-container
Network=host
Volume=/etc/etcd/:/etc/etcd/:Z
Volume=/var/lib/etcd-data:/etcd-data:Z
AutoUpdate=registry
NoNewPrivileges=true

[Service]
Environment=ETCD_CONFIG_FILE=/etc/etcd/etcd.conf
ExecStartPre=-mkdir -p /var/lib/etcd-data
ExecStartPre=-/bin/podman kill etcd
ExecStartPre=-/bin/podman rm etcd
ExecStartPre=-/bin/podman pull quay.io/coreos/etcd
Restart=always

[Install]
WantedBy=multi-user.target" > /etc/containers/systemd/etcd-quadlet.container
	systemctl daemon-reload
	# Remember, quadlets don't work with systemd enable <arg>
	systemctl start etcd-quadlet.service
	#systemctl enable etcd-container.service --now

	# Generate and enable systemd units
	# Therefore, they will start on next boot, run, and disable themselves
	# Installing the security layer will require two reboots, one for the domain enrollment and one to move to userland.
	echo -e "[Unit]
Description=Install Dependencies
ConditionPathExists=/var/rpm-ostree-overlay.rpmfusion.pkgs.complete
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c "/usr/local/bin/wavelet_install_ug_depends.sh"
ExecStartPost=systemctl disable wavelet_install_depends.service
[Install]
WantedBy=multi-user.target" > /etc/systemd/system/wavelet_install_depends.service

	echo -e "[Unit]
Description=Install PXE support
ConditionPathExists=/var/wavelet_depends.complete
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c "/usr/local/bin/wavelet_pxe_grubconfig.sh"
ExecStartPost=systemctl disable wavelet_install_pxe.service
[Install]
WantedBy=multi-user.target" > /etc/systemd/system/wavelet_install_pxe.service

	if [[ -f /var/prod.security.enabled ]]; then
		echo -e "Generating systemd unit for security layer.."
		echo -e "[Unit]
Description=Install Security Layer
ConditionPathExists=/var/prod.security.enabled
ConditionPathExists=/var/wavelet_depends.complete
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c "/usr/local/bin/wavelet_install_hardening.sh"
ExecStartPost=systemctl disable wavelet_install_hardening.service
[Install]
WantedBy=multi-user.target" > /etc/systemd/system/wavelet_install_hardening.service
	fi
	# wavelet_install_depends.service will then run, and force enable wavelet_install_pxe.service
	# wavelet_pxe_install.service will complete the root portion of the server spinup
	# OR
	# It will detect the security layer flag and call wavelet_install_hardening.sh, then reboot allowing build_ug.sh to run in userspace.

	# Start installing ostree updates via OCI container image
	detect_custom_requirements
	# generate a hostname file so that dnsmasq's dhcp-script call works properly
	get_ipValue
	systemctl disable systemd-resolved.service --now
	sed -i "s/SVR_IPADDR/${IPVALUE}/g" /etc/dnsmasq.conf

	domain=$(dnsdomainname)
	gateway=$(read _ _ gateway _ < <(ip route list match 0/0); echo "$gateway")

	echo -e "# The domain directive is only necessary, if your local
	     # router advertises something like	localdomain and	you have
	     # set up your hostnames via an external domain.
	     domain ${domain}
	     # In case you a running a local dns server	or caching name	server
	     # like local-unbound(8) for example.
	     nameserver	127.0.0.1
	     # IP address of the local or ISP name service
	     nameserver	${gateway}
	     # quad9 as fallback
	     nameserver	9.9.9.9" > /etc/resolv.conf
	systemctl enable dnsmasq.service --now
	systemctl enable wavelet_install_depends.service
	touch /var/no.wifi
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

determine_ifSurface(){
	# We already know we're x86, now we check to see if we're a Surface and that extended overlays should be built.
	# Ref https://github.com/linux-surface/linux-surface
	if [[ ${determination} == 1 ]]; then
		echo "This device is a surface, proceeding to pull a CoreOS overlay based off the Surface Kernel..\n"
			if [[ -f /var/extended_x86_support.flag ]]; then
				echo -e "Extended x86 support is enabled, building surface kernel container overlay..\n"
				rpm_ostree_surfaceKernel
			else
				echo -e "Extended x86 device support is DISABLED.  We will not build additional coreos overlays and utilize the standard overlay instead..\n"
				rpm_overlay_install_decoder
			fi
	else
		echo -e "This platform has some microsoft identifiers, but does not appear to be a Surface device, reverting to standard ostree overlay.."
		rpm_overlay_install_decoder
	fi
}

detect_custom_requirements(){
	echo -e "platform is ${platform} \n"
	case ${platform} in
	*Dell*)                 echo -e "platform is Dell, no special additions needed..\n"					;	touch /var/platform.dell && rpm_overlay_install
	;;
	*icrosoft*)				echo -e "platform is Microsoft, probing for Surface specific devices..\n"	;	determine_ifSurface
	;;
	*)                      echo -e "platform is generic and requires no special additions..\n" 		;	rpm_overlay_install
	;;
	esac
}

rpm_overlay_install(){
	echo -e "Installing via container and applying as Ostree overlay..\n"
	DKMS_KERNEL_VERSION=$(uname -r)
	# Shamelessly stolen from;
	# https://github.com/icedream/customizepkg-config/blob/main/decklink.patches/0001-Add-signing-key-generation-post-install-secure-boot-.patch
	cat > "/home/wavelet/containerfiles/openssl.cnf" << EOF
HOME        = /var/lib/blackmagic
RANDFILE    = /var/lib/blackmagic/.rnd

[ req ]
distinguished_name      = req_distinguished_name
x509_extensions   = v3_ca
string_mask       = utf8only

[ req_distinguished_name ]

[ v3_ca ]
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always,issuer
basicConstraints  = critical,CA:FALSE

# We use extended key usage information to limit what this auto-generated
# key can be used for.
#
# codeSigning:  specifies that this key is used to sign code.
#
# 1.3.6.1.4.1.2312.16.1.2:  defines this key as used for module signing
#         only. See https://lkml.org/lkml/2015/8/26/741.
#
extendedKeyUsage  = codeSigning,1.3.6.1.4.1.2312.16.1.2
nsComment         = "OpenSSL Generated Certificate"
EOF
	echo ':: A certificate to sign the driver has been created at /var/lib/blackmagic/MOK.der. This certificate needs to be enrolled if you run Secure Boot with validation (e.g. shim).'
	echo -e "\nPlease run:\nmokutil --import '/var/lib/blackmagic/MOK.der'\nIn order to enroll the MOK key!!"
	# Podman build, tags the image, uses DKMS_KERNEL_VERSION to parse host OS kernel version into container
	# The first stage builds the container with the necessary software to run as a decoder/encoder
	# The second stage adds everything necessary for the server.
	# We do this two-stage process to keep the overlay size down as much as we can
	podman build -t localhost/coreos_overlay_client \
	--build-arg DKMS_KERNEL_VERSION=${DKMS_KERNEL_VERSION} \
	-v=/home/wavelet/containerfiles:/mount:z \
	-f /home/wavelet/containerfiles/Containerfile.coreos.overlay.client
	podman tag localhost/coreos_overlay_client localhost:5000/coreos_overlay_client:latest
	touch /var/rpm-ostree-overlay.complete
	touch /var/rpm-ostree-overlay.rpmfusion.repo.complete
	touch /var/rpm-ostree-overlay.rpmfusion.pkgs.complete
	# Push client image to container registry - N.B can only use --compress with dir: transport method. 
	podman push localhost:5000/coreos_overlay_client:latest 192.168.1.32:5000/coreos_overlay_client --tls-verify=false	
	# Build the server overlay
	podman build -t localhost/coreos_overlay_server \
	--build-arg DKMS_KERNEL_VERSION=${DKMS_KERNEL_VERSION} \
	-v=/home/wavelet/containerfiles:/mount:z \
	-f /home/wavelet/containerfiles/Containerfile.coreos.overlay.server
	podman tag localhost/coreos_overlay_server localhost:5000/coreos_overlay_server:latest
	# We don't need to push the server overlay to the registry, because this it the only host which will use it.
	# Rebase server on server overlay image
	rpm-ostree rebase ostree-unverified-image:containers-storage:localhost:5000/coreos_overlay_server
	echo -e "\nRPM package updates completed, finishing installer task and checking for extended support..\n"
}

rpm_ostree_surfaceKernel(){
	# Surface kernel will require MOK for running a nonstandard kernel.
	DKMS_KERNEL_VERSION=$(uname -r)
	# Shamelessly stolen from;
	# https://github.com/icedream/customizepkg-config/blob/main/decklink.patches/0001-Add-signing-key-generation-post-install-secure-boot-.patch
	cat > "/home/wavelet/containerfiles/openssl.cnf" << EOF
HOME        = /var/lib/blackmagic
RANDFILE    = /var/lib/blackmagic/.rnd

[ req ]
distinguished_name      = req_distinguished_name
x509_extensions   = v3_ca
string_mask       = utf8only

[ req_distinguished_name ]

[ v3_ca ]
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always,issuer
basicConstraints  = critical,CA:FALSE

# We use extended key usage information to limit what this auto-generated
# key can be used for.
#
# codeSigning:  specifies that this key is used to sign code.
#
# 1.3.6.1.4.1.2312.16.1.2:  defines this key as used for module signing
#         only. See https://lkml.org/lkml/2015/8/26/741.
#
extendedKeyUsage  = codeSigning,1.3.6.1.4.1.2312.16.1.2
nsComment         = "OpenSSL Generated Certificate"
EOF
	echo ':: A certificate to sign the driver has been created at /var/lib/blackmagic/MOK.der. This certificate needs to be enrolled if you run Secure Boot with validation (e.g. shim).'
	echo -e "\nPlease run:\nmokutil --import '/var/lib/blackmagic/MOK.der'\nIn order to enroll the MOK key!!"
	podman build -t localhost/coreos_overlay \
	--build-arg DKMS_KERNEL_VERSION=${DKMS_KERNEL_VERSION} \
	-v=/home/wavelet/containerfiles:/mount:z \
	-f /home/wavelet/containerfiles/Containerfile.surface.coreos.overlay
	podman tag localhost/coreos_overlay localhost:5000/coreos_overlay_surface
	touch /var/rpm-ostree-overlay.complete
	touch /var/rpm-ostree-overlay.rpmfusion.repo.complete
	touch /var/rpm-ostree-overlay.rpmfusion.pkgs.complete
	# N.B can only use --compress with dir: transport method. zstd would be pretty cool, no? 
	podman push localhost:5000/coreos_overlay_surface:latest 192.168.1.32:5000/coreos_overlay_surface --tls-verify=false
}

rpm_ostree_ARM(){
	# We are building ARM version here, so the containerfile would specify arm-specific libraries for multiple proprietary platforms.  
	# Unless panfrost made some major progress on mainline hw video acceleration, this would need A LOT of work...
	if [[ -f /var/arm_support.flag ]]; then
		echo -e "ARM support is enabled, building ARM OCI overlay and downloading additional UltraGrid build..\n"
	else
		echo -e "ARM support is NOT enabled, and we are running on an ARM device.  Exiting.\n"; exit 1
	fi
	podman build -t localhost/coreos_overlay \
	--build-arg DKMS_KERNEL_VERSION=${DKMS_KERNEL_VERSION} \
	-v=/home/wavelet/containerfiles:/mount:z \
	-f /home/wavelet/containerfiles/Containerfile.arm.coreos.overlay.client
	podman tag localhost/coreos_overlay localhost:5000/coreos_overlay_arm_client
	touch /var/rpm-ostree-overlay.complete
	touch /var/rpm-ostree-overlay.rpmfusion.repo.complete
	touch /var/rpm-ostree-overlay.rpmfusion.pkgs.complete
	# N.B can only use --compress with dir: transport method. zstd would be pretty cool, no? 
	podman push localhost:5000/coreos_overlay_surface:latest 192.168.1.32:5000/coreos_overlay_arm_client --tls-verify=false
}

rpm_ostree_RISCV(){
	# We are building RISCV version here, so the containerfile would specify libraries for RISC-V target platforms.  This would need A LOT of work...
	podman build -t localhost/coreos_overlay \
	--build-arg DKMS_KERNEL_VERSION=${DKMS_KERNEL_VERSION} \
	-v=/home/wavelet/containerfiles:/mount:z \
	-f /home/wavelet/containerfiles/Containerfile.RISCV.coreos.overlay.client
	podman tag localhost/coreos_overlay localhost:5000/coreos_overlay_RISCV_client
	touch /var/rpm-ostree-overlay.complete
	touch /var/rpm-ostree-overlay.rpmfusion.repo.complete
	touch /var/rpm-ostree-overlay.rpmfusion.pkgs.complete
	# N.B can only use --compress with dir: transport method. zstd would be pretty cool, no? 
	podman push localhost:5000/coreos_overlay_surface:latest 192.168.1.32:5000/coreos_overlay_RISCV_client --tls-verify=false
}

rpm_overlay_install_decoder(){
	# This differs from the server in that we don't need to build the container,
	# We pull the client installer module and run it to generate the wavelet files in /usr/local/bin
	#dmidecode | grep "Manufacturer" | cut -d ':' -f 2 | head -n 1
	echo -e "Generating client install service systemd entry.."
	echo -e "[Unit]
Description=Install Client Dependencies
ConditionPathExists=/var/rpm-ostree-overlay.rpmfusion.pkgs.complete
After=multi-user.target
[Service]
Type=oneshot
ExecStartPre=/usr/bin/bash -c 'curl -o /usr/local/bin/wavelet_install_client.sh http://192.168.1.32:8080/ignition/wavelet_install_client.sh && chmod 0755 /usr/local/bin/wavelet_install_client.sh'
ExecStart=/usr/bin/bash -c '/usr/local/bin/wavelet_install_client.sh'
[Install]
WantedBy=multi-user.target" > /etc/systemd/system/wavelet_install_client.service
	systemctl daemon-reload
	# and we pull the already generated overlay from the server registry
	# This is the slowest part of the process, can we speed it up by compressing the overlay?
	echo -e "Installing via container and applying as ostree overlay..\n"
	# We need to pull the container from the server registry first, apparently manually?  Probably https issue here.
	podman pull 192.168.1.32:5000/coreos_overlay_client --tls-verify=false 
	rpm-ostree rebase ostree-unverified-image:containers-storage:192.168.1.32:5000/coreos_overlay_client
	touch /var/rpm-ostree-overlay.complete
	touch /var/rpm-ostree-overlay.rpmfusion.repo.complete && \
	touch /var/rpm-ostree-overlay.rpmfusion.pkgs.complete && \
	touch /var/rpm-ostree-overlay.dev.pkgs.complete
	echo -e "RPM package updates completed, finishing installer task..\n"
	echo -e "Client install service will run on next reboot to populate wavelet modules and configure networking."
	systemctl enable wavelet_install_client.service
	echo -e "Starting decoder hostname randomizer, this is the final step in the first boot, and will reboot the client machine.."
	systemctl start decoderhostname.service
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