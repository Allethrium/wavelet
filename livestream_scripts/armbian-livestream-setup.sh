#!/bin/bash
#
# This script sets up a system to be a Wavelet Livestream appliance.   The machine will need to have realtime 1080p/H.264 transcoding capability.  
#  I'd suggest a fast CPU or something # supporting VA-API
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

sudo apt install ffmpeg* \
sway \
sway-backgrounds \
swaybg \
swayimg \
waybar l\
ibasound2-dev \
uid-dev \
libopencv-dev \
libglew-dev \
freeglut3-dev \
libgl1-mesa-dev \
libglfw3-dev \
libjack-jackd2-dev \
libavcodec-dev \
libavutil-dev \
libssl-dev \
libopencv-dev \
libcurl4-nss-dev \
libgl1-mesa-dev \
libsdl2-dev \
libsdl1.2-dev \
libsoxr-dev \
libspeexdsp-dev \
libvulkan-dev \
libv4l2-dev \
#gstreamer1 \
foot \
mplayer \
srt\
vim \
powerline \
tuned \
build-essential
wait 1
sudo apt autoremove

# remove this in deployment, right now its only to automate 
sudo hostname livestream.box.mis.357m.wavelet.local
# 
#
# setup system hostname, network profile, IP 
# this should be done as part of the basic board bringup and is probably out of scope for the setup script
#
# add Wavelet UID/user with password
useradd wavelet -s /bin/bash -m -g $PRIMARYGRP -G $MYGROUP
chpasswd << 'END'
wavelet:WvltU$R60C
END

mkdir -p /home/wavelet
chown -R wavelet:wavelet /home/wavelet

#
# generate password
# 1000 bytes should be enough to give us 16 alphanumeric ones
#p=$(openssl rand 1000 | strings | grep -io [[:alnum:]] | head -n 16 | tr -d '\n')
# omit the "-1" if you want traditional crypt()
#usermod -p $(openssl passwd -5 "$p") wavelet
#output password so it's viewable for the next step
#cat $P > /home/wavelet_pw.txt
# set perms for PW to a secure setting
#chmod 600 /home/wavelet_pw.txt

# create autologin service for wavelet user
#
echo "[Service]
# the VT is cleared by TTYVTDisallocate
#                       ##ADDED THIS HERE##
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
# the VT is cleared by TTYVTDisallocate
#                       ##ADDED THIS HERE##
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

# Generate bash scripts for decoders

echo "#!/bin/bash
# Runs Ultragrid on graphical output
# kills existing uv instances
# runs FFMPEG to stream to output, requires a valid YouTube API key for this instance. 
kill $(pidof uv) 
DISPLAY=0:
uv -d gl:fs
RTMP_URL="rtmp://a.rtmp.youtube.com/live2"
STREAM_KEY="youtubeapikeygoeshere"
OUTPUT=$RTMP_URL/$STREAM_KEY
ffmpeg  -i http://localhost:8554/ug.sdp/dev/video0 -c:v libx264 -preset veryfast -maxrate 3000k -bufsize 6000k -pix_fmt yuv420p -g 50 -an -f flv $OUTPUT
echo "Wavelet Livestreaming started"
" > /home/wavelet/start_livestream.sh

# Generate bash script for ceasing livestream
#

echo "#!/bin/bash
# Runs Ultragrid on graphical output w/ graphical prompt
# kills existing uv instances
kill $(pidof uv) 
kill $(pidof ffmpeg*)
DISPLAY=0:
uv -d gl:fs
echo "Wavelet Livestreaming stopped"
" > /home/wavelet/stop_livestream.sh


# Build Ultragrid.  
# Why am I doing this instead of using the appimage?
# Basically, the AppImage doesn't appear to work properly.  Eventually I will be working out how to cross-compile for appropriate targets and export as a container
# For now, initial setup has to involve a local build of the application.

cd /home/wavelet/
wget https://github.com/CESNET/UltraGrid

cd Ultragrid

#build on debian

./autogen.sh
make
make install


# copy SSH keys
# disable SSH password auth
# apt install packages and QoL improvements
# tweak system performance tuning
#
systemctl enable tuned --now

# integration test with wavelet server
# integration test with wavelet encoder
# done.
