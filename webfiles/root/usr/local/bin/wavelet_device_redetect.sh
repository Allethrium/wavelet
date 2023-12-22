#!/bin/bash
#
# This script resets the appropriate flag back to 0 and then runs detectv4l.sh
# Detectv4l has self detection already built in, so this will run on everyone.

#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
ETCDCTL_API=3

event(){
# Kill the systemd task for a few moments
systemctl --user stop wavelet-device-redetect.service
echo -e "\nResetting redetect flag and starting device detection..\n\n\n"
/usr/local/bin/wavelet_detectv4l.sh && wait 5
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
