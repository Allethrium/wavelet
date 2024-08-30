#!/bin/bash

# PLACEHOLDER
# Wavelet Janitor service, cleans up old fusermount filesystems, call from crontab every 15 minutes or so?

# ps ax | grep for running UltraGrid instances
# mount -l | grep ".mount_appima" | awk -F " " '{print "fusermount -u " $3}' | bash
# compare these two outputs and unmount all but the running processes
# echo -e "Unmounted the following filesystems leftover from killed processes:\n"
# echo -e ${deadfilesystems}