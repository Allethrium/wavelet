#!/bin/bash
# Simple module which adds a delay to firefox 
# Finds server IP address and adds it to the UI Argument
# Obviously won't work without reliable DNS resolution
# Might grow if we can finally work out why FireFox is ignoring the policies.json file, or maybe we just dump it and move to LibreWolf.

main(){
	serverIP=$(nslookup svr | awk '/^Address: / { print $2 }')
        systemctl --user start http-php-pod.service
	sleep 5
	exec firefox http://${serverIP}:9080
}

get_authtoken(){
        # This function would be used to get an auth token so the server could support a local web console
        # in the event that the UI were password protected.
        echo "Right now we don't do anything here."
}

#####
#
# Main
#
#####

logName=/var/home/wavelet/logs/webui.log
#set -x
exec > "${logName}" 2>&1

if [[ "$EUID" -eq 0 ]]; then echo "Cannot run as root"
  exit 1
fi

if [[ -e $logName || -L $logName ]] ; then
        i=0
        while [[ -e $logName-$i || -L $logName-$i ]] ; do
                let i++
        done
        logName=$logName-$i
fi

PARENT_COMMAND=$(ps -o comm= $PPID)
echo -e "Called from ${PARENT_COMMAND}"
main