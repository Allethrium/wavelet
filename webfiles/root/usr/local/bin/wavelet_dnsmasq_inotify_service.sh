#!/bin/bash
# monitors directory for .lease file creation and calls script to handle when this happens.

while true; do
	inotifywait -m --include '.*\.lease' -e modify,create /var/tmp | while read file; do
		/usr/local/bin/wavelet_network_device.sh "$file" &
	done
done