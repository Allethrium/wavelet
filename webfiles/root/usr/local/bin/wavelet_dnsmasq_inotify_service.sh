#!/bin/bash
# monitors directory for .lease file creation and calls script to handle when this happens.

while true; do
	# We react only to created files, we don't do anything on deletion or even modification.
	inotifywait -m --include '.*\.lease' -e create /var/tmp | while read file; do
		/usr/local/bin/wavelet_network_device.sh "$file" &
	done
done