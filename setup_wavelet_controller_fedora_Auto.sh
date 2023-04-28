#!/bin/bash
# Version 0.1 - functional test unit
#
# This script sets up a system to be a Wavelet Controller appliance.   The machine will need to have fast network capability and relatively powerful CPU.  
#
# It assumes the following;
#
#	Machine is already imaged with Fedora or compatible RPM-based os
#	Machine is connected to a wavelet network (via ethernet) and to an internet network (via wifi)
#	Machine hostname is properly set for the target room.
#	Naming convention is:  livestream.type (vim1s, vim3, edge2, opt7090) .dept (part3, mis). room (357m). loc (60C) . wavelet.local
#	The Wavelet server depends on an accurate hostname in order to enumerate the new decoder... or it will eventually when I've written that part.
#

# TODO
# Proper DHCP interrogation and detection for the controller
# the automated SSH keypair copy doesn't work as expected.   Revisit
# you need to make a decision about what paths you're going to put in because not deciding between /mnt /mnt/usb and /home/wavelet/Downloads is killing you

echo "Run this script from the wavelet-git directory on your USB drive.  Everything is handled automatically from there."
echo "Running it from a different location will result in script failure."
echo "USB Drive can be found by running lsblk if necessary"
echo "USB drive can be mounted by sudo mount /dev/sd$ /mnt - where SD$ is the USB drive partition, usually the last, biggest partition as per lsblk"


# needs root privileges

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Add self to hosts
echo "192.168.1.32	svr" > /etc/hosts

# Request domain information OR populate from preconfigured file
# I guess i'd do this by prepopulating a file so we can check for its existence, if not do user input.
# 04-25-2023 ...Problem for future me.
generatedomain() {
echo 'Please enter the location information, this will be used to create the local domain'
read -p 'Enter the department, or Part Number in the format "mis" or "part52":' dept
read -p 'Enter the Room number of this deployment in the format "281", "359m" or similar:' room
read -p 'Enter the Building Location of this deployment in the format "60c", "80c" or similar:' building

domain=$dept.$room.$building.wavelet.local

read -p "Domain is configured as '$domain', is this correct? (y/n): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || echo "User cancelled, exiting.." exit 1
}

generatedomain
sudo hostname svr.$domain
echo "Domain variable is set to $domain, setting Wavelet server hostname to '$hostname'."

# These commands install everything necessary to build and run the server, fully.  Some may not be needed
# And will be removed during QA and hardening phases.
# Eventually when things are more settled maybe work out a way to deploy the binaries without building them
# on every single decoder and encoder like an idiot?
#
dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
dnf update -y

# Install useful packages and system QoL packages
dnf install -y nasm neofetch minicom podman powerline powerline-fonts vim vim-powerline cockpit sway swaybg waybar tuned git inotify-tools dnsmasq wget openssh-server

# Let's install dependencies for UltraGrid and other multimedia packages we might need
dnf groupupdate -y multimedia --setop="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
dnf groupinstall -y "C Development Tools and Libraries"
dnf install -y alsa-lib-devel mesa-libOpenCL-devel pipewire-jack-audio-connection-kit-devel pipewire-jack-audio-connection-kit  mesa-libGL-devel freeglut-devel glfw-devel ffmpeg-devel openssl-devel portaudio-devel opencv-devel libcurl-devel SDL2 soxr-devel speexdsp-devel vulkan-loader-devel SDL2_gfx-devel SDL2-devel libv4l-devel GraphicsMagick-devel ImageMagick-devel live555 live555-devel live555-tools ndi-sdk-devel libndi-devel ffmpeg vlc rav1e svt-av1 gstreamer1-rtsp-server-devel gpac intel-media-driver intel-gmmlib intel-mediasdk libva libva-utils libva-intel-driver libva-intel-hybrid-driver gstreamer1-plugins-* intel-gpu-tools mesa-dri-drivers mpv libsrtp srt-devel srt-libs srt sshpass buildah skopeo python3-pip qemu-user-static ipxe-bootimgs 

