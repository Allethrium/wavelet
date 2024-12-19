#!/bin/bash
# Simple module which adds a delay to firefox 
# Finds server IP address and adds it to the UI Argument
# Obviously won't work without reliable DNS resolution
# Might grow if we can finally work out why FireFox is ignoring the policies.json file, or maybe we just dump it and move to LibreWolf.

serverIP=$(nslookup svr | awk '/^Address: / { print $2 }')
sleep 3
exec firefox --kiosk http://${serverIP}:9080