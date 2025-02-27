#!/bin/bash

# Wavelet etcd interaction.  Calls etcdctl which is installed on the base layer, detects if security layer is enabled and parses proper client certificates
# Effectively, it intercepts the etcd calls from the other modules and injects certificates as necessary

#Etcd Interaction global variables
ETCDENDPOINT="$(cat /var/home/wavelet/config/etcd_ip):2379"
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
	# the commandline must be quoted, otherwise arguments such as "-t blablabla" aren't processed.
	# This may mean we get quotation marks back out during queries, which will need to be stripped by their processing modules.
	if [[ -f /var/prod.security.enabled ]]; then
		# Username / password is already stored in the variable ${userArg}, which is in the sparse ${commandLine} array
		ETCDURI=https://${ETCDENDPOINT}/v3/kv/
		echo -e "Attempting: \n
			etcdctl --endpoints="${ETCDENDPOINT}" --cert-file "${clientCertificateFile}" --key-file "${clientKeyFile}" --ca-file "${certificateAuthorityFile}" ${commandLine[@]}" >> /var/home/wavelet/logs/etcdlog.log
		etcdCommand(){
			printvalue=$(etcdctl --endpoints="${ETCDENDPOINT}" \
			--cert-file "${clientCertificateFile}" \
			--key-file "${clientKeyFile}" \
			--ca-file "${certificateAuthorityFile}" \
			${commandLine[@]})
		}
	else
		ETCDURI=http://${ETCDENDPOINT}/v3/kv/
		echo "Attempting: etcdctl --endpoints="${ETCDENDPOINT}" ${commandLine[@]}" >> /var/home/wavelet/logs/etcdlog.log
		etcdCommand(){
			printvalue=$(etcdctl --endpoints="${ETCDENDPOINT}" ${commandLine[@]})
		}
	fi
	etcdCommand
	# Process feedback
	if	[[ ${fID} == "clearText" ]]; then
	 	echo "${printvalue}"
	elif [[ ${printvalue} = "OK" ]]; then
		# If we're performing a write, then we get OK back
		echo -e "OK"
		exit 0
	elif [[ ${printvalue} = *"revision"* ]]; then
		# We're pulling other etcd data such as key revision
		echo ${printvalue}
	else
		# If we are performing a get operation, we need to decode from base64
		IFS=' '; echo ${printvalue} | base64 -d
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
	# We have additional security requirements of client/server certificates
		ETCDURI=http://${ETCDENDPOINT}/v3/kv/
		echo -e "[Unit]
Description=Wavelet ${inputKeyName}
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=etcdctl --endpoints=${ETCDENDPOINT} \
--cert-file ${clientCertificateFile} \
--key-file ${clientKeyFile} \
--ca-file ${certificateAuthorityFile} \
${userArg} \
watch ${inputKeyName} -w simple -- /usr/bin/bash -c \"/usr/local/bin/${waveletModule}.sh ${additionalArg}\"
Restart=always

[Install]
WantedBy=default.target" > /home/wavelet/.config/systemd/user/${waveletModule}.service
	else
	# We still have defined server, root and webui roles
		echo -e "[Unit]
Description=Wavelet ${inputKeyName}
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=etcdctl --endpoints=${ETCDENDPOINT} \
${userArg} \
watch ${inputKeyName} -w simple -- /usr/bin/bash -c \"/usr/local/bin/${waveletModule}.sh ${additionalArg}\"
Restart=always

[Install]
WantedBy=default.target" > /home/wavelet/.config/systemd/user/${waveletModule}.service
	fi
	echo -e "User Systemd service unit for etcd Key: ${inputKeyName} generated\nName: ${waveletModule}.service\nRemember to run 'systemctl --user daemon-reload' from your calling function.\n"
	exit 0
}

generate_etcd_core_roles(){
	# Generate etcd roles
	# Etcd roles must be generated because the build_ug, detectv4l modules do not know if security is on or off, so they set role permissions as they generate and remove their keys.
	# webui ensures the webui can only write to keys under the range "/UI/"
	etcdctl --endpoints=${ETCDENDPOINT} role add webui
	etcdctl --endpoints=${ETCDENDPOINT} role grant-permission webui --prefix=true readwrite "/UI/" 
	# The server should be able to modify everything, and has its own "root" role.  Most coordination happens on the server, so this is fine.
	etcdctl --endpoints=${ETCDENDPOINT} role add server
	etcdctl --endpoints=${ETCDENDPOINT} role grant-permission server --prefix=true readwrite "" 
	# The PROV role is designed for provision requests and is 'wide open' so that an initial host can request a provision key
	etcdctl --endpoints=${ETCDENDPOINT} role add PROV
	etcdctl --endpoints=${ETCDENDPOINT} role grant-permission PROV --prefix=true readwrite "/PROV/" 
	generate_etcd_core_users
}

generate_etcd_core_users(){
	# Generate basic etcd users
	# Root user
	set -x
	declare -a FILES=("/var/home/wavelet/.ssh/secrets/etcd_svr_pw.secure" "/var/home/wavelet/.ssh/secrets/etcd_client_pw.secure" "/var/home/wavelet/.ssh/secrets/etcd_root_pw.secure")
	for file in "${FILES[@]}"; do
		if [[ -f $file ]]; then
			echo "File '$file' is configured." >> /var/home/wavelet/logs/etcdlog.log
			fileFound=1
		fi
	done
	if [[ $fileFound -eq "1" ]]; then
		echo 'Files already generated!  Doing nothing, as overwriting them will result in an inaccessible keystore!'
		exit 0
	fi
	echo "Generating roles and users for initial system setup.."
	mkdir -p ~/.ssh/secrets
	local PassWord=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')	
	echo ${PassWord} > ~/.ssh/secrets/etcd_root_pw.secure
	etcdctl --endpoints=${ETCDENDPOINT} user add root --new-user-password ${PassWord}
	etcdctl --endpoints=${ETCDENDPOINT} user grant-role root root
	unset PassWord
	# Server
	local PassWord=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')
	echo ${PassWord} > ~/.ssh/secrets/etcd_svr_pw.secure
	etcdctl --endpoints=${ETCDENDPOINT} user add svr --new-user-password ${PassWord}
	etcdctl --endpoints=${ETCDENDPOINT} user grant-role svr server
	unset PassWord
	# WebUI
	local PassWord=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')
	echo ${PassWord} > ~/.ssh/secrets/etcd_webui_pw.secure
	etcdctl --endpoints=${ETCDENDPOINT} user add webui --new-user-password ${PassWord}
	etcdctl --endpoints=${ETCDENDPOINT} user grant-role webui webui
	# Create the PROV user
	etcdctl --endpoints=${ETCDENDPOINT} user add PROV --no-password
	etcdctl --endpoints=${ETCDENDPOINT} user grant-role PROV PROV
	# Create the base UI key and grant the webui user access to the prefix range
	KEYNAME="/UI/"; KEYVALUE="True"; /usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	unset PassWord
	# User backend pw if set during setup (add as option later)
	# add a test here to ensure everything is functional
	KEYNAME="Global_test"; KEYVALUE="True"; /usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	returnVal=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}")
	if [[ ${returnVal} == "True" ]];then
		echo "Key value correct, enabling auth.."
		etcdctl auth enable
	else
		echo "The test key value was not successfully retrieved.  Please review logs to troubleshoot!"
		exit 1
	fi
	test_auth "svr"
	test_auth "webui"
	set +x
	exit 0
}

test_auth() {
	echo "testing $1"
	if [[ $1 == "svr" ]]; then
		returnVal=$(/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "svr_auth" "True")
	else
		local webuipw=$(cat /var/home/wavelet/.ssh/secrets/etcd_webui_pw.secure)
		returnVal=$(etcdctl --endpoints=${ETCDENDPOINT} --user webui:${webuipw} put "/UI/ui_auth" -- "True")
	fi
	if [[ ${returnVal} == "True" ]]; then
		echo "Test successful!"
	else
		echo "Test failed!"
		exit 1
	fi
}

generate_etcd_host_role(){
	# This is called from a specific systemd watcher service to handle provision requests.
	# Hosts can modify keys under themselves: /$(hostname)/$, they should not be able to write global "root" keys.
	# These permissions can really only be added after the initial host provisioning is completed, because they do not exist prior to this.
	# This must be processed by the server, as natively new hosts will not have permissions to write their own keys (if i do this 'right')
	echo "Generating role and user for ETCD client.."
	KEYNAME="/PROV/REQUEST"; clientHostName=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}")
	etcdctl --endpoints=${ETCDENDPOINT} role add "${clientHostName}" --prefix=true readwrite "/${clientHostName}/"
	local PassWord=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')
	etcdctl --endpoints=${ETCDENDPOINT} user add "host-${clientHostName}" --new-user-password ${PassWord}
	etcdctl --endpoints=${ETCDENDPOINT} user grant-role host-${clientHostName} host-${clientHostName}
	# write key-val which the host will be watching to get the initial info back - this is insecure even though its deleted immediately. 
	# find a better way to do this.
	etcdctl --endpoints=${ETCDENDPOINT} put "/PROV/${clientHostName}" -- ${PassWord}
	unset PassWord
	exit 0
}

get_creds(){
	declare -a FILES=("/var/home/wavelet/.ssh/secrets/etcd_svr_pw.secure" "/var/home/wavelet/.ssh/secrets/etcd_client_pw.secure")
	for i in "${FILES[@]}"; do
		echo "looking for $i" >> /var/home/wavelet/logs/etcdlog.log
		if [[ -f $i ]]; then
			echo "File $i is configured." >> /var/home/wavelet/logs/etcdlog.log
			set_userArg
		else
			echo "No credentials files configured!" >> /var/home/wavelet/logs/etcdlog.log
		fi
	done
}

set_userArg() {
	case $(hostname) in
		# If we are the server we use a different password than a client machine
		# This might be a silly way of doing this because:   
		#	(a) the password is now a variable in this shell 
		#	(b) will the variable be accessible from the above functions?
		svr*)		userArg="--user svr:$(cat /var/home/wavelet/.ssh/secrets/etcd_svr_pw.secure)";
		;;
		*)			userArg="--user host-$(hostname):$(cat /var/home/wavelet/.ssh/secrets/etcd_client_pw.secure)";
		;;
	esac
	echo "User args: ${userArg}" >> /var/home/wavelet/logs/etcdlog.log
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

# We want to convert the inputKeyValue to a base64 string, much like etcd does internally, otherwise we run into difficulty handling spacing, escape chars and other common issues.
# This means that ALL key values are base64 now.
echo -e "\n\n**New log**\n\n" >> /var/home/wavelet/logs/etcdlog.log
get_creds

case ${action} in
	# Read an etcd value stored under a hostname - note the preceding / 
	# Etcd does not have a hierarchical structure so we're 'simulating' directories by adding the /
	read_etcd)					declare -A commandLine=([4]="${userArg}" [3]="get" [2]="/$(hostname)/${inputKeyName}" [1]="--print-value-only");
	;;
	# Read an etcd value set globally - may still be hostname but would be defined in inputKeyName
	read_etcd_global)			declare -A commandLine=([4]="${userArg}" [3]="get" [2]="${inputKeyName}" [1]="--print-value-only"); fID="clearText";
	;;
	# Read a set of etcd values by prefix.  I.E a list of IP addresses
	read_etcd_prefix)   	    declare -A commandLine=([4]="${userArg}" [3]="get" [2]="/$(hostname)/${inputKeyName}" [1]="--prefix" [0]="--print-value-only");
	;;
	# For global keys, values only
	read_etcd_prefix_global)    declare -A commandLine=([4]="${userArg}" [3]="get" [2]="${inputKeyName}" [1]="--prefix" [0]="--print-value-only"); fID="clearText";
	;;
	# For global keys + values, returned in a list key-value-key-value IFS is newline
	read_etcd_prefix_list)    	declare -A commandLine=([4]="${userArg}" [3]="get" [2]="${inputKeyName}" [1]="--prefix"); fID="clearText";
	;;
	read_etcd_json_revision)	declare -A commandLine=([4]="${userArg}" [3]="get -w json" [1]="${inputKeyName}");
	;;
	read_etcd_lastrevision)		declare -A commandLine=([4]="${userArg}" [2]="get" [1]="${inputKeyName}" [0]="--rev=${revisionID}");
	;;
	# Want to return everything in the clear here
	read_etcd_keysonly)			declare -A commandLine=([4]="${userArg}" [3]="get" [2]="${inputKeyName}" [1]="--prefix" [0]="--keys-only"); fID="clearText";
	;;
	# Write an etcd value under a hostname.  Keys here are base64
	# Note -w 0 to disable base64 line wrapping, or we get a newline \n after every 76 chars.
	write_etcd)					inputKeyValue=$(echo ${inputKeyValue} | base64 -w 0); declare -A commandLine=([3]="put" [2]="/$(hostname)/${inputKeyName}" [1]="--" [0]="${inputKeyValue}");
	;;
	# Write a global etcd value where the key is root and not considered "under" a host.  Keys here are clear text.
	write_etcd_global)			declare -A commandLine=([4]="${userArg}" [3]="put" [2]="${inputKeyName}" [1]="--" [0]="${inputKeyValue}");
	;;
	# Special function for writing ip addresses under /decoderip/ 
	write_etcd_client_ip)		declare -A commandLine=([4]="${userArg}" [3]="put" [2]="/decoderip/$(hostname)" [1]="--" [0]="${inputKeyValue}");
	;;
	# returns value list of IP Addresses, special case to parse directly to command (used for read_etcd_clients and the sed variant)
	read_etcd_clients*)			declare -A commandLine=([4]="${userArg}" [3]="get" [2]="--prefix" [1]="/decoderip/" [0]="--print-value-only"); fID="clearText";
	;;
	# Delete a key
	delete_etcd_key)			declare -A commandLine=([4]="${userArg}" [1]="del" [0]="/$(hostname)/${inputKeyName}"); fID="clearText";
	;;
	# Delete a global key
	delete_etcd_key_global)		declare -A commandLine=([4]="${userArg}" [1]="del" [0]="${inputKeyName}"); fID="clearText";
	;;
	# Delete keys on prefix
	delete_etcd_key_prefix)		declare -A commandLine=([4]="${userArg}" [2]="del" [1]="${inputKeyName}" [0]="--prefix"); fID="clearText";
	;;
	# Generate a user systemd watcher based off keyname and module arguments.
	generate_service)			generate_service "${inputKeyName}" "${waveletModule}" "${additionalArg}" "${userArg}"; fID="clearText";
	;;
	# Generates basic etcd role definitions
	generate_etcd_core_roles)	generate_etcd_core_roles;
	;;
	# Generates etcd host role definition
	generate_etcd_host_role)	generate_etcd_host_role "${inputKeyValue}";
	;;
	# Generates etcd host role definition
	client_provision_request)	declare -A commandLine=([4]="--user PROV" [2]="put" [1]="/PROV/REQUEST" [0]="${hostNameSys}"); fID="clearText";
	;;
	client_provision_response)	declare -A commandLine=([4]="--user PROV" [2]="get" [1]="/PROV/REQUEST" [0]="--print-value-only"); fID="clearText";
	;;
	check_status)				declare -A commandLine=([4]="${userArg}" [2]="endpoint status"); fID="clearText";
	;;
	# exit with error because other commands are not valid!
	*)			echo -e "\nInvalid command\n"; exit 1;
	;;
esac

# Because we need an output from this script, we can't enable logging (unless something's broken..)
#set -x
#exec >/var/home/wavelet/logs/etcdlog.log 2>&1
hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
main "${action}" "${inputKeyName}" "${inputKeyValue}" "${valueOnlySwitch}" "${userArg}"