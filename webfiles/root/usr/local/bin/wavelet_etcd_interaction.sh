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
			etcdctl --endpoints="${ETCDENDPOINT}" --cert-file "${clientCertificateFile}" --key-file "${clientKeyFile}" --ca-file "${certificateAuthorityFile}" ${commandLine[@]}" >> /var/home/${user}/logs/etcdlog.log
		etcdCommand(){
			printvalue=$(etcdctl --endpoints="${ETCDENDPOINT}" \
			--cert-file "${clientCertificateFile}" \
			--key-file "${clientKeyFile}" \
			--ca-file "${certificateAuthorityFile}" \
			${commandLine[@]})
		}
	else
		ETCDURI=http://${ETCDENDPOINT}/v3/kv/
		user=$(whoami)
		echo "Attempting: etcdctl --endpoints="${ETCDENDPOINT}" ${commandLine[@]}" >> /var/home/${user}/logs/etcdlog.log
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
WantedBy=default.target" > /var/home/${user}/.config/systemd/user/${waveletModule}.service
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
WantedBy=default.target" >> /var/home/${user}/.config/systemd/user/${waveletModule}.service
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
	# This is because the etcd root cred should be available only root or wavelet-root.
	# The other creds are in the wavelet userland.
	# Test for etcd accessibility, fail if no.
	if [[ "$EUID" -ne 0 ]]; then 
		echo "Please run as root"
  	exit
	fi
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
	mkdir -p /var/home/wavelet-root/.ssh/secrets
	local PassWord=$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9') 
	encrypt_pw_data "root" "${PassWord}"
	etcdctl --endpoints=${ETCDENDPOINT} user add root --new-user-password ${PassWord}
	etcdctl --endpoints=${ETCDENDPOINT} user grant-role root root
	unset PassWord
	# Server
	local PassWord=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')
	encrypt_pw_data "svr" "${PassWord}"
	etcdctl --endpoints=${ETCDENDPOINT} user add svr --new-user-password ${PassWord}
	etcdctl --endpoints=${ETCDENDPOINT} user grant-role svr server
	unset PassWord
	# WebUI
	local PassWord=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')
	encrypt_webui_data ${PassWord}
	etcdctl --endpoints=${ETCDENDPOINT} user add webui --new-user-password ${PassWord}
	etcdctl --endpoints=${ETCDENDPOINT} user grant-role webui webui
	# Create the PROV user
	etcdctl --endpoints=${ETCDENDPOINT} user add PROV --new-user-password "wavelet_provision"
	etcdctl --endpoints=${ETCDENDPOINT} user grant-role PROV PROV
	unset PassWord
	# User backend pw if set during setup (add as option later)
	etcdctl auth enable
	test_auth "svr"
	test_auth "webui"
	exit 0
}

encrypt_pw_data() {	
	# This makes a poor man's two factor auth to get etcd access.
	local user=$1
	local pw=$2
	local password2=$(head -c 16 /dev/urandom |  base64 | tr -dc 'a-zA-Z0-9')
	if [[ "${user}" == "root" ]]; then
		mkdir -p /var/home/wavelet-root/.ssh/secrets; secretsDir="/var/home/wavelet-root/.ssh/secrets"
		mkdir -p /var/home/wavelet-root/config; configDir="/var/home/wavelet-root/config"
		user="wavelet-root"
	else
		user="wavelet"
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
	chown ${user}:${user} "${secretsDir}/${1}.crypt.bin"; chown ${user}:${user} "${configDir}/${1}.pw2.txt"
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
	echo "testing $1"
	if [[ $1 == "svr" ]]; then
		echo "Testing svr auth.." >> /var/home/${user}/logs
		KEYNAME="svr_auth"; KEYVALUE="True"
		/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
		returnVal=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}")
		echo "Returned: ${returnVal}" >> /var/home/${user}/logs
		if [[ ${returnVal} == "True" ]]; then
			echo "Test successful!" >> /var/home/${user}/logs
		else
			echo "Test failed!" >> /var/home/${user}/logs
			exit 1
		fi
	else
		echo "Testing webui auth.." >> /var/home/${user}/logs
		KEYNAME="/UI/ui_auth"
		local password2=$(cat /var/home/wavelet/http-php/secrets/pw2.txt)
		local decrypt=$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -nosalt -in /var/home/wavelet/http-php/secrets/crypt.bin -d)
		local webuipw=$(echo "${decrypt}" | base64 -d)
		etcdctl --endpoints=${ETCDENDPOINT} --user webui:${webuipw} put "/UI/ui_auth" -- "True"
		echo "Attempting: etcdctl --endpoints=${ETCDENDPOINT} --user webui:${webuipw} get ${KEYNAME}" >> /var/home/${user}/logs/etcdlog.log
		returnVal=$(etcdctl --endpoints=${ETCDENDPOINT} --user webui:${webuipw} get "${KEYNAME}" --print-value-only)
		echo "Returned: ${returnVal}" >> /var/home/${user}/logs
		if [[ ${returnVal} == *"True"* ]]; then
			echo "Test successful!" >> /var/home/${user}/logs
		else
			echo "Test failed!" >> /var/home/${user}/logs
			exit 1
		fi
	fi
}

