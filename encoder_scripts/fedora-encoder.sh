#!/bin/bash
#
# This script sets up a system to be a Wavelet encoder.
#
# It is similar to the decoder script, however the generated systemd units are more numerous - one has to exist for each input
# additionally, the encoder runs a decal watermark that must be stopped/started when the system state changes
# This ensures a visual prompt exists E.G during livestreaming
#
#
# Run as root
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# initial install and update
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm && dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
dnf update -y

# start installing basic dependencies.
dnf install -y nasm ffmpeg vlc rav1e svt-av1 gstreamer1-rtsp-server-devel neofetch minicom gpac podman powerline powerline-fonts vim vim-powerline intel-media-driver intel-gmmlib intel-mediasdk libva libva-intel-driver libva-intel-hybrid-driver gstreamer1-plugins-* intel-gpu-tools mesa-dri-drivers mpv libva-utils libsrtp libsrtp-devel libsrtp-tools srt-devel srt-libs srt cockpit sway swaybg waybar tuned git alsa-lib-devel mesa-libOpenCL-devel pipewire-jack-audio-connection-kit mesa-libGL-devel freeglut-devel glfw-devel ffmpeg-devel openssl-devel portaudio-devel opencv-devel libcurl-devel SDL2 soxr-devel speexdsp-devel vulkan-loader-devel SDL2_gfx-devel SDL2-devel libv4l-devel GraphicsMagick-devel ImageMagick-devel pipewire-jack-audio-connection-kit-devel v4l-utils

dnf groupupdate -y multimedia --setop="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
dnf groupinstall -y "C Development Tools and Libraries"

# Add powerline to skel (Skeleton files, think programdata) so its there for allusers
echo 'if [ -f `which powerline-daemon` ]; then
  powerline-daemon -q
  POWERLINE_BASH_CONTINUATION=1
  POWERLINE_BASH_SELECT=1
  . /usr/share/powerline/bash/powerline.sh
fi;' >> /etc/skel/.bashrc

# Add Sway to skel
echo 'if [ -z "${DISPLAY}" ] && [ "${XDG_VTNR}" -eq 1 ]; then
  exec sway
fi' >> /etc/skel/.bashrc

# Add powerline-vim to skel
echo 'python3 from powerline.vim import setup as powerline_setup
python3 powerline_setup()
python3 del powerline_setup
set laststatus=2 " Always display the statusline in all windows
set showtabline=2 " Always display the tabline, even if there is only one tab
set noshowmode " Hide the default mode text (e.g. -- INSERT -- below the statusline)
set t_Co=256' >> /etc/skel/vimrc

useradd -u 1337 wavelet -s /bin/bash -m 
chpasswd << 'END'
wavelet:WvltU$R60C
END

# Makehomedirs.  This should be done automatically by useradd but i'm not leaving it to chance.
mkdir -p /home/wavelet
cd /home/wavelet/

# Replace with containerized workflow as soon as you get this up and running
# should look something like;
# 
git clone https://github.com/CESNET/UltraGrid
cd UltraGrid
./autogen.sh
make -j$(nproc)
make install

# I don't think we need to be signed in for the encoder to work so this will remain commented out.
#echo "[Service]
#ExecStart=-/sbin/agetty --noclear %I $TERM
#Type=idle
#Restart=always
#RestartSec=0
#UtmpIdentifier=%I
#TTYPath=/dev/%I
#TTYReset=yes
#TTYVHangup=yes
#TTYVTDisallocate=yes
#KillMode=process
#IgnoreSIGPIPE=no
#SendSIGHUP=yes" > /lib/systemd/system/getty@.service

#echo "[Service]
#ExecStart=-/sbin/agetty -a wavelet --noclear %I $TERM
#Type=idle
#Restart=always
#RestartSec=0
#UtmpIdentifier=%I
#TTYPath=/dev/%I
#TTYReset=yes
#TTYVHangup=yes
#TTYVTDisallocate=yes
#KillMode=process
#IgnoreSIGPIPE=no
#SendSIGHUP=yes" > /lib/systemd/system/getty@tty1.service

#loginctl enable-linger wavelet

# Throw in a couple of boot and performance optimizations
sed -i -e 's/dynamic_tuning = 0/dynamic_tuning = 1/g' /etc/tuned/tuned-main.conf
systemctl enable tuned --now
systemctl disable NetworkManager-wait-online.service --now
sed -i -e 's/GRUB_TIMEOUT=/GRUB_TIMEOUT=0/g' /etc/default/grub
dracut --regenerate-all --force


mkdir -p /home/wavelet/.config/systemd/user

# This is where I should be more clever.
# I'd like to call a script to enumerate attached capture devices via v4l2
# and automatically generate a systemd unit for each one
# even better, do something with udev rules!
# PULL THESE OFF THE MODEL ENCODER TOMORROW!!!

