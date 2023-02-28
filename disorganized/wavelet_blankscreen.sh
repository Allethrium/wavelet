#May need some udev rule to make sure it always maps to the right input device
#!/bin/bash

# I am a script executing display a static image to all decoders
# Check system log for execution status as is implemented as SystemD service

systemctl start ultragrid-blank.service
#
#/home/labuser/Downloads/UltraGrid-1.8-x86_64.AppImage -t file:/home/labuser/Downloads/dickbutt.jpg:loop -c libavcodec:encoder=hevc_vaapi:gop=2:bitrate=7M -P 5004 192.168.1.32