echo 'if [ -f `which powerline-daemon` ]; then
  powerline-daemon -q
  POWERLINE_BASH_CONTINUATION=1
  POWERLINE_BASH_SELECT=1
  . /usr/share/powerline/bash/powerline.sh
fi;' >> /etc/skel/.bashrc
cp /etc/skel/.bashrc 

#
# add Wavelet UID/user with password
useradd -u 1337 wavelet -s /bin/bash -m -d /home/wavelet
chpasswd << 'END'
wavelet:WvltU$R60C
END

# we're operating in a specific directory structure under the wavelet user
# so we want all this stuff in specific places
# since we tweaked Useradd above here, we might not need to manually do this now.
mkdir -p /home/wavelet/.config/systemd/user
mkdir -p /home/wavelet/Downloads
cp -R ./wavelet-git /home/wavelet/Downloads
cd /home/wavelet/Downloads
mkdir -p /lib/systemd/system/
mkdir -p /usr/local/man1
chown -R wavelet:wavelet /home/wavelet
echo "homedir directories created, chowned and wavelet application files copied to /home/wavelet/Downloads.."

# create autologin service for wavelet user
#
echo "[Service]
ExecStart=-/sbin/agetty --noclear %I $TERM
Type=idle
Restart=always
RestartSec=0
UtmpIdentifier=%I
TTYPath=/dev/%I
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
KillMode=process
IgnoreSIGPIPE=no
SendSIGHUP=yes" > /lib/systemd/system/getty@.service

echo "[Service]
ExecStart=-/sbin/agetty -a wavelet --noclear %I $TERM
Type=idle
Restart=always
RestartSec=0
UtmpIdentifier=%I
TTYPath=/dev/%I
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
KillMode=process
IgnoreSIGPIPE=no
SendSIGHUP=yes" > /lib/systemd/system/getty@tty1.service


# create logkeys file and chmod
touch /var/log/logkeys.log
chmod 755 /var/log/logkeys.log

# Generate USER Systemd units for server
# Logkeys for input sense
echo "[Service]
Type=forking
Description=Logkeys based keylogger service to provide wavelet with input sense
ExecStop=llkk
ExecStart=llk
WorkingDirectory=/var/log/

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/wavelet-keylogger.service

# poke a hole in the firewall for UltraGrid (5004) and Pipewire (3000)
firewall-cmd --permanent --add-port=5004/tcp
firewall-cmd --permanent --add-port=5004/udp
firewall-cmd --permanent --add-port=3000/tcp
firewall-cmd --permanent --add-port=3000/udp
firewall-cmd --reload


## Depreciated, we now use a container build.
# Build Ultragrid.  
# Why am I doing this instead of using the appimage?
# Basically, the AppImage doesn't appear to work properly.  Eventually I will be working out how to cross-compile for appropriate targets and export as a container
# For now, initial setup has to involve a local build of the application.
#cd /home/wavelet/Downloads
#git clone https://github.com/CESNET/UltraGrid 
#git clone https://github.com/hellerf/EmbeddableWebServer
#cp /home/wavelet/Downloads/EmbeddableWebServer/EmbeddableWebServer.h ./UltraGrid/
#cd UltraGrid
#
#build
#./autogen.sh
# for faster build use
# make -j$(nproc) 
# this sometimes breaks on the ARM boards.  Since this is the controller and will almost certainly be a PC, we will build quickly.
#make -j$(nproc)
# install the binaries to /usr/bin and set aliases so they can be invoked without a path
#make install
#echo "UltraGrid installed.."
## Depreciated, we now use a container build.

# build LogKeys
git clone https://github.com/kernc/logkeys
cd logkeys
./autogen.sh
cd build
../configure
make 
make install
cd /home/wavelet/Downloads
echo "input sense installed.."