# This runs a viewer direct from the encoder.  It may run 4-5 frames ahead of the other devices, so it might not be a great idea.  we'll see.
echo "[Unit]
Description=Wavelet encoder viewer service
After=network.target

[Service]
Type=simple
ExecStop=/usr/bin/pkill -u %i -x uv
ExecStart=uv -d vulkan_sdl2:fs 
WorkingDirectory=/home/wavelet/

[Install]
WantedBy=multi-user.target" > /home/wavelet/.config/systemd/user/wavelet-encoder-viewer.service

# This implements a user systemd service for the primary document camera
# Configuration options are set via environment file from the controller, all other methods depreciated

echo "[Unit]
Description=Wavelet (UltraGrid) Encoder Service
After=network.target

[Service]
Type=simple
Restart=always
EnvironmentFile=/home/wavelet/uv_service.env
ExecStop=/usr/bin/pkill uv
ExecStart=uv $args (TO BE WRITTEN, UPDATE THIS BEFORE END OF WEEK)
WorkingDirectory=/home/wavelet/

[Install]
WantedBy=multi-user.target" > /home/wavelet/.config/systemd/user/wavelet_encoder_documentcamera.service


# This is the always-on service to capture audio.  Right now it is set to use a USB Jabra device but it will be configured to ingest Bluetooth from the Biamp devices already installed.
# After tests, audio latency with Ultragrid is too high.  We need to explore using JACK, PipeWire or some other low-latency option, and we need some useful echo cancellation (speex?)  
echo "[Unit]
Description=Wavelet Encoder - Audio Service
After=network.target

[Service]
Type=simple
ExecStop=/usr/bin/pkill -u %i -x uv
ExecStart=uv -s alsa:--audio-codec pcm -P 5006 192.168.1.32
WorkingDirectory=/home/wavelet/

[Install]
WantedBy=multi-user.target" > /home/wavelet/.config/systemd/user/wavelet_encoder_audio.service



chown -R 1337:root /home/wavelet

systemctl --user daemon-reload
fwupdmgr update

# Create system udev rules for known devices.  As hardware support grows, more devices will need to be 
# added to this list.
# reference: https://askubuntu.com/questions/354612/how-to-run-a-script-when-i-connect-a-device
# Does this make any sense?  https://github.com/doleron/v4l2-list-devices
# OK you need to learn udev rules properly.  You could symlink them
# https://wiki.archlinux.org/title/Udev
#
# But really maybe just rtfm?
# https://www.reactivated.net/writing_udev_rules.html#example-printer
#
#
# The problem is: we have no idea of the physical location and function of the device we're plugging in.  We only see vendor/product.
# How do we make it easy to define this information for a technician working on the application?
# Some QR code scanner that parses a test card input from each device and enumerates it as such during the setup phase
#
# Temporal - MUST plug in, in this order.  MUST keep track of devices removed and re-seated.   It seems too fragile for a full deployment though?
# Update - it seems V4L2 makes a best effort to maintain symlink stability with connected devices, ultimately working on this problem won't yield much value to i'm putting it to bed for now.
#
# Encoder can also function as a decoder without performance loss, so we can run it as a primary display someplace if necessary
#
# Logitech HDMI to USB screen capture device
#echo 'ACTION=="add", SUBSYSTEM=="usb", SYSFS{idVendor}=="046d",SYFS{idProduct}=="086c",RUN="/home/wavelet/Downloads/wavelet-git/encoder_scripts/logitechscreenshare.sh' >> /etc/udev/rules.d/85-logitechscreenshare.rules
# IPEVO Ziggi HD-Plus document camera
#echo 'ACTION=="add", SUBSYSTEM=="usb", SYSFS{idVendor}=="1778",SYFS{idProduct}=="0212",RUN="/home/wavelet/Downloads/wavelet-git/encoder_scripts/IPEVOZIggi-HDplus.sh' >> /etc/udev/rules.d/86-IPEVOZIggi-HDplus.rules
# Intel Bluetooth Audio dongle
# TBA
# Jabra handsfree Mic
#echo 'ACTION=="add", SUBSYSTEM=="usb", SYSFS{idVendor}=="0b0e",SYFS{idProduct}=="0410",RUN="/home/wavelet/Downloads/wavelet-git/encoder_scripts/GN.Netcom.JabraSPEAK410.sh' >> /etc/udev/rules.d/87-GN.Netcom.JabraSPEAK410.rules


echo "waiting ten seconds before system restart..." && wait 10

shutdown -r now

# stuff that should be done after this is completed:
# copy SSH keys from server to this machine
# disable SSH password auth, disable root login w/ PW
# integration test with wavelet server
# integration test with wavelet decoder
#
# done.
