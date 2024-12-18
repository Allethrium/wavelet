#!/bin/bash
# Simple module which adds a delay to firefox 
# Finds server IP address and adds it to the UI Argument
# Obviously won't work without reliable DNS resolution

nslookup svr | awk '/^Address: / { print $2 }'
sleep 5
exec firefox --kiosk http://${serverIP}:9080