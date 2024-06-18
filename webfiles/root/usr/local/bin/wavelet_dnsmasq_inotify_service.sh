#!/bin/bash
# monitors directory for .lease file creation and calls script to handle when this happens.

while true; do
    inotifywait -m -r --include '.*\.(?:lease)\..*' -e modify,create /var/lib/dnsmasq/leases | while read file; do
        ./wavelet_network_device_sense.sh "$file" &
    done
done