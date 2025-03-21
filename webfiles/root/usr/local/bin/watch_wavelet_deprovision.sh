#!/bin/bash
#
# This is the systemd watcher for the service.  It utilizes the loadcred argument to keep the credentials away from the user.  
# The service only has access to this client's credentials.

logName=/var/home/wavelet/logs/deprovision_watcher.log
if [[ -e $logName || -L $logName ]] ; then
	i=0
	while [[ -e $logName-$i || -L $logName-$i ]] ; do
		let i++
	done
	logName=$logName-$i
fi
chown wavelet:wavelet /var/home/wavelet/logs/deprovision_watcher.log
hostName=$(hostname)
etcdctl --endpoints=${ETCDENDPOINT} --user ${hostName:0:7}:$CREDENTIALS_DIRECTORY/etcd_client_pass \
watch /UI/hosts/${hostName}/control/DEPROVISION \
-w simple -- /usr/bin/bash -c "/usr/local/bin/wavelet_deprovision.sh"