generate_etcd_host_role(){
	# This is called from a specific systemd watcher service to handle provision requests.
	# Hosts can modify keys under themselves: /$(hostname)/$, they should not be able to write global "root" keys.
	# These permissions can really only be added after the initial host provisioning is completed, because they do not exist prior to this.
	# This is processed on the server only from wavelet-root user.
	if [[ "$EUID" -ne 9337 ]]; then 
		echo "Please run as wavelet-root" >> /var/home/${user}/logs
  	exit
	fi
	echo "Generating role and user for ETCD client.." >> /var/home/wavelet-root/logs/etcdlog.log
	KEYNAME="/PROV/REQUEST"; clientHostName=$(etcdctl --endpoints=${ETCDENDPOINT} --user PROV:wavelet_provision get "${KEYNAME}" --print-value-only)
	echo "Client hostname retrieved for: ${clientHostName}" >> /var/home/wavelet-root/logs/etcdlog.log
	etcdctl --endpoints=${ETCDENDPOINT} ${userArg} role add ${clientHostName:0:7}
	etcdctl --endpoints=${ETCDENDPOINT} ${userArg} put /UI/hosts/${clientHostName} -- 1
	etcdctl --endpoints=${ETCDENDPOINT} ${userArg} put /UI/hostlist/${clientHostName} -- 1
	etcdctl --endpoints=${ETCDENDPOINT} ${userArg} put /UI/hostHash/${clientHostName} -- 1
	etcdctl --endpoints=${ETCDENDPOINT} ${userArg} put /${clientHostName} -- 1
	etcdctl --endpoints=${ETCDENDPOINT} ${userArg} role grant-permission ${clientHostName:0:7} readwrite "/UI/hosts/${clientHostName}/" --prefix=true
	etcdctl --endpoints=${ETCDENDPOINT} ${userArg} role grant-permission ${clientHostName:0:7} readwrite "/UI/hostlist/" --prefix=true # This one could be dangerous.
	etcdctl --endpoints=${ETCDENDPOINT} ${userArg} role grant-permission ${clientHostName:0:7} readwrite "/UI/hosthash/" --prefix=true # This one could be dangerous.
	etcdctl --endpoints=${ETCDENDPOINT} ${userArg} role grant-permission ${clientHostName:0:7} readwrite "/hosthash/" --prefix=true # This one could be dangerous.
	etcdctl --endpoints=${ETCDENDPOINT} ${userArg} role grant-permission ${clientHostName:0:7} readwrite "/${clientHostName}/" --prefix=true
	local PassWord=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')
	etcdctl --endpoints=${ETCDENDPOINT} ${userArg} user add "${clientHostName:0:7}" --new-user-password "${PassWord}"
	echo "Testing access.." >> /var/home/wavelet-root/logs/etcdlog.log
	printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} --user ${clientHostName:0:7}:${PassWord} get "/${clientHostName}/")
	echo "Returned value should be 1:  ${printvalue}" >> /var/home/wavelet-root/logs/etcdlog.log
	# This makes a poor man's two factor auth to get etcd access.
	local user="${clientHostName}"
	local password2=$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')
	echo "${PassWord}" | base64 | openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -nosalt -out /var/home/wavelet-root/config/${clientHostName:0:7}.crypt.bin
	local result=$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -nosalt -in /var/home/wavelet-root/config/${clientHostName:0:7}.crypt.bin -d)
	local result=$(echo $result | base64 -d)
	if [[ $result == $PassWord ]]; then
		echo "Password encrypted and tested successfully!" >> /var/home/wavelet-root/logs/etcdlog.log
	else
		echo "Decrypt failed, something is wrong!" >> /var/home/wavelet-root/logs/etcdlog.log
		exit 1
	fi
	# Upload generated files
	declare -A commandLine=([4]="--user PROV:wavelet_provision" [3]="put" [2]="/PROV/CRYPT" [1]="--" [0]="$(cat /var/home/wavelet-root/config/${clientHostName:0:7}.crypt.bin | base64)"); fID="clearText"; main
	declare -A commandLine=([4]="--user PROV:wavelet_provision" [3]="put" [2]="/PROV/FACTOR2" [1]="--" [0]="${password2}"); fID="clearText"; main
	etcdctl --endpoints=${ETCDENDPOINT} ${userArg} user grant-role ${clientHostName:0:7} ${clientHostName:0:7}
	unset PassWord
	# From here the host should download the PW2 (FACTOR2) and crypt.bin (CRYPT) then delete them from /PROV after they are stored locally.
	# remove client crypt file from the server, it lives in etcd until the client has downloaded and tested it, then it's removed.
	rm -rf /var/home/wavelet-root/config/${clientHostName}.crypt.bin
	KEYNAME="/PROV/RESPONSE" KEYVALUE="True"; etcdctl --endpoints=${ETCDENDPOINT} --user PROV:wavelet_provision put "${KEYNAME}" -- "${clientHostName}"
	exit 0
}

