#!/bin/bash
# Version 0.1 - functional test unit
#
# This script sets up a system to be a Wavelet Controller appliance.   The machine will need to have fast network capability and relatively powerful CPU.  
#
# It assumes the following;
#
#	Machine is already imaged with an Ubuntu or Debian os
#	Machine is connected to a wavelet network (via ethernet) and to an internet network (via wifi)
#	Machine hostname is properly set for the target room.
#	Naming convention is:  livestream.type (vim1s, vim3, edge2, opt7090) .dept (part3, mis). room (357m). loc (60C) . wavelet.local
#	The Wavelet server depends on an accurate hostname in order to enumerate the new decoder... or it will eventually when I've written that part.
#
# Very simple here - just needs a lightweight gui like sway, Ultragrid 1.7+ appimage and nothing else.

# needs root priveleges

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Add self to hosts
echo "192.168.1.32	svr" > /etc/hosts

apt update && apt upgrade -y
# this apt command installs EVERYTHING.  Probably not needed and can be pared down. 
# Eventually when things are more settled maybe work out a way to deploy the binaries without building them
# on every single decoder and encoder like an idiot?
sudo apt install ffmpeg* sway sway-backgrounds swaybg waybar libasound2-dev uuid-dev libopencv-dev libglew-dev freeglut3-dev libgl1-mesa-dev libglfw3-dev libjack-jackd2-dev libavcodec-dev libavutil-dev libssl-dev portaudio19-dev libopencv-dev libcurl4-nss-dev libsdl2-dev libx11-dev libsdl1.2-dev libsoxr-dev libspeexdsp-dev libvulkan-dev libv4l-dev foot mplayer libsrt-openssl-dev libsrtp2-dev vim powerline tuned build-essential python3-zfec wget git build-essential autoconf automake libtool pkgconf libmagickcore-6.q16-dev libmagickwand-6.q16-dev libmagickwand-dev python3-powerline-gitstatus sphinx-rtd-theme-common fonts-font-awesome fonts-lato libjs-sphinxdoc libjs-underscore powerline-doc powerline-gitstatus libsdl2-image-2* libsdl2-gfx-dev build-essential autoconf automake libtool pkgconf -y

# remove this in deployment, right now its only to automate 
# decoder#,hwdescriptor,dept,room,location.wavelet.local
# sudo hostname dec.box.mis.357m.60C.wavelet.local

echo 'if [ -f `which powerline-daemon` ]; then
  powerline-daemon -q
  POWERLINE_BASH_CONTINUATION=1
  POWERLINE_BASH_SELECT=1
  . /usr/share/powerline/bash/powerline.sh
fi;' >> /etc/skel/.bashrc

#
# setup system hostname, network profile, IP 
# this should be done as part of the basic board bringup and is probably out of scope for the setup script
#
# add Wavelet UID/user with password
useradd -u 1337 wavelet -s /bin/bash -m 
chpasswd << 'END'
wavelet:WvltU$R60C
END

# we're operating in a specific directory structure under the wavelet user
# so we want all this stuff in specific places
mkdir -p /home/wavelet/.config/systemd/user
mkdir -p /home/wavelet/Downloads
chown -R wavelet:wavelet /home/wavelet
cd /home/wavelet/Downloads

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
SendSIGHUP=yes" > /lib/systemd/system/getty@.service/lib/systemd/system/getty@tty1.service


# Generate USER Systemd units for server
# Logkeys for input sense
echo "[Service]
Type=simple
Description=Logkeys based keylogger service to provide wavelet with input sense
After=network.target syslog.target
ExecStop=/usr/bin/pkill -u %i -x logkeys
ExecStart=logkeys -u -s -o /home/wavelet/Downloads/logkeys.log
WorkingDirectory=/home/wavelet/Downloads

[Install]
WantedBy=multi-user.target" > /home/wavelet/.config/systemd/user/wavelet-keylogger.service

# poke a hole in the firewall
firewall-cmd --permanent --add-port=5004/tcp
firewall-cmd --permanent --add-port=5004/udp
firewall-cmd --reload

# Build Ultragrid.  
# Why am I doing this instead of using the appimage?
# Basically, the AppImage doesn't appear to work properly.  Eventually I will be working out how to cross-compile for appropriate targets and export as a container
# For now, initial setup has to involve a local build of the application.
cd /home/wavelet/
git clone https://github.com/CESNET/UltraGrid && git clone https://github.com/hellerf/EmbeddableWebServer
cp EmbeddableWebServer/EmbeddableWebServer.h ./UltraGrid/
cd Ultragrid

#build on debian
./autogen.sh
# for faster build use
# make -j$(nproc) 
# this sometimes breaks on the ARM boards.
make
# install the binaries to /usr/bin and set aliases so they can be invoked without a path
make install

# build LogKeys
git clone https://github.com/kernc/logkeys
cd logkeys
./autogen.sh
cd build
../configure
make
make install
cd /home/wavelet/Downloads

# tweak system performance tuning.
# reload systemd units
systemctl daemon-reload
systemctl enable tuned --now
su wavelet

# Wait so that devices can be plugged in
echo "Please plug in any Wavelet sense peripherals (keyboard, remote) NOW." && wait 60

sytemctl --user daemon-reload
touch /home/wavelet/Downloads/logkeys.log
systemctl --user start wavelet-keylogger.service
./wavelet.controller.sh

# wavelet controller should be always aware of devices on the network, livestreamers, encoders, decoders, recorders.
# This means being aware of DNS cache and DNS cache changes
# Since its already an authoritative DHCP server, it should ALSO be the DNS server
# can we use dhcpd and dnsmasq?  or just dnsmasq?

# The alternative is use some kind of list/inventory file which must be manually updated.  I'd rather this was automatic, doesn't seem like something people should have to do.

# DNSMASQ
# cat /var/lib/dnsmasq/dnsmasq.leases
# sort this somehow and generate lists of decoder, encoder and other boxes, refresh upon new DHCP lease being assigned?
# maybe this makes more sense to run in the wavelet_controller.sh file given it's a "live" functionality?


