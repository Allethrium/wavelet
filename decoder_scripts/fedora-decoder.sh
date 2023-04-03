#!/bin/bash
#
# This script sets up a system to be a Wavelet decoder
#
# Very simple here - just needs a lightweight gui like sway, Ultragrid 1.7+ appimage and nothing else.
# Assumes you have installed Fedora, connected to a network with internet access and you are running as root.
# 
#
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
usermod -aG video wavelet
usermod -aG render wavelet

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

loginctl enable-linger wavelet

sed -i -e 's/dynamic_tuning = 0/dynamic_tuning = 1/g' /etc/tuned/tuned-main.conf

systemctl enable tuned --now
systemctl disable NetworkManager-wait-online.service --now

sed -i -e 's/GRUB_TIMEOUT=/GRUB_TIMEOUT=0/g' /etc/default/grub

dracut --regenerate-all --force

mkdir -p /home/wavelet/.config/systemd/user

echo "[Unit]
Description=Wavelet decoder viewer service
After=network.target

[Service]
Type=simple
#These environment variables commonly need to be set to tell the service which display to use for output.  On a PC its not all that finnicky..usually
#They are dependent on numerous considerations like the available GPU acceleration.  Since I lean towards Sway for the display, we will always be using Wayland as a Display Manager.
#Display=:0 is a command that defines a display for an older DM called Xorg.  
#Environment=SDL_VIDEODRIVER=wayland
#Environment=DISPLAY=:0
#Environment=WAYLAND_DISPLAY=wayland-1
ExecStop=/usr/bin/pkill -u %i -x uv
ExecStart=uv -d vulkan_sdl2:fs 
WorkingDirectory=/home/wavelet/

[Install]
WantedBy=multi-user.target" > /home/wavelet/.config/systemd/user/wavelet_start_decoder.service

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


# ALT METHODS
# Podman container is now functional
install podman during setup
pull podman image
ensure wavelet user has group memberships for render and video groups
run podman container w/ entrypoint args and appropriate security settings
ensure selinux context set