# copy config and enable dnsmasq
# This will enable the controller to query new devices through DHCP and DNS, meaning they'll be controllable
# as long as their hostname is properly set.  We can dispense with a file of statically set IP addresses.
# Poke holes for DNS and DHCP in firewall
# directories are a problem here.. ugh just echo it overwriting the existing file.  Less muss, less fuss.
# Do I want to containerize DHCP and DNS together at some point?   Probably.. running a mini-domain might make more sense, especially if I wind up requiring WPA2-ENT/RADIUS/LDAP backend.
echo "
## Wavelet svr config file for DNSmasq
## provides DHCP and DNS functionality for the extremely simple network
## Make sure DHCPD and systemd-resolved are both OFF
domain-needed
bogus-priv
filterwin2k
expand-hosts
except-interface=Public_Access
interface=eno2
interface=lo
listen-address=127.0.0.1,192.168.1.32
user=dnsmasq
group=dnsmasq
domain='$domain'
local=/local./
dhcp-range=192.168.1.8,192.168.1.31,12h
dhcp-authoritative
dhcp-rapid-commit
cache-size=64
server=9.9.9.9
log-queries
log-dhcp
## Enable PXE
# enable built-in tftp server
enable-tftp
tftp-root=/tftpboot
# Tag dhcp request from iPXE
dhcp-match=set:ipxe,175
# inspect the vendor class string and tag BIOS client
dhcp-vendorclass=BIOS,PXEClient:Arch:00000
# 1st boot file - EFI client
# at the moment all non-BIOS clients are considered
# EFI client
dhcp-boot=tag:!ipxe,tag:!BIOS,ipxe.efi,10.1.0.1
# 2nd boot file
dhcp-boot=tag:ipxe,menu/boot.ipxe
#
## Ideally i'd like to use this to interrogate DNS records dynamically, but it might make more sense to simply label the devices intelligently and make assumptions on this end" >> /etc/dnsmasq.conf
systemctl disable systemd-resolved.service --now
systemdctl disable dhcpd --now
firewall-cmd --permanent --add-service=dns
firewall-cmd --permanent --add-service=dhcp
firewall-cmd --permanent --add-service=tftp 
firewall-cmd --reload
systemctl enable dnsmasq --now
echo "DNS and DHCP installed and enabled, Resolved service disabled.."

# reload systemd units
# tweak system performance tuning to an appropriate profile for network latency applications
systemctl daemon-reload
systemctl enable tuned --now
tuned-adm profile network-latency
#ip set eth0 mtu 9000

# Alter network buffer settings
Echo "# Extended network buffers for UltraGrid
net.core.wmem_max = 8388608
net.core.rmem_max = 72990720   # for uncompressed 8K" >/etc/sysctl.conf
sysctl -p

su wavelet -c "sytemctl --user daemon-reload"
systemctl  enable wavelet-keylogger.service --now

# generate a valid SSH key, copy this key to the http server directory
# remove old keys first!
su wavelet -c "rm -f ~/.ssh/id_ed25519*"
su wavelet -c "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "wavelet@wavelet.local" -N ''"
su wavelet -c "cp ~/.ssh/id_ed25519.pub ~/http/" 


## ToDo, work out this workflow. ##
# notify technician for WiFi connection
#echo "Please join all decoders and encoders to the wavelet WiFi network now"
#echo "nmcli dev wifi list"
#echo "nmcli dev wifi connect LabWiFi password Lab2022-09"
#echo "OR"
#echo "nmcli con up LabWiFi"
#read -p "Press any key to continue.." -n1 -s

# Right now I'm manually copying the SSH id keys during setup.  I would like to build this into the controller 
# So that the system can dynamically setup a properly control channel when new devices are detected.
# For my purposes right now, this is a list of the encoders, decoders, livestreamers and basically any other host
# That the controller needs to be able to target
# This might take a while because it just tries 1.4 through 1.32 in sequence and you'll have to wait for timeouts.  sorry.
# for some stupid reason, this thing has to have an implicit directory so i'm assuming its run from /mnt/
#user="wavelet"
#my_pass="WvltU$R60C"
#while IFS="" read -r p || [ -n "$p" ]
#do
  #printf '%s\n' "$p" echo "updating $p"	
  #su wavelet -c "sshpass -p'$my_pass' ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_ed25519.pub $user@$p"
  #echo "client updated with keypair.."