client_provision_get_data() {
	if [[ "$EUID" -ne 1337 ]]; then 
		echo "Please run as wavelet" >> /var/home/${user}/logs
  	exit
	fi
	# This is run from the client side as 1337/wavelet, from provision_watcher, and retrieves the populated data from etcd
	echo "Getting client data from previous provision request.." >> /var/home/wavelet/logs/etcdlog.log
	mkdir -p /var/home/wavelet/.ssh/secrets
	userArg="--user PROV:wavelet_provision" 
	declare -A commandLine=([3]="${userArg}" [2]="get" [1]="/PROV/RESPONSE" [0]="--print-value-only"); fID="clearText"; local output=$(main)
	echo "Got host: $output" >> /var/home/wavelet/logs/etcdlog.log
	if [[ $(hostname) != ${output} ]]; then
		echo "this request isn't for me.  Ignoring." >> /var/home/wavelet/logs/etcdlog.log
		exit 0
	fi
	declare -A commandLine=([3]="${userArg}" [2]="get" [1]="/PROV/CRYPT" [0]="--print-value-only"); fID="clearText"; local output=$(main)
	#echo "Got Crypt: $output" >> /var/home/${user}/logs/etcdlog.log
	echo ${output} | base64 -d > /var/home/wavelet/.ssh/secrets/$(hostname).crypt.bin
	declare -A commandLine=([3]="${userArg}" [2]="get" [1]="/PROV/FACTOR2" [0]="--print-value-only"); fID="clearText"; local output=$(main)
	#echo "Got factor2: $output" >> /var/home/${user}/etcdlog.log
	echo ${output} > /var/home/wavelet/config/pw2.txt 
	# test Auth now we have the appropriate keys
	KEYNAME="Client_test"; KEYVALUE="True"; /usr/local/bin/wavelet_etcd_interaction.sh "write_etcd" "${KEYNAME}" "${KEYVALUE}"
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd" "${KEYNAME}")
	if [[ ${printvalue} == "${KEYVALUE}" ]]; then
		echo "Client test successful!" >> /var/home/wavelet/logs/etcdlog.log
		# Delete keys now that we are done
		declare -A commandLine=([4]="${userArg}" [1]="del" [0]="/PROV/CRYPT"); fID="clearText"; main
		declare -A commandLine=([4]="${userArg}" [1]="del" [0]="/PROV/FACTOR2"); fID="clearText"; main
		declare -A commandLine=([4]="${userArg}" [1]="del" [0]="/PROV/RESPONSE"); fID="clearText"; main
		echo "Provisioning process completed.  Client may resume normal operation!" >> /var/home/wavelet/logs/etcdlog.log
	else
		echo "Client test unsuccessful!  Please see logs." >> /var/home/wavelet/logs/etcdlog.log
		echo "We got ${printvalue} back" >> /var/home/wavelet/logs/etcdlog.log
		exit 1
	fi
}

set_userArg() {
	case $(hostname) in
		# If we are the server we use a different password than a client machine
		# This might be a silly way of doing this because:   
		#   (a) the password is now a variable in this shell 
		#   (b) will the variable be accessible from the above functions?
		svr*)       svr_userArg;
		;;
		*)          get_client_pw
		;;
	esac
	#echo "User args: ${userArg}" >> /var/home/wavelet/logs/etcdlog.log
}

get_client_pw(){
	# Checks if we are provisioned or not, if we aren't we use PROV, if we are, generates password from available factors.
	if [[ -f /var/provisioned.complete ]]; then
		echo "ETCD provisioning is not complete, defaulting to PROV" >> /var/home/wavelet/logs/etcdlog.log
		userArg="--user PROV:wavelet_provision"
	else
		local password2=$(cat /var/home/wavelet/config/pw2.txt); hostname=$(hostname);
		local password1=$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -nosalt -in /var/home/wavelet/.ssh/secrets/$(hostname).crypt.bin -d | base64 -d);
		userArg="--user ${hostname:0:7}:${password1}";
	fi
}

svr_userArg() {
	# Special case for server, we need to determine if we are in wavelet-root and therefore need etcd root for prov request
	if [[ "$EUID" -eq 9337 ]]; then 
		echo "Called from wavelet root, we are dealing with a provision request" >> /var/home/wavelet-root/logs/etcdlog.log
		local password2=$(cat /var/home/wavelet-root/config/root.pw2.txt);
		local password1=$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -nosalt -in /var/home/wavelet-root/.ssh/secrets/root.crypt.bin -d | base64 -d);
		userArg="--user root:${password1}"
	else
		echo "Using svr account for normal operations." >> /var/home/${user}/logs/etcdlog.log
		local password2=$(cat /var/home/wavelet/config/svr.pw2.txt);
		local password1=$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -nosalt -in /var/home/wavelet/.ssh/secrets/svr.crypt.bin -d | base64 -d);
		userArg="--user svr:${password1}"
	fi
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

# Logfile has to live in $HOME here, because wavelet-root cannot write to wavelet's homedir.
set -x
user=$(whoami)
mkdir -p /var/home/${user}/logs
echo -e "\n\n**New log**" >> /var/home/${user}/logs/etcdlog.log

set_userArg

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
	generate_etcd_host_role)    generate_etcd_host_role;
	;;
	# Generates etcd host role definition
	client_provision_request)   declare -A commandLine=([4]="--user PROV:wavelet_provision" [3]="put" [2]="/PROV/REQUEST" [1]="--" [0]="$(hostname)"); fID="clearText";
	;;
	client_provision_data)		client_provision_get_data;
	;;
	client_provision_response)  declare -A commandLine=([3]="--user PROV:wavelet_provision" [2]="get" [1]="/PROV/REQUEST" [0]="--print-value-only"); fID="clearText";
	;;
	check_status)               declare -A commandLine=([4]="${userArg}" [2]="endpoint status"); fID="clearText";
	;;
	# exit with error because other commands are not valid!
	*)         					 echo -e "\nInvalid command\n"; exit 1;
	;;
esac

# Because we need an output from this script, we can't enable logging (unless something's broken..)
# set -x
#exec >> /var/home/${user}/logs/etcdlog.log 2>&1
hostNameSys=$(hostname)
hostNamePretty=$(hostnamectl --pretty)
main "${action}" "${inputKeyName}" "${inputKeyValue}" "${valueOnlySwitch}" "${userArg}"