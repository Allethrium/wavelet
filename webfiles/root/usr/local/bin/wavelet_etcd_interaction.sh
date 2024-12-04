#!/bin/bash

# Wavelet etcd interaction.  Calls etcdctl which is installed on the base layer, detects if security layer is enabled and parses proper client certificates
# Effectively, it intercepts the etcd calls from the other modules and injects certificates as necessary

#Etcd Interaction global variables
ETCDENDPOINT="$(cat /var/home/wavelet/etcd_ip):2379"
ETCDCTL_API=3
clientCertificateFile="/etc/pki/tls/cert/etcd.cert"
clientCertificateKeyFile="/etc/pki/tls/private/etcd.key"
certificateAuthorityFile="/etc/ipa/ca.crt"

# This script is called with args.  
	# Arg 1 is action (simplified from previous version with read_etcd, read_etcd_globa, write_etcd etc.)
	# Arg 2 is the input key name
	# Arg 3 is the input key value
	# Arg 4 is the print-value-only request (true if exists, false otherwise)

#	The module returns the input key/keyvalue and success if the action is modify, update, delete etc.
#	The module returns the key value if the command is 'get' as ${prinvalue}

main() {
	#echo -e "\nFunction:\nAction: ${action}\nKey Name: ${inputKeyName}\nKey Value: ${inputKeyValue}\nPrint Value Only?:${valueOnlySwitch}"
	# We need to add a separator to etcd doesn't try to process any command inputs starting with the -- delimeter as etcd flags
	set --
	if [[ ${inputKeyValue} != "" ]]; then flagSeparator="-- "; fi
	# Here we are going to parse the entire command line, otherwise injected '' for unused variables mess with the results.
	# check for security layer
	if [[ -f /var/prod.security.enabled ]]; then
		ETCDURI=https://192.168.1.32:2379/v3/kv/put
		etcdCommand(){
			printvalue=$(etcdctl --endpoints="${ETCDENDPOINT}" \
			--cert-file "${clientCertificateFile}" \
			--key-file "${clientKeyFile}" \
			--ca-file "${certificateAuthorityFile}" "${commandLine[@]}")
		}
	else
		ETCDURI=http://192.168.1.32:2379/v3/kv/put
		etcdCommand(){
			printvalue=$(etcdctl --endpoints="${ETCDENDPOINT}" "${commandLine[@]}")
		}
	fi
	etcdCommand
	if [[ ${printvalue} = "OK" ]]; then
		echo -e "etcd key written successfully"
	else
		echo ${printvalue}
	fi
}

generate_service(){
	# This should parse a call to generate a systemd watcher service based off parsed parameters from the relevant modules.
	# In this case, we'd put generate_service ${KEYNAME} 0 0 ${MODULE} ${additionalArg}
	
	# If ${MODULE} == null, we use the keyname.
	# Generates only user services, we don't use etcd in this capacity on any rootful stuff.
	if [[ "${waveletModule}" = "" ]]; then
		echo -e "Module argument empty, the generated service will be named the same as the key it is watching.\n"
		waveletModule=${inputKeyName}
	fi

	if [[ -f /var/prod.security.enabled ]]; then
		ETCDURI=https://192.168.1.32:2379/v3/kv/put
		echo -e "[Unit]
Description=Wavelet ${inputKeyName}
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=etcdctl --endpoints=${ETCDENDPOINT} \
--cert-file ${clientCertificateFile} \
--key-file ${clientKeyFile} \
--ca-file ${certificateAuthorityFile} \
watch ${inputKeyName} -w simple -- sh -c "/usr/local/bin/${waveletModule}.sh ${additionalArg}"
Restart=always

[Install]
WantedBy=default.target" > /home/wavelet/.config/systemd/user/${waveletModule}.service
	else
		echo -e "[Unit]
Description=Wavelet ${inputKeyName}
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=etcdctl --endpoints=${ETCDENDPOINT} \
watch ${inputKeyName} -w simple -- sh -c "/usr/local/bin/${waveletModule}.sh ${additionalArg}"
Restart=always

[Install]
WantedBy=default.target" > /home/wavelet/.config/systemd/user/${waveletModule}.service
	fi
	echo -e "User Systemd service unit for ${inputKeyName} generated, remember to systemd --user daemon-reload from your calling function!\n"
	exit 0
}


#####
#
#  Main
#
#####

action=$1
inputKeyName=$2
inputKeyValue=$3
valueOnlySwitch=$4
waveletModule=$5
additionalArg=$6
revisionID=$7

case ${action} in
	# Read an etcd value stored under a hostname - note the preceding / 
	# Etcd does not have a hierarchical structure so we're 'simulating' directories by adding the /
	read_etcd)					declare -A commandLine=([3]="get" [2]="/$(hostname)/${inputKeyName}" [1]="--print-value-only");
	;;
		# Read an etcd value set globally - may still be hostname but would be defined in inputKeyName
	read_etcd_global)			declare -A commandLine=([3]="get" [2]="${inputKeyName}" [1]="--print-value-only");
	;;
	# Read a set of etcd values by prefix.  I.E a list of IP addresses
	read_etcd_prefix)   	    declare -A commandLine=([3]="get" [2]="/$(hostname)/${inputKeyName}" [1]="--prefix" [0]="--print-value-only");
	;;
	read_etcd_json_revision)	declare -A commandline=([0]="get -w json");
	;;
	read_etcd_lastrevision)		declare -A commandLine=([2]="get" [1]="${inputKeyName}" [0]="--rev=${revisionID}");
	;;
	read_etcd_keysonly)			declare -A commandLine=([3]="get" [2]="${inputKeyName}" [1]="--prefix" [0]="--keys-only");
	;;
	# Write an etcd value under a hostname
	write_etcd)					declare -A commandLine=([3]="put" [2]="/$(hostname)/${inputKeyName}" [1]="--" [0]="${inputKeyValue}");
	;;
	# Write a global etcd value where the key is root and not considered "under" a host
	write_etcd_global)			declare -A commandLine=([3]="put" [2]="${inputKeyName}" [1]="--" [0]="${inputKeyValue}");
	;;
	# Special function for writing ip addresses under /decoderip/ 
	write_etcd_client_ip)		declare -A commandLine=([3]="put" [2]="/decoderip/$(hostname)" [1]="--" [0]="${inputKeyValue}");
	;;
	# returns value list of IP Addresses, special case to parse directly to command (used for read_etcd_clients and the sed variant)
	read_etcd_clients*)			declare -A commandLine=([3]="get" [2]="--prefix" [1]="/decoderip/" [0]="--print-value-only");
	;;
	# Delete a key
	delete_etcd_key)			declare -A commandLine=([1]="del" [0]="$()hostname)/${inputKeyName}");
	;;
	# Delete a global key
	delete_etcd_key_global)		declare -A commandLine=([1]="del" [0]="${inputKeyName}");
	;;
	# Generate a user systemd watcher based off keyname and module arguments.
	generate_service)			generate_service "${inputKeyName}" "${waveletModule}" "${additionalArg}";
	;;
	# exit with error because other commands are not valid!
	*)			echo -e "\nInvalid command\n"; exit 1;
	;;
esac

# Because we need an output from this script, we can't enable logging (unless something's broken..)
#set -x
#exec >/home/wavelet/etcdlog.log 2>&1
main "${action}" "${inputKeyName}" "${inputKeyValue}" "${valueOnlySwitch}"