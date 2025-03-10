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

#   The module returns the input key/keyvalue and success if the action is modify, update, delete etc.
#   The module returns the key value if the command is 'get' as ${prinvalue}

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
	if  [[ ${fID} == "clearText" ]]; then
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
	# Etcd roles must be generated because the build_ug, detectv4l modules do not know if security is on or off
	# webui ensures the webui can only write to keys under the range "/UI/" and all other orchestration happens separately.
	if [ "$EUID" -ne 0 ]
		then echo "Only runs during initial setup as root."
		exit 1
	fi
	etcdctl --endpoints=${ETCDENDPOINT} role add webui
	KEYNAME="/UI/"; KEYVALUE="True"; /usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
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
	# This should be invoked by the root user prior to everything getting spun up. 
	# This is because the etcd root cred should be available only TO root.
	# The other creds are in the wavelet userland.
	#set -x
	# Test for etcd accessibility, fail if no.
	KEYNAME="Global_test"; KEYVALUE="True"; /usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	returnVal=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}")
	if [[ ${returnVal} == "True" ]];then
		echo "Key value correct, enabling auth.."
	else
		echo "The test key value was not successfully retrieved.  Please review logs to troubleshoot!"
		exit 1
	fi
	# Create the base UI key and grant the webui user access to the prefix range
	echo "Generating roles and users for initial system setup.."
	mkdir -p ~/.ssh/secrets
	local PassWord=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9') 
	encrypt_pw_data "root" "${PassWord}"
	#echo ${PassWord} > ~/.ssh/secrets/etcd_root_pw.secure
	etcdctl --endpoints=${ETCDENDPOINT} user add root --new-user-password ${PassWord}
	etcdctl --endpoints=${ETCDENDPOINT} user grant-role root root
	unset PassWord
	# Server
	local PassWord=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')
	encrypt_pw_data "svr" "${PassWord}"
	#echo ${PassWord} > ~/.ssh/secrets/etcd_svr_pw.secure
	etcdctl --endpoints=${ETCDENDPOINT} user add svr --new-user-password ${PassWord}
	etcdctl --endpoints=${ETCDENDPOINT} user grant-role svr server
	unset PassWord
	# WebUI
	local PassWord=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')
	encrypt_webui_data ${PassWord}
	etcdctl --endpoints=${ETCDENDPOINT} user add webui --new-user-password ${PassWord}
	etcdctl --endpoints=${ETCDENDPOINT} user grant-role webui webui
	# Create the PROV user
	etcdctl --endpoints=${ETCDENDPOINT} user add PROV --no-password
	etcdctl --endpoints=${ETCDENDPOINT} user grant-role PROV PROV
	unset PassWord
	# User backend pw if set during setup (add as option later)
	etcdctl auth enable
	test_auth "svr"
	test_auth "webui"
	set +x
	exit 0
}

encrypt_pw_data() {	
	# This makes a poor man's two factor auth to get etcd access.
	local user=$1
	local pw=$2
	local password2=$(head -c 16 /dev/urandom |  base64 | tr -dc 'a-zA-Z0-9')
	if [[ "${user}" == "root" ]]; then
		mkdir -p /var/roothome/.ssh/secrets; secretsDir="/var/roothome/.ssh/secrets"
		mkdir -p /var/roothome/config; configDir="/var/roothome/config"
	else
		#mkdir -p /var/home/wavelet/.ssh/secrets & chown -R wavelet:wavelet /var/home/wavelet/.ssh/secrets
		secretsDir="/var/home/wavelet/.ssh/secrets"
		configDir="/var/home/wavelet/config"
	fi
	echo ${password2} > ${configDir}/${1}.pw2.txt
	echo "${pw}" | base64 | openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -nosalt -out ${secretsDir}/${1}.crypt.bin
	local result=$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -nosalt -in ${secretsDir}/${1}.crypt.bin -d)
	local result=$(echo $result | base64 -d)
	if [[ $result == $pw ]]; then
		echo "Password for $1 encrypted and tested successfully!"
	else
		echo "Decrypt failed, something is wrong!"
		exit 1
	fi
	chown wavelet:wavelet "${secretsDir}/${1}.crypt.bin"; chown wavelet:wavelet "${configDir}/${1}.pw2.txt"
	chmod 600 "${secretsDir}/${1}.crypt.bin"; chmod 600 "${configDir}/${1}.pw2.txt"
}

encrypt_webui_data() {
	#	webui goes to different spots as they need to be accessible by php-fpm for the web processes.
	local pw=$1
	local password2=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')
	mkdir -p /var/home/wavelet/http-php/secrets/; chown -R wavelet:wavelet /var/home/wavelet/http-php/secrets/
	echo "${password2}" > /var/home/wavelet/http-php/secrets/pw2.txt
	echo "${pw}" | base64 | openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -nosalt -out /var/home/wavelet/http-php/secrets/crypt.bin
	local result=$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -nosalt -in /var/home/wavelet/http-php/secrets/crypt.bin -d)
	local result=$(echo $result | base64 -d)
	if [[ $result == $pw ]]; then
		echo "Password encrypted and tested successfully!"
	else
		echo "Decrypt failed, something is wrong!"
		exit 1
	fi
	# Remember to chown and chmod
	chown -R wavelet:wavelet /var/home/wavelet/http-php/secrets/
	chmod 751 /var/home/wavelet/http-php/secrets/
	# try to work out some other less obvious place to stash pw2..
}


test_auth() {
	set -x
	echo "testing $1"
	if [[ $1 == "svr" ]]; then
		echo "Testing svr auth.." >> /var/home/wavelet/logs/etcdlog.log
		KEYNAME="svr_auth"; KEYVALUE="True"
		/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
		returnVal=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}")
		echo "Returned: ${returnVal}" >> /var/home/wavelet/logs/etcdlog.log
		if [[ ${returnVal} == "True" ]]; then
			echo "Test successful!" >> /var/home/wavelet/logs/etcdlog.log
		else
			echo "Test failed!" >> /var/home/wavelet/logs/etcdlog.log
			exit 1
		fi
	else
		echo "Testing webui auth.." >> /var/home/wavelet/logs/etcdlog.log
		KEYNAME="/UI/ui_auth"
		local password2=$(cat /var/home/wavelet/http-php/secrets/pw2.txt)
		local decrypt=$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -nosalt -in /var/home/wavelet/http-php/secrets/crypt.bin -d)
		local webuipw=$(echo "${decrypt}" | base64 -d)
		etcdctl --endpoints=${ETCDENDPOINT} --user webui:${webuipw} put "/UI/ui_auth" -- "True"
		echo "Attempting: etcdctl --endpoints=${ETCDENDPOINT} --user webui:${webuipw} get ${KEYNAME}" >> /var/home/wavelet/logs/etcdlog.log
		returnVal=$(etcdctl --endpoints=${ETCDENDPOINT} --user webui:${webuipw} get "${KEYNAME}" --print-value-only)
		echo "Returned: ${returnVal}" >> /var/home/wavelet/logs/etcdlog.log
		if [[ ${returnVal} == *"True"* ]]; then
			echo "Test successful!" >> /var/home/wavelet/logs/etcdlog.log
		else
			echo "Test failed!" >> /var/home/wavelet/logs/etcdlog.log
			exit 1
		fi
	fi
	set +x
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
	# This makes a poor man's two factor auth to get etcd access.
	local user="${clientHostName}"
	local password2=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')
	KEYNAME="/PROV/FACTOR2"; KEYVALUE="${password2}"; write_etcd_global
	echo "${pw}" | base64 | openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -nosalt -out /var/home/wavelet/config/${clientHostName}.crypt.bin
	local result=$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -nosalt -in ${secretsDir}/${1}.crypt.bin -d)
	local result=$(echo $result | base64 -d)
	if [[ $result == $pw ]]; then
		echo "Password encrypted and tested successfully!"
	else
		echo "Decrypt failed, something is wrong!"
		exit 1
	fi
	# Upload 
	KEYNAME="/PROV/CRYPT"; KEYVALUE="$(cat /var/home/wavelet/config/${clientHostName}.crypt.bin | base64)"; write_etcd_global
	etcdctl --endpoints=${ETCDENDPOINT} user add "host-${clientHostName}" --new-user-password ${PassWord}
	etcdctl --endpoints=${ETCDENDPOINT} user grant-role host-${clientHostName} host-${clientHostName}
	unset PassWord
	# From here the host should download the PW2 (FACTOR2) and crypt.bin (CRYPT) then delete them from /PROV after they are stored locally.
	# remove client crypt file
	rm -rf /var/home/wavelet/config/${clientHostName}.crypt.bin
	exit 0
}

get_creds(){
	declare -a FILES=("/var/home/wavelet/.ssh/secrets/svr.crypt.bin" "/var/home/wavelet/.ssh/secrets/client.crypt.bin")
	for i in "${FILES[@]}"; do
		echo "looking for $i" >> /var/home/wavelet/logs/etcdlog.log
		if [[ -f $i ]]; then
			echo "File $i is configured." >> /var/home/wavelet/logs/etcdlog.log
			set_userArg
		else
			echo "No credential for $i configured!" >> /var/home/wavelet/logs/etcdlog.log
		fi
	done
}

set_userArg() {
	case $(hostname) in
		# If we are the server we use a different password than a client machine
		# This might be a silly way of doing this because:   
		#   (a) the password is now a variable in this shell 
		#   (b) will the variable be accessible from the above functions?
		svr*)       password2=$(cat /var/home/wavelet/config/svr.pw2.txt);
					password1=$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -nosalt -in /var/home/wavelet/.ssh/secrets/svr.crypt.bin -d);
					userArg="--user svr:$(echo ${password1} | base64 -d)";
		;;
		*)          password2=$(cat /var/home/wavelet/config/client.pw2.txt);
					password1=$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -nosalt -in /var/home/wavelet/.ssh/secrets/client.crypt.bin -d);
					userArg="--user host-$(hostname):$(echo ${password1} | base64 -d)";
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
echo -e "\n\n**New log**\n" >> /var/home/wavelet/logs/etcdlog.log
get_creds

case ${action} in
	# Read an etcd value stored under a hostname - note the preceding / 
	# Etcd does not have a hierarchical structure so we're 'simulating' directories by adding the /
	read_etcd)                  declare -A commandLine=([4]="${userArg}" [3]="get" [2]="/$(hostname)/${inputKeyName}" [1]="--print-value-only");
	;;
	# Read an etcd value set globally - may still be hostname but would be defined in inputKeyName
	read_etcd_global)           declare -A commandLine=([4]="${userArg}" [3]="get" [2]="${inputKeyName}" [1]="--print-value-only"); fID="clearText";
	;;
	# Read a set of etcd values by prefix.  I.E a list of IP addresses
	read_etcd_prefix)           declare -A commandLine=([4]="${userArg}" [3]="get" [2]="/$(hostname)/${inputKeyName}" [1]="--prefix" [0]="--print-value-only");
	;;
	# For global keys, values only
	read_etcd_prefix_global)    declare -A commandLine=([4]="${userArg}" [3]="get" [2]="${inputKeyName}" [1]="--prefix" [0]="--print-value-only"); fID="clearText";
	;;
	# For global keys + values, returned in a list key-value-key-value IFS is newline
	read_etcd_prefix_list)      declare -A commandLine=([4]="${userArg}" [3]="get" [2]="${inputKeyName}" [1]="--prefix"); fID="clearText";
	;;
	read_etcd_json_revision)    declare -A commandLine=([4]="${userArg}" [3]="get -w json" [1]="${inputKeyName}");
	;;
	read_etcd_lastrevision)     declare -A commandLine=([4]="${userArg}" [2]="get" [1]="${inputKeyName}" [0]="--rev=${revisionID}");
	;;
	# Want to return everything in the clear here
	read_etcd_keysonly)         declare -A commandLine=([4]="${userArg}" [3]="get" [2]="${inputKeyName}" [1]="--prefix" [0]="--keys-only"); fID="clearText";
	;;
	# Write an etcd value under a hostname.  Keys here are base64
	# Note -w 0 to disable base64 line wrapping, or we get a newline \n after every 76 chars.
	write_etcd)                 inputKeyValue=$(echo ${inputKeyValue} | base64 -w 0); declare -A commandLine=([4]="${userArg}" [3]="put" [2]="/$(hostname)/${inputKeyName}" [1]="--" [0]="${inputKeyValue}");
	;;
	# Write a global etcd value where the key is root and not considered "under" a host.  Keys here are clear text.
	write_etcd_global)          declare -A commandLine=([4]="${userArg}" [3]="put" [2]="${inputKeyName}" [1]="--" [0]="${inputKeyValue}");
	;;
	# Special function for writing ip addresses under /decoderip/ 
	write_etcd_client_ip)       declare -A commandLine=([4]="${userArg}" [3]="put" [2]="/decoderip/$(hostname)" [1]="--" [0]="${inputKeyValue}");
	;;
	# returns value list of IP Addresses, special case to parse directly to command (used for read_etcd_clients and the sed variant)
	read_etcd_clients*)         declare -A commandLine=([4]="${userArg}" [3]="get" [2]="--prefix" [1]="/decoderip/" [0]="--print-value-only"); fID="clearText";
	;;
	# Delete a key
	delete_etcd_key)            declare -A commandLine=([4]="${userArg}" [1]="del" [0]="/$(hostname)/${inputKeyName}"); fID="clearText";
	;;
	# Delete a global key
	delete_etcd_key_global)     declare -A commandLine=([4]="${userArg}" [1]="del" [0]="${inputKeyName}"); fID="clearText";
	;;
	# Delete keys on prefix
	delete_etcd_key_prefix)     declare -A commandLine=([4]="${userArg}" [2]="del" [1]="${inputKeyName}" [0]="--prefix"); fID="clearText";
	;;
	# Generate a user systemd watcher based off keyname and module arguments.
	generate_service)           generate_service "${inputKeyName}" "${waveletModule}" "${additionalArg}" "${userArg}"; fID="clearText";
	;;
	# Generates basic etcd role definitions
	generate_etcd_core_roles)   generate_etcd_core_roles;
	;;
	# Generates etcd host role definition
	generate_etcd_host_role)    generate_etcd_host_role "${inputKeyValue}";
	;;
	# Generates etcd host role definition
	client_provision_request)   declare -A commandLine=([4]="--user PROV" [2]="put" [1]="/PROV/REQUEST" [0]="${hostNameSys}"); fID="clearText";
	;;
	client_provision_response)  declare -A commandLine=([4]="--user PROV" [2]="get" [1]="/PROV/REQUEST" [0]="--print-value-only"); fID="clearText";
	;;
	check_status)               declare -A commandLine=([4]="${userArg}" [2]="endpoint status"); fID="clearText";
	;;
	# exit with error because other commands are not valid!
	*)          echo -e "\nInvalid command\n"; exit 1;
	;;
esac

# Because we need an output from this script, we can't enable logging (unless something's broken..)
#set -x
#exec >/var/home/wavelet/logs/etcdlog.log 2>&1
hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
main "${action}" "${inputKeyName}" "${inputKeyValue}" "${valueOnlySwitch}" "${userArg}"