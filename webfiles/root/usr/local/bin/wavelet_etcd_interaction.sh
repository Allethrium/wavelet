#!/bin/bash

# Wavelet etcd interaction.  Calls etcdctl which is installed on the base layer, detects if security layer is enabled and parses proper client certificates
# Effectively, it intercepts the etcd calls from the other modules and injects certificates as necessary

#Etcd Interaction global variables
ETCDENDPOINT=$(cat /home/wavelet/etcd_ip)
ETCDCTL_API=3

# This script is called with args.  
	# Arg 1 is action (simplified from previous version with read_etcd, read_etcd_globa, write_etcd etc.)
	# Arg 2 is the input key name
	# Arg 3 is the input key value
	# Arg 4 is the print-value-only request (true if exists, false otherwise)

#	The module returns the input key/keyvalue and success if the action is modify, update, delete etc.
#	The module returns the key value if the command is 'get' as ${prinvalue}

main() {
	#echo -e "\nFunction:\nAction: ${action}\nKey Name: ${inputKeyName}\nKey Value: ${inputKeyValue}\nPrint Value Only?:${valueOnlySwitch}"
	if [[ -f /var/prod.security.enabled ]]; then
		ETCDURI=https://192.168.1.32:2379/v3/kv/put
		etcdCommand(){
			etcdctl --endpoints=${ETCDENDPOINT} \
			--cert-file ${clientCertificateFile} \
			--key-file ${clientKeyFile} \
			--ca-file ${certificateAuthorityFile} \
			${action} \
			${inputKeyName} \
			${inputKeyValue} \
			${valueOnlySwich}
		}
	else
		ETCDURI=http://192.168.1.32:2379/v3/kv/put
		etcdCommand(){
			etcdctl --endpoints=${ETCDENDPOINT} \
			${action} \
			${inputKeyName} \
			${inputKeyValue} \
			${valueOnlySwitch}
		}
	fi
	etcdCommand
}



#####
#
#  Main
#
#####

#set -x
action=$1
inputKeyName=$2
inputKeyValue=$3
valueOnlySwitch=$4

case ${action} in
	# Read an etcd value stored under a hostname - note the preceding / 
	# Etcd does not have a hierarchical structure so we're 'simulating' directories by adding the /
	read_etcd)		action="get"; inputKeyName="/$(hostname)/${inputKeyName}" inputKeyValue=""; valueOnlySwitch="--print-value-only";
	;;
		# Read an etcd value set globally - may still be hostname but would be defined in inputKeyName
	read_etcd_global)	action="get"; valueOnlySwitch="--print-value-only";
	;;
	# Read a set of etcd values by prefix.  I.E a list of IP addresses
	read_etcd_prefix)       action="get --prefix"; inputKeyName="/$(hostname)/${inputKeyName}"; valueOnlySwitch="--print-value-only"
		;;
	# Write an etcd value under a hostname
	write_etcd)		action="put"; inputKeyName="/$(hostname)/${inputKeyName} --"; valueOnlySwitch=""
	;;
	# Write a global etcd value where the key is implicit
	write_etcd_global)	action="put"; inputKeyName="${inputKeyName} -- "; valueOnlySwitch=""
	;;
	# Special function for writing ip addresses under /decoderip/ 
	write_etcd_clientip)	action="put"; inputKeyName="/decoderip/$(hostname) -- ";
	;;
	# returns value list of IP Addresses
	read_etcd_clients_ip)	action="get"; inputKeyName="--prefix /decoderip/"; valueOnlySwitch="--print-value-only";
	;;
	# Special function only used for reflector.  Probably overcomlicating things and unnecessary.
	read_etcd_clients_sed)	action="get --prefix /decoderip/" valueOnlySwitch="--print-value-only";
	;;
	# exit with error because other commands are not valid!
	*)			echo -e "\nInvalid command\n"; exit 1;
	;;
esac

main "${action}" "${inputKeyName}" "${inputKeyValue}" "${valueOnlySwitch}"
