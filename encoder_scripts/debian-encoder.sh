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
apt update -y && apt upgrade -y
apt install ffmpeg* sway sway-backgrounds swaybg waybar libasound2-dev uuid-dev libopencv-dev libglew-dev freeglut3-dev libgl1-mesa-dev libglfw3-dev libjack-jackd2-dev libavcodec-dev libavutil-dev libssl-dev portaudio19-dev libopencv-dev libcurl4-nss-dev libsdl2-dev libx11-dev libsdl1.2-dev libsoxr-dev libspeexdsp-dev libvulkan-dev libv4l-dev foot mplayer libsrt-openssl-dev libsrtp2-dev vim powerline tuned build-essential python3-zfec wget git build-essential autoconf automake libtool pkgconf libmagickcore-6.q16-dev libmagickwand-6.q16-dev libmagickwand-dev python3-powerline-gitstatus sphinx-rtd-theme-common fonts-font-awesome fonts-lato libjs-sphinxdoc libjs-underscore powerline-doc powerline-gitstatus libsdl2-image-2* libsdl2-gfx-dev v4l-utils -y

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

#v4l2-ctl --list-devices
#for I in /sys/class/video4linux/*; do cat $I/name; done


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