#done < /home/wavelet/Downloads/wavelet-git/clients.txt
#

## Setup controller systemd unit
# May want to execute the controller in a different fashion.
echo "[Service]
Type=forking
Description=Wavelet Controller service
ExecStart=/home/wavelet/Downloads/wavelet.controller.sh
WorkingDirectory=/home/wavelet/Downloads

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/wavelet-controller.service
systemctl enable wavelet-controller.service


# We may, or may not use this but we're going to setup a local container registry on the server so that containers can be composed and then pushed out to sources appropriately.
# This stuff isn't necessary unless we want to secure the registry... which might be a good idea for a production build, who knew?  Yes, that is a 10 year certificate.
# Don't need this if insecure registry

#sudo dnf install httpd-tools
#mkdir -p /var/lib/registry/{auth,certs,data}
#htpasswd -bBc /var/lib/registry/auth/htpasswd wavelet wavelet
#openssl req -newkey rsa:4096 -nodes -sha256 -keyout /var/lib/registry/certs/domain.key -x509 -days 3650 -out /var/lib/registry/certs/domain.crt


echo "[[registry]]
prefix = "svr.$domain"
location = "192.168.1.32:5000"
insecure = true" > /etc/containers/registries.conf
systemctl restart podman
podman run --privileged -d --name registry -p 5000:5000 -v /var/lib/registry/:/var/lib/registry/ --restart=always registry:2

# Run as wavelet user, because Podman is designed to be rootless
su wavelet

# Build UltraGrid in container, push to local registry - did this because for UG Debian packages seem less finnicky.  Still can't get Live555 working.
# Create buildah manifest file
		#echo "
		## Set your manifest name
		#export MANIFEST_NAME="multiarch-UltraGrid"

		## Set the required variables
		#export BUILD_PATH="backend"
		#export REGISTRY="hostname"
		#export USER="wavelet"
		#export IMAGE_NAME="UltraGrid"
		#export IMAGE_TAG="v0.0.1"

		## Create a multi-architecture manifest
		#buildah manifest create ${MANIFEST_NAME}

		## Build your amd64 architecture container
		#buildah bud \
		    #--tag "${REGISTRY}/${USER}/${IMAGE_NAME}:${IMAGE_TAG}" \
		    #--manifest ${MANIFEST_NAME} \
		    #--arch amd64 \
		    #${BUILD_PATH}

		## Build your arm64 architecture container
		#buildah bud \
		    #--tag "${REGISTRY}/${USER}/${IMAGE_NAME}:${IMAGE_TAG}" \
		    #--manifest ${MANIFEST_NAME} \
		    #--arch arm64 \
		    #${BUILD_PATH}
#
		## Push the full manifest, with both CPU Architectures
		#buildah manifest push --all \
		    #${MANIFEST_NAME} \
		    #"docker://${REGISTRY}/${USER}/${IMAGE_NAME}:${IMAGE_TAG}"
		#"

## Changing build process to Containers, and to support multiple architectures
## Utilizing buildah bud and a Containerfile
## Push to previously configured local registry
## Reference: https://podman.io/blogs/2021/10/11/multiarch.html - https://williamlam.com/2020/07/configuring-dnsmasq-as-pxe-server-for-esxi.html - https://ipxe.org/cmd
platarch=linux/amd64,linux/arm64
buildah bud --jobs=4 --platform=$platarch -f Containerfile.UltraGrid --manifest ultragrid .
buildah tag localhost/ultragrid svr.$domain/ultragrid
podman manifest rm localhost/ultragrid
podman manifest push --all svr.$domain/ultragrid docker://svr.$domain/ultragrid

