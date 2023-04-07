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
dnf install -y alsa-lib-devel mesa-libOpenCL-devel pipewire-jack-audio-connection-kit-devel pipewire-jack-audio-connection-kit  mesa-libGL-devel freeglut-devel glfw-devel ffmpeg-devel openssl-devel portaudio-devel opencv-devel libcurl-devel SDL2 soxr-devel speexdsp-devel vulkan-loader-devel SDL2_gfx-devel SDL2-devel libv4l-devel GraphicsMagick-devel ImageMagick-devel live555 live555-devel live555-tools ndi-sdk-devel libndi-devel ffmpeg vlc rav1e svt-av1 gstreamer1-rtsp-server-devel gpac intel-media-driver intel-gmmlib intel-mediasdk libva libva-utils libva-intel-driver libva-intel-hybrid-driver gstreamer1-plugins-* intel-gpu-tools mesa-dri-drivers mpv libsrtp srt-devel srt-libs srt sshpass buildah python3-pip

# Not needed if hostname properly set during installation (Oooh, can I just do all this with an Anaconda/cloud automation script? look into it..
# sudo hostname dec.box.mis.357m.60C.wavelet.local

echo 'if [ -f `which powerline-daemon` ]; then
  powerline-daemon -q
  POWERLINE_BASH_CONTINUATION=1
  POWERLINE_BASH_SELECT=1
  . /usr/share/powerline/bash/powerline.sh
fi;' >> /etc/skel/.bashrc

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

# poke a hole in the firewall for UltraGrid
firewall-cmd --permanent --add-port=5004/tcp
firewall-cmd --permanent --add-port=5004/udp
firewall-cmd --reload

# Build Ultragrid.  
# Why am I doing this instead of using the appimage?
# Basically, the AppImage doesn't appear to work properly.  Eventually I will be working out how to cross-compile for appropriate targets and export as a container
# For now, initial setup has to involve a local build of the application.
cd /home/wavelet/Downloads
git clone https://github.com/CESNET/UltraGrid 
git clone https://github.com/hellerf/EmbeddableWebServer
cp /home/wavelet/Downloads/EmbeddableWebServer/EmbeddableWebServer.h ./UltraGrid/
cd UltraGrid

#build
./autogen.sh
# for faster build use
# make -j$(nproc) 
# this sometimes breaks on the ARM boards.  Since this is the controller and will almost certainly be a PC, we will build quickly.
make -j$(nproc)
# install the binaries to /usr/bin and set aliases so they can be invoked without a path
make install
echo "UltraGrid installed.."

# build LogKeys
# right now this build just seems to stop and wreck the entire process?
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
# Do I want to containerize DHCP and DNS together at some point?   Probably.. running a mini-domain might make more sense.
echo "# Wavelet svr config file for DNSmasq
# provides DHCP and DNS functionality for the extremely simple network
# # make sure DHCPD and systemd-resolved are both OFF
# domain-needed
# bogus-priv
# filterwin2k
# expand-hosts
# except-interface=Public_Access
# interface=eno2
# interface=lo
# listen-address=127.0.0.1,192.168.1.32
# user=dnsmasq
# group=dnsmasq
# domain=mis.357m.60c.wavelet.local
# local=/local./
# dhcp-range=192.168.1.8,192.168.1.31,12h
# dhcp-authoritative
# dhcp-rapid-commit
# cache-size=64
# server=9.9.9.9
# log-queries
# log-dhcp
#
# Ideally i'd like to use this to interrogate DNS records dynamically, but it might make more sense to simply label the devices intelligently and make assumptions on this end" >> /etc/dnsmasq.conf
systemctl disable systemd-resolved.service --now
firewall-cmd --permanent --add-service=dns
firewall-cmd --permanent --add-service=dhcp
firewall-cmd --reload
systemctl enable dnsmasq --now
echo "DNS and DHCP installed and enabled, Resolved service disabled.."

# tweak system performance tuning.
# reload systemd units
systemctl daemon-reload
systemctl enable tuned --now

# Wait so that devices can be plugged in
echo "Please plug in any Wavelet sense peripherals (keyboard, remote) NOW." 
read -p "Press any key to continue.."

su wavelet -c "sytemctl --user daemon-reload"
systemctl  enable wavelet-keylogger.service --now

# generate SSH key
# remove old keys first!
su wavelet -c "rm -f ~/.ssh/id_ed25519*"
su wavelet -c "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "wavelet@wavelet.local" -N ''"

# notify technician for WiFi connection
echo "Please join all decoders and encoders to the wavelet WiFi network now"
echo "nmcli dev wifi list"
echo "nmcli dev wifi connect LabWiFi password Lab2022-09"
echo "OR"
echo "nmcli con up LabWiFi"
read -p "Press any key to continue.." -n1 -s

# Right now I'm manually copying the SSH id keys during setup.  I would like to build this into the controller 
# So that the system can dynamically setup a properly control channel when new devices are detected.
# For my purposes right now, this is a list of the encoders, decoders, livestreamers and basically any other host
# That the controller needs to be able to target
# This might take a while because it just tries 1.4 through 1.32 in sequence and you'll have to wait for timeouts.  sorry.
# for some stupid reason, this thing has to have an implicit directory so i'm assuming its run from /mnt/
user="wavelet"
my_pass="WvltU$R60C"
while IFS="" read -r p || [ -n "$p" ]
do
  printf '%s\n' "$p" echo "updating $p"	
  su wavelet -c "sshpass -p'$my_pass' ssh-copy-id -o StrictHostKeyChecking=no -i ~/.ssh/id_ed25519.pub $user@$p"
  echo "client updated with keypair.."
done < /home/wavelet/Downloads/wavelet-git/clients.txt

# Setup controller systemd unit
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
prefix = "svr.mis.357m.60c.wavelet.local"
location = "192.168.1.32:5000"
insecure = true" > /etc/containers/registries.conf
systemctl restart podman
podman run --privileged -d --name registry -p 5000:5000 -v /var/lib/registry/:/var/lib/registry/ --restart=always registry:2

# Run as wavelet user, because Podman is designed to be rootless
su wavelet

# Build UltraGrid in container, push to local registry - did this because for UG Debian packages seem less finnicky.  Still can't get Live555 working.
buildah from debian
buildah run debian-working-container apt update
buildah run debian-working-container apt install ffmpeg* sway sway-backgrounds swaybg waybar libasound2-dev uuid-dev libopencv-dev libglew-dev freeglut3-dev libgl1-mesa-dev libglfw3-dev libjack-jackd2-dev libavcodec-dev libavutil-dev libssl-dev portaudio19-dev libopencv-dev libcurl4-nss-dev libsdl2-dev libx11-dev libsdl1.2-dev libsoxr-dev libspeexdsp-dev libvulkan-dev libv4l-dev foot mplayer libsrt-openssl-dev libsrtp2-dev vim powerline tuned build-essential python3-zfec wget git autoconf automake libtool pkgconf libmagickcore-6.q16-dev libmagickwand-6.q16-dev libmagickwand-dev python3-powerline-gitstatus sphinx-rtd-theme-common fonts-font-awesome fonts-lato libjs-sphinxdoc libjs-underscore powerline-doc powerline-gitstatus libsdl2-image-2* libsdl2-gfx-dev liblivemedia-* -y
buildah run debian-working-container git clone https://github.com/CESNET/UltraGrid
buildah run debian-working-container /UltraGrid/autogen.sh
buildah run debian-working-container make
buildah run debian-working-container make install
buildah run debian-working-container rm -rf UltraGrid
buildah run debian-working-container apt autoremove -y
# Might want to leave this part up to the decoder to sort out.. 
# buildah config --entrypoint "uv -d vulkan_sdl2:fs" debian-working-container
buildah commit debian-working-container ultragrid-viewer
podman push svr.mis.357m.60c.wavelet.local/ultragrid-viewer


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


#https://microshift.io/ ?



echo "To launch the server, restart the system"
