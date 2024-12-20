#!/bin/bash
# Simple module which adds a delay to firefox 
# Finds server IP address and adds it to the UI Argument
# Obviously won't work without reliable DNS resolution
# Might grow if we can finally work out why FireFox is ignoring the policies.json file, or maybe we just dump it and move to LibreWolf.

main(){
	serverIP=$(nslookup svr | awk '/^Address: / { print $2 }')
	sleep 3
	exec firefox http://${serverIP}:9080
}

#####
#
# Main
#
#####

logName=/var/home/wavelet/webui.log
if [[ -e $logName || -L $logName ]] ; then
        i=0
        while [[ -e $logName-$i || -L $logName-$i ]] ; do
                let i++
        done
        logName=$logName-$i
fi

#set -x
exec > "${logName}" 2>&1

main