#version='0.0.1'
#buildah from debian
#buildah run debian-working-container apt update
#buildah run debian-working-container apt install ffmpeg* sway sway-backgrounds swaybg waybar libasound2-dev uuid-dev libopencv-dev libglew-dev freeglut3-dev libgl1-mesa-dev libglfw3-dev libjack-jackd2-dev libavcodec-dev libavutil-dev libssl-dev portaudio19-dev libopencv-dev libcurl4-nss-dev libsdl2-dev libx11-dev libsdl1.2-dev libsoxr-dev libspeexdsp-dev libvulkan-dev libv4l-dev foot mplayer libsrt-openssl-dev libsrtp2-dev vim powerline tuned build-essential python3-zfec wget git autoconf automake libtool pkgconf libmagickcore-6.q16-dev libmagickwand-6.q16-dev libmagickwand-dev python3-powerline-gitstatus sphinx-rtd-theme-common fonts-font-awesome fonts-lato libjs-sphinxdoc libjs-underscore powerline-doc powerline-gitstatus libsdl2-image-2* libsdl2-gfx-dev liblivemedia-* -y
#buildah run debian-working-container git clone https://github.com/CESNET/UltraGrid
#buildah run debian-working-container /UltraGrid/autogen.sh
#buildah run debian-working-container make
#buildah run debian-working-container make install
#buildah run debian-working-container rm -rf UltraGrid
#buildah run debian-working-container apt autoremove -y
# Might want to leave this part up to the decoder to sort out.. 
# buildah config --entrypoint "uv -d vulkan_sdl2:fs" debian-working-container
#buildah commit debian-working-container UltraGrid:$version
#podman push svr.mis.357m.60c.wavelet.local/UltraGrid:$version
#buildah build --jobs=2 --pull --platform linux/arm64/v8,linuc/amd64  -t hostname/UltraGrid-arm64 .
#buildah build --pull --platform linux/amd64 -t hostname/UltraGrid-amd64 .
#buildah manifest create hostname/UltraGrid:UltraGrid:$version \
	#hostname/UltraGrid:0.0.1-linux-arm64 \
	#hostname/UltraGrid:0.0.1-linux-amd64
#buildah manifest push hostname/UltraGrid:$version docker://hostname/UltraGrid:$version
#buildah manifest rm hostname/UltraGrid:$version

# We should think about adding an appropriate CoreOS ignition file to enable WiFi on the decoder boxes.   This way we can further automate and have each decoder effectively self-provision with some jiggery-pokery.
# Notes for later:
# https://askubuntu.com/questions/456689/error-xdg-runtime-dir-not-set-in-the-environment-when-attempting-to-run-naut
# https://www.redhat.com/sysadmin/simple-container-registry
# https://www.redhat.com/sysadmin/7-transports-features
# https://www.redhat.com/sysadmin/files-devices-podman
# https://www.redhat.com/en/services/training/do080-deploying-containerized-applications-technical-overview?intcmp=701f20000012ngPAAQ
# https://www.fosslinux.com/49839/how-to-build-run-and-manage-container-images-with-podman.htm
# 
# Rabbit hole goes deeper - Fedora IoT / Zezere :
# https://github.com/fedora-iot/zezere
# https://blog.while-true-do.io/iot-fedora-ansible-podman/
# OK zezere is a no-go its been dead for three years... back to CoreOS...
#dnf install python3-pip 
#pip install virtualenv
#virtualenv venv
#pip install mod_wsgi-standalone
#pip install psycopg2-binary

#!/
WHERE AM I WITH THIS?
OK, 
	Need to work out etcd for persistence and spin it up on svr.wavelet.local 
		Bootstrapping, configuration etc. all needs to be learned
		CoreOS deployment is stuck until I have an ethernet/internet access solution
		Work on parsing command line params to UV container so our previous cmdline concatenation logic operates normally
		Test coreOS deployment for encoders, decoders
		Test coreOS deployment for livestreamers
		Pass functional deployment procedure to staff for testing
#!/




# Spin up HTTP server container and mount appropriate storage for CoreOS and .IGN files
su wavelet -c "mkdir -p /home/wavelet/http/media/ignition"
su wavelet -c "podman pull docker.io/library/httpd"
su wavelet -c "podman pull docker.io/library/nginx"

## Aquire necessary images.  This will take some time.
#echo "
# https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/37.20230401.3.0/x86_64/fedora-coreos-37.20230401.3.0-metal4k.x86_64.raw.xz
# https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/37.20230401.3.0/x86_64/fedora-coreos-37.20230401.3.0-live.x86_64.iso
# OK i don't know how to dynamically download the images.. set BASEURL https://builds.coreos.fedoraproject.org/prod/streams/${STREAM}/builds/${VERSION}/x86_64
#https://redirect.armbian.com/khadas-edge2/Bullseye_legacy
#https://redirect.armbian.com/khadas-vim2/Jammy_current
#https://redirect.armbian.com/odroidm1/Jammy_edge
#https://redirect.armbian.com/orangepi4-lts/Jammy_current
#" > /home/wavelet/images_list.txt
#su wavelet -c "cd /home/wavelet/http/media/"
#su wavelet -c "wget -i /home/wavelet/images_list.txt -q --show-progress"

## Create an array of imagers found in the media folder
#imagesArray="ls /home/wavelet/http/media"
## process array in turn to mount and copy installation files
#foreach $image in $imagesArray
	#do;
	#imageDirectory=awk (truncateimagename to something friendly)
	#mount -t iso9660 -o ro,loop $image /var/www/html/media/$imageDirectory

# Generate predifined ignition file
server=hostname
echo "
#
# Tutorial
# https://invidious.tinfoil-hat.net/watch?v=cvWN8dXHaVo
#
# https://rollout.io/blog/infrastructure-as-code/
# https://www.plutora.com/blog/infrastructure-as-code
# https://dzone.com/articles/observability-and-beyond-building-resilient-applic
#
# This file aims to provide a usable base CoreOS image which can run Encoder/Decoder/Livestreamer tasks effectively

{
  "ignition": { "version": "3.0.0" },
  variant: fcos,
  version: 1.5.0,
  "storage": {
    "files": [{
#	Sets hostname
      "path": "/etc/hostname",
      "mode": 420,
      "overwrite": true,
      "contents": { "source": "data:http://{server}/pxehostname.txt" }
#	Skel
		"path": "/etc/skel/.bashrc",
		"mode": 420,
		"overwrite": true,
		"contents": { "source": "data:hhttps://andymelville.net/wavelet/public/skel.txt" }
#	Udev_rules (ENCODER but installed on all boxes anyway)
		"path": "/etc/udev/rules.d/80-wavelet-encoder.rules",
		"mode": 420,
		"overwrite": true,
		"contents": { "source": "data:https://andymelville.net/wavelet/public/80-wavelet-encoder.rules" }
#	udev_call  (required otherwise udev blocks /dev/ tree access until trigger is complete)
		"path": "/home/wavelet/udev_call.sh",
		"mode": 420,
		"overwrite": true,
		"contents": { "source": "data:https://andymelville.net/wavelet/public/udev_call.sh" }
#	DetectV4l  (attempts to intelligently manage v4l devices with symlinks)
		"path": "/home/wavelet/detectv4l.sh",
		"mode": 420,
		"overwrite": true,
		"contents": { "source": "data:http://{server}/detectv4l.sh" }
    }]
  }
}

