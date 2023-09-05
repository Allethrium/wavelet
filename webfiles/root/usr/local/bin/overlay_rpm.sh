#!/bin/bash
set -x
echo -e "Installing RPMFusion and RPMFusion based dependencies for image manipulation and HW acceleration.."
rpm-ostree install -A --idempotent intel-media-driver intel-gpu-tools intel-compute-runtime \
			 oneVPL-intel-gpu intel-media-driver intel-gmmlib intel-mediasdk ocl-icd opencl-headers mpv libsrtp mesa-dri-drivers \
			 intel-opencl mesa-libOpenCL python3-pip srt srt-libs ffmpeg vlc libv4l v4l-utils libva-v4l2-request pipewire-v4l2 \
			 ImageMagick oneapi-level-zero oneVPL intel-gmmlib libva-utils mplayer

# Older drivers VAAPI <12th Gen CPU/Xe Core:
# libva libva-utils libva-intel-driver libva-intel-hybrid-driver

# VDPAU is terrible, don't use it.
# libvdpau libva-vdpau-driver mesa-vdpau-drivers