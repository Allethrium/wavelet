#!/bin/bash

DEVICE="/dev/$1"

if [[ -c "$DEVICE" ]]; then
    # Only set parameters that improve performance without breaking functionality
    # Disable compression if supported (for better quality/lower CPU)
    v4l2-ctl -d "$DEVICE" --set-ctrl=compression_quality=100 2>/dev/null || true
    # Set to highest quality mode available
    v4l2-ctl -d "$DEVICE" --set-ctrl=video_bitrate_mode=0 2>/dev/null || true  # VBR
    # Optimize for streaming (not recording)
    v4l2-ctl -d "$DEVICE" --set-ctrl=scene_mode=0 2>/dev/null || true  # None/auto
    # Keep autofocus/exposure enabled but tune them for streaming
    v4l2-ctl -d "$DEVICE" --set-ctrl=focus_auto=1 2>/dev/null || true
    v4l2-ctl -d "$DEVICE" --set-ctrl=exposure_auto=3 2>/dev/null || true  # Aperture priority
    # Set white balance to auto but faster convergence
    v4l2-ctl -d "$DEVICE" --set-ctrl=white_balance_temperature_auto=1 2>/dev/null || true
    # Disable power line frequency filtering if it causes frame drops
    v4l2-ctl -d "$DEVICE" --set-ctrl=power_line_frequency=0 2>/dev/null || true
    echo "$(date): Optimized V4L2 device $DEVICE" >> /var/log/wavelet_v4l2_optimize.log
fi
