#!/bin/bash
#
# This module is called from a ROOTFUL systemD unit preprovisioned during the install process.
# This module is destructive and will deprovision a host from Wavelet
# It will leave one remaining key (${hostName}/DEPROVISION == 1)
# If the security layer is enabled, it will deprovision from the domain
# which will prevent it from reconnecting without a full re-image from the server.
# If the security layer is NOT enabled, a reboot will reconnect it to wavelet, and it will reprovision itself.


# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
read_etcd_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}") 
	echo -e "Key Name: {$KEYNAME} read from etcd for Global Value: $printvalue\n"
}

event_deprovision(){
	KEYNAME="/${hostNameSys}/DEPROVISION"; read_etcd_global
	if [[ "${printvalue}" -eq 1 ]]; then
		echo -e "\nDeprovision flag is set.  System will deprovision itself.."
		if [[ -f /var/prod.security.disabled ]]; then
			echo "Security layer enabled.  Not this will prevent the host reconnecting to Wavelet."
			security_layer_deprovision
		systemctl shutdown now
	else
		echo -e "\nDeprovision key is set to 0, doing nothing.. \n"
		exit 0
	fi
}

security_layer_deprovision(){
	echo "Removing client from IPA Domain.."
	ipa-client-install --uninstall
	echo "Removing pregenerated configs.."
	rm -rf /var/home/wavelet/config
	echo "Removal complete.  This host may be redeployed by imaging from scratch via PXE.  It will not be able to reconnect to Wavelet in its current state."
}

###
#
# Main 
#
###

logName=/var/home/wavelet/logs/deprovision.log
if [[ -e $logName || -L $logName ]] ; then
	i=0
	while [[ -e $logName-$i || -L $logName-$i ]] ; do
		let i++
	done
	logName=$logName-$i
fi

#set -x
exec > "${logName}" 2>&1

hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
event_deprovision