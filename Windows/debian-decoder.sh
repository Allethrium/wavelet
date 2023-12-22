#!/bin/bash
# Version 0.1 - functional test unit
#
# This script sets up a system to be a Wavelet Decoder appliance.   The machine will need to have realtime 1080p/H.264 transcoding capability.  
#  I'd suggest a fast CPU or something supporting VA-API
#
# It assumes the following;
#
#	Machine is already imaged with an Ubuntu or Debian os
#	Machine is connected to a wavelet network (via ethernet) and to an internet network (via wifi)
#	Machine hostname is properly set for the target room.
#	Naming convention is:  dec(number).type (vim1s, vim3, edge2, opt7090) .dept (part3, mis). room (357m). loc (60C) . wavelet.local
#	The Wavelet server depends on an accurate hostname in order to enumerate the new decoder... or it will eventually when I've written that part.
#
# Very simple here - just needs a lightweight gui like sway, Ultragrid 1.7+ appimage and nothing else.

# needs root priveleges

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# this apt command installs EVERYTHING.  Probably not needed and can be pared down. 
# Eventually when things are more settled maybe work out a way to deploy the binaries without building them
# on every single decoder and encoder like an idiot?
sudo apt install ffmpeg* sway sway-backgrounds swaybg waybar libasound2-dev uuid-dev libopencv-dev libglew-dev freeglut3-dev libgl1-mesa-dev libglfw3-dev libjack-jackd2-dev libavcodec-dev libavutil-dev libssl-dev portaudio19-dev libcurl4-nss-dev libsdl2-dev libx11-dev libsdl1.2-dev libsoxr-dev libspeexdsp-dev libvulkan-dev libv4l-dev foot mplayer libsrt-openssl-dev libsrtp2-dev vim powerline tuned build-essential python3-zfec wget git autoconf automake libtool pkgconf libmagickcore-6.q16-dev libmagickwand-6.q16-dev libmagickwand-dev python3-powerline-gitstatus sphinx-rtd-theme-common fonts-font-awesome fonts-lato libjs-sphinxdoc libjs-underscore powerline-doc powerline-gitstatus libsdl2-image-2* libsdl2-gfx-dev 

# remove this in deployment, right now its only to automate 
# decoder#,hwdescriptor,dept,room,location.wavelet.local
sudo hostname dec.box.mis.357m.60C.wavelet.local

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

mkdir -p /home/wavelet/.config/systemd/user
chown -R wavelet:wavelet /home/wavelet

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

# Generate USER Systemd units for decoders
# Ultragrid decoder to display
echo "[Service]
Type=simple
# These environment variables commonly need to be set to tell the service which display to use for output.  On a PC its not all that finnicky..usually
# They are dependent on numerous considerations like the available GPU acceleration.  Since I lean towards Sway for the display, we will always be using Wayland as a Display Manager.
# Display=:0 is a command that defines a display for an older DM called Xorg.  
#Environment=SDL_VIDEODRIVER=wayland
#Environment=DISPLAY=:0
#Environment=WAYLAND_DISPLAY=wayland-1
ExecStop=/usr/bin/pkill -u %i -x uv
# This will pull a stream out of UltraGrid and render it to screen.  Depending on your target platform, this can be
# a little sensitive.  gl is the most common working one.  sdl and vulkan_sdl2 can also work at a pinch.  use the cmd uv -d help to see what
# is available on the system once UltraGrid has been built.
# Future plans include template files so this won't be necessary once we work out what hardware we are using.
ExecStart=uv -d gl
WorkingDirectory=/home/wavelet/

[Install]
WantedBy=multi-user.target" > /home/wavelet/.config/systemd/user/wavelet-decoder.service

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


# tweak system performance tuning
# reload systemd units
systemctl daemon-reload
systemctl enable tuned --now
su wavelet
sytemctl --user daemon-reload

# wavelet livestream from this box can now be controlled by systemctl --user start wavelet-livestream-decoder.service && systemctl --user start wavelet-livestream.service, substitute with stop to stop them.  The controller should have this built in already.
# ssh keypairs need to be copied to this box from the server in order for a control channel to be established.
