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
dnf install -y nasm ffmpeg vlc rav1e svt-av1 gstreamer1-rtsp-server-devel neofetch minicom gpac podman powerline powerline-fonts vim vim-powerline intel-media-driver intel-gmmlib intel-mediasdk libva libva-intel-driver libva-intel-hybrid-driver gstreamer1-plugins-* intel-gpu-tools mesa-dri-drivers mpv libva-utils libsrtp libsrtp-devel libsrtp-tools srt-devel srt-libs srt cockpit sway swaybg waybar tuned git alsa-lib-devel mesa-libOpenCL-devel pipewire-jack-audio-connection-kit mesa-libGL-devel freeglut-devel glfw-devel ffmpeg-devel openssl-devel portaudio-devel opencv-devel libcurl-devel SDL2 soxr-devel speexdsp-devel vulkan-loader-devel SDL2_gfx-devel SDL2-devel libv4l-devel GraphicsMagick-devel ImageMagick-devel pipewire-jack-audio-connection-kit-devel 

dnf groupupdate multimedia --setop="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
dnf groupinstall "C Development Tools and Libraries"

echo 'if [ -f `which powerline-daemon` ]; then
  powerline-daemon -q
  POWERLINE_BASH_CONTINUATION=1
  POWERLINE_BASH_SELECT=1
  . /usr/share/powerline/bash/powerline.sh
fi;' >> /etc/skel/.bashrc

echo 'if [ -z "${DISPLAY}" ] && [ "${XDG_VTNR}" -eq 1 ]; then
  exec sway
fi' >> /etc/skel/.bashrc

echo 'python3 from powerline.vim import setup as powerline_setup
python3 powerline_setup()
python3 del powerline_setup
set laststatus=2 " Always display the statusline in all windows
set showtabline=2 " Always display the tabline, even if there is only one tab
set noshowmode " Hide the default mode text (e.g. -- INSERT -- below the statusline)
set t_Co=256' >> ~/.vimrc

useradd -u 1337 wavelet -s /bin/bash -m 
chpasswd << 'END'
wavelet:WvltU$R60C
END

mkdir -p /home/wavelet
cd /home/wavelet/
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

sed -i -e 's/dynamic_tuning = 0/dynamic_tuning = 1/g' /etc/tuned/tuned-main.conf

systemctl enable tuned --now
systemctl disable NetworkManager-wait-online.service --now

sed -i -e 's/GRUB_TIMEOUT=/GRUB_TIMEOUT=0/g' /etc/default/grub

dracut --regenerate-all --force

mkdir -p /home/wavelet/.config/systemd/user

# This is where I should be more clever.
# I'd like to call a script to enumerate attached capture devices via v4l2
# and automatically generate a systemd unit for each on
# even better, do something with udev rules!
# PULL THESE OFF THE MODEL ENCODER TOMORROW!!!

echo "[Unit]
Description=Wavelet encoder viewer service
After=network.target

[Service]
Type=simple
ExecStop=/usr/bin/pkill -u %i -x uv
ExecStart=#uv - vulkan_sdl2:fs 
WorkingDirectory=/home/wavelet/

[Install]
WantedBy=multi-user.target" > /home/wavelet/.config/systemd/user/wavelet_start_encoder_deviceID.service

chown -R 1337:root /home/wavelet

systemctl --user daemon-reload
fwupdmgr update

echo "waiting ten seconds before system restart..." && wait 10

shutdown -r now

# stuff that should be done after this is completed:
# copy SSH keys from server to this machine
# disable SSH password auth, disable root login w/ PW
# integration test with wavelet server
# integration test with wavelet decoder
#
# done.
