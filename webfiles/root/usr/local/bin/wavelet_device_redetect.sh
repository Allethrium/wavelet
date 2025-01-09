#!/bin/bash
#
# This script resets the appropriate flag back to 0 and then runs detectv4l.sh
# Detectv4l has self detection already built in, so this will run on everyone.

event(){
# Kill the systemd task for a few moments
systemctl --user stop wavelet-device-redetect.service
echo -e "\nResetting redetect flag and starting device detection..\n\n\n"
/usr/local/bin/wavelet_detectv4l.sh && wait 3
systemctl --user enable wavelet-device-redetect.service --now
echo -e "\nTask Complete.\n"
exit 0
}

###
#
# Main 
#
###
#
event
