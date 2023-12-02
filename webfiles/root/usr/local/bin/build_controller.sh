#!/bin/bash

#  Creates systemd dropins and other sundries required but not directly handled by Ignition oneshot services.
#   Think: UG runner service, reflector service etc.


# Create autologin because the ignition file just doesn't seem to get it right.
#mkdir -p /etc/systemd/system/getty@tty1.service.d/
#echo "[Service]
#ExecStart=
#ExecStart=-/usr/sbin/agetty --autologin wavelet --noclear %I $TERM" > /etc/systemd/system/getty@tty1.service.d/override.conf
cd /home/wavelet
wget https://andymelville.net/wavelet/wavelet_controller_alpha.sh
mkdir -p /home/wavelet/.config/systemd/user/
chown -R wavelet:wavelet /home/wavelet/
pwd