"passwd": {
    "users": [
      {
        "name": "wavelet-root",
        "uid": "9337",
        "passwordHash": "$6$nP0Rno68wE$kLZixz9bqOzUspYONNXvH21razOeqkkxo.325Q1pfWtuHWoSAHaoUVrbJ0oqYYjO7f4/Qs5U5HOpm2n6WFASO0",
        "home_dir": "/home/wavelet-root",
        #"sshAuthorizedKeys": [
        #  "ssh-rsa veryLongRSAPublicKey"
        #]
      },
      {
        "name": "wavelet",
        "uid": "1337",
        "passwordHash": "$6$0OV84d.JPTnYjv02$i8JnR90kRViFcTwjPKTB3g7p99DpIux8PJBI2n2ToNvcI7Epb1T2vLLRuansi8WQbxaQT7Ibl/RKWtAD5Otsz0",
        "home_dir": "/home/wavelet",
        #"sshAuthorizedKeys": [
        #  "ssh-rsa veryLongRSAPublicKey"
        #]
      }
     ]
}
  
"systemd": {
    "units": [{
      "name": "install-overlayed-rpms.service",
# Adding overlays to rpm-ostree is risky due to the push model used for providing server updates.
# Upstream testing will not have been performed on your specific combination of packages
# Mitigate this risk by having some servers running on the 'next' stream so that you know what's coming.
      "enabled": true,
      "contents": "[Unit]
      Description=Install Overlay Packages
      ConditionFirstBoot=yes
      Wants=network-online.target
      After=network-online.target
      After=multi-user.target
      
      [Service]
      Type=oneshot
      ExecStart=rpm-ostree install vim powerline powerline-fonts vim-powerline cockpit NetworkManager-wifi iw wireless-regdb wpa_supplicant etcd --reboot

      [Install]
      WantedBy=multi-user.target"
    }]
}
" > /home/wavelet/http/media/ignition/ignition_base.yaml

wget https://github.com/coreos/layering-examples/blob/main/wifi/Containerfile

# This command is necessary to generate an index.html static tree of files configured in the http server's folder.  For security reasons, allowing dynamic generation is disouraged.
# Yes, this means that the Wavelet deployment will be effectively locked to a single version.   This is by design, if you want to rebase to a newer OS kernel/version, you will need to **redeploy from scratch**
su wavelet -c "tree -H '.' -L 1 --noreport --dirsfirst -T 'Downloads' -s -D --charset utf-8 -o /home/wavelet/http/index.html"

# Spin up PXE server functionality and configure appropriately for server.
# Wavelet Encoder, Decoder are all the same CoreOS file, tweaks occur after installation
su wavelet -c "mkdir -p /home/wavelet/tftpboot"
su wavelet -c "mkdir -p /home/wavelet/tftpboot/menu"
chcon -t tftpdir_t /tftpboot
sudo cp /usr/share/ipxe/{ipxe.efi} /home/wavelet/tftpboot/
echo "
#!ipxe

:start
menu PXE Boot Options

item Fedora-CoreOS-Wavelet
item shell iPXE shell
item exit  Exit to EFI/BIOS

choose --default exit --timeout 10000 option && goto ${option}

:CoreOS
set STREAM stable
set VERSION 37.20230401.3.0
set INSTALLDEV /dev/nvme0
set CONFIGURL https://andymelville.net/wavelet/public/config.ign
set BASEURL https://builds.coreos.fedoraproject.org/prod/streams/${STREAM}/builds/${VERSION}/x86_64
kernel ${BASEURL}/fedora-coreos-${VERSION}-live-kernel-x86_64 initrd=main coreos.live.rootfs_url=${BASEURL}/fedora-coreos-${VERSION}-live-rootfs.x86_64.img coreos.inst.install_dev=${INSTALLDEV} coreos.inst.ignition_url=${CONFIGURL}
initrd --name main ${BASEURL}/fedora-coreos-${VERSION}-live-initramfs.x86_64.img
chain http://{localhost}/store_information.php?name=${name:uristring}&email=${email:uristring}
:shell
shell

:exit
exit
"



# Server should now be configured to properly streamline installation via CoreOS/Ignition/Podman for;
#	Encoder
#	Livestream proxy
#	Decoders

#	Think about adding etcd for persistent variable storage within the Wavelet system.  Enc/Dec hostnames, devicenames, command line params etc.

#https://microshift.io/ ?



echo "To launch the server, restart the system"
