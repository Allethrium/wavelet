#!/bin/bash
# Resets the server
# This removes all the build flags,
# destroys the etcd cluster data,
# and reverts the server back to a "mint" condition before the build_ug module performs server bootstrap.
# Must be run as root
systemctl stop etcd-quadlet.service
/usr/bin/rm -rf /var/lib/etcd-data
/usr/bin/rm -rf /var/home/wavelet/{server_bootstrap_completed,encoder.firstrun,reflector_clients_ip.txt}
/usr/bin/systemctl reboot -i