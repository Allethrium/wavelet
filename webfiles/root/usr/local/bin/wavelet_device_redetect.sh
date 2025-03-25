#!/bin/bash
#
# This script resets the appropriate flag back to 0 and then runs detectv4l.sh
# Detectv4l has self detection already built in, so this will run on everyone.

event(){
# Kill the systemd task for a few moments
echo -e "\nResetting redetect flag and starting device detection..\n"
/usr/local/bin/wavelet_detectv4l.sh
systemctl --user enable wavelet_device_redetect.service --now
echo -e "Task Complete\n"
# We do not reset the DEVICE_REDETECT flag to 0 here,
# because that would result in multiple writes from multiple different clients to the same key.
exit 0
}
read_etcd_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}") 
	echo -e "Key Name: {$KEYNAME} read from etcd for Global Value: $printvalue\n"
}

###
#
# Main 
#
###
#

#set -x
exec >/var/home/wavelet/logs/device-redetect.log 2>&1
hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)


# Check if redetect flag is 1
KEYNAME="DEVICE_REDETECT"; read_etcd_global
if [[ ${printvalue} = "1" ]]; then
	event
else
	echo "Redetect bit set to null, doing nothing!"
	exit 0
fi