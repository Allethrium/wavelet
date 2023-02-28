#!/bin/bash
#
# This script sets up a system to be a Wavelet decoder
#
# It assumes the following;
#
#	Machine is already imaged with an Ubuntu or Debian os
#	Machine is connected to a wavelet network (via ethernet) and to an internet network (via wifi)
#	Machine hostname is properly set for the target room.
#	Naming convention is:  dec$.type (vim1s, vim3, edge2, opt7090) .dept (part3, mis). room (357m). loc (60C) . wavelet.local
#	The Wavelet server depends on an accurate hostname in order to enumerate the new decoder... or it will eventually when I've written that part.
#
# Very simple here - just needs a lightweight gui like sway, Ultragrid 1.7+ appimage and nothing else.
# needs root priveleges

sudo apt install ffmpeg* sway swaybg waybar swayimg libasound2-dev uuid-dev libopencv-dev libglew-dev freeglut3-dev libgl1-mesa-dev libglfw3-dev libjack-jackd2-dev libavcodec-dev libavutil-dev libssl-dev libopencv-dev libcurl4-nss-dev libsdl2-dev nodm libsoxr-dev libspeexdsp-dev libvulkan-dev libv4l-dev foot mplayer vim powerline tuned build-essential libsrt-openssl-dev automake autogen make libsdl2-2.0-0 libsdl2-gfx-dev libsdl2-image-2.0-0 fonts-font-awesome fonts-lato libjs-sphinxdoc libjs-underscore powerline-doc powerline-gitstatus python3-powerline-gitstatus sphinx-rtd-theme-common-y

sudo apt autoremove

# 
#
# setup system hostname, network profile, IP 
# this should be done as part of the basic board bringup and is probably out of scope for the setup script
#
# add Wavelet UID/user with password
useradd wavelet -s /bin/bash -m 
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
SendSIGHUP=yes" > /lib/systemd/system/getty@tty1.service

# enable linger so wavelet user can manage systemd without being logged in

loginctl enable-linger wavelet

# create user systemd service so that wavelet can start and stop the systemd services

mkdir -p /home/wavelet/.config/systemd/user

# start decoder service

echo "[Unit]
Description=Wavelet decoder viewer service

[Service]
ExecStart=/home/wavelet/start_decoder.sh
WorkingDirectory=/home/wavelet/" > ~/.config/systemd/user/wavelet_start_decoder.service

# Ensure Sway starts on autologin

echo "if [ -z "${DISPLAY}" ] && [ "${XDG_VTNR}" -eq 1 ]; then
  exec sway
fi" >> /etc/profile

# start decoder-livestream service

echo "[Unit]
Description=Wavelet decoder viewer service

[Service]
ExecStart=/home/wavelet/start_decoder_libvestream.sh
WorkingDirectory=/home/wavelet/" > ~/.config/systemd/user/wavelet_start_decoder_livestream.service


# add powerline to system bashrc

echo 'powerline-daemon -q
POWERLINE_BASH_CONTINUATION=1
POWERLINE_BASH_SELECT=1
. /usr/share/powerline/bindings/bash/powerline.sh' >> /etc/bash.bashrc

# Generate bash systemd unit for decoders
mkdir -p /home/wavelet/.config/systemd/user
echo "[Unit]
Description=Wavelet decoder viewer service
After=network.target

[Service]
Type=simplei
Environment=SDL_VIDEODRIVER=wayland
#Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=wayland-1
ExecStop=/usr/bin/pkill -u %i -x uv
ExecStart=uv -d sdl:fs 
WorkingDirectory=/home/wavelet/

[Install]
WantedBy=multi-user.target" > /home/wavelet/.config/systemd/user/wavelet_start_decoder.service


# Generate bash script for decoder + prompt for livestream
# capture filter is encoder-only, so we basically can only add a red border to show it's recording.
# to do differently would require the capability of switching the capture filter on the encoder without disrupting its output.
mkdir -p /home/wavelet/.config/systemd/user
echo "[Unit]
Description=Wavelet decoder viewer service
After=network.target

[Service]
Type=simplei
Environment=SDL_VIDEODRIVER=wayland
#Environment=DISPLAY=:0
Environment=WAYLAND_DISPLAY=wayland-1
ExecStop=/usr/bin/pkill -u %i -x uv
#Capture filter works only on ENCODER
#ExecStart=uv --capture-filter logo:/home/wavelet/livestream_watermark.pam:1850:1000 -d sdl:fs
ExecStart=uv -p border:color=#ff0000:width=20==8 -d sdl:fs 

[Install]
WantedBy=multi-user.target
WorkingDirectory=/home/wavelet/" > /home/wavelet/.config/systemd/user/wavelet_start_decoder_livestream.service


# Build Ultragrid.  
# Why am I doing this instead of using the appimage?
# Basically, the AppImage doesn't appear to work properly.  Eventually I will be working out how to cross-compile for appropriate targets and export as a container
# For now, initial setup has to involve a local build of the application.

cd /home/wavelet/
git clone https://github.com/CESNET/UltraGrid

cd UltraGrid

#build on debian

./autogen.sh
make 
make install


# copy SSH keys
# disable SSH password auth
# apt install packages and QoL improvements
# tweak system performance tuning
#
#systemctl enable tuned --now


# reload all systemd units, su to wavelet and reload user systemd units
systemctl daemon-reload

sudo -i -u wavelet bash << EOF
echo "In"
systemctl --user daemon-reload
EOF
echo "Out"

# integration test with wavelet server
# integration test with wavelet encoder
# done.
