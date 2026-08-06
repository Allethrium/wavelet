#!/bin/bash

# Wavelet etcd management.  
# Originally part of etcd_interaction
# Handles etcd admin functions, initial setup, new role creation etc.
# Now includes host role/user generation functionality
# Runs initially with root privs, but also gets called under wavelet-root for new host user creation.

# Add our attempt at a password security solution here
ETCDSECURECREDENTIALSMOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_secure_credentials.sh" ]]; then
	source "/var/wavelet_ramfs/wavelet_secure_credentials.sh"
	ETCDSECURECREDENTIALSMOD="/var/wavelet_ramfs/wavelet_secure_credentials.sh"
else
	source "/usr/local/bin/wavelet_secure_credentials.sh"
	ETCDSECURECREDENTIALSMOD="/usr/local/bin/wavelet_secure_credentials.sh"
fi

ETCDINTERACTIONMOD=""
if [[ -f "/var/wavelet_ramfs/etcd_interaction_hooks.sh" ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source "/usr/local/bin/etcd_interaction_hooks.sh"
	ETCDINTERACTIONMOD="/usr/local/bin/etcd_interaction_hooks.sh"
fi

# Source settings
# TODO - reduce etcd calls based on data that are available from wavelet.conf now.
source "/etc/wavelet.conf"

#Etcd Interaction global variables
ETCDENDPOINT="https://$SVR_HOSTNAME:2379"
if [[ -z "$ETCDENDPOINT" ]]; then
	# populate from waveletdir because we didn't have read access to the root copy
	ETCDENDPOINT="https://$SVR_HOSTNAME:2379"
fi

certificateAuthorityFile="/etc/ipa/ca.crt"

# Helper function for consistent command execution
execute_etcd_cmd() {
	# Redact passwords from logging
	local logCmd=$(echo "$@" | sed -e 's/--new-user-password [^ ]*/--new-user-password REDACTED/g' -e 's/--user [^ ]*/--user REDACTED/g')
	echo "Executing: etcdctl $logCmd" >> /var/home/"${user}"/logs/etcdlog.log
	etcdctl "$@"
}

# Define cleanup handler
cleanup() {
	unset ETCDCTL_ENDPOINTS
	unset ETCDCTL_USER
	unset ETCDCTL_CACERT
	unset ETCDCTL_PASSWORD
}

generate_etcd_core_roles(){
	# Generate etcd roles
	# Etcd roles must be generated because the wavelet_build, detectv4l modules do not know if security is on or off
	# webui ensures the webui can only write to keys under the range "/UI/" and all other orchestration happens separately.
	if [[ "$EUID" -ne 0 ]];	then
		echo "  Only runs during initial setup as root." >> "/var/home/wavelet/logs/etcdlog.log"
		exit 1
	fi
	# Generate our userdirs that will support the wrapper files
	init_wrapper_contexts
	# we need to create this dir
	mkdir -p "/var/home/root/logs"
	echo -e "\n\n  Generating etcd users and roles, setting userArg to null.." >> "/root/logs/etcdlog.log"
	unset userArg
	etcdctl --endpoints="$ETCDENDPOINT" --cacert="$certificateAuthorityFile" role add webui
	KEYNAME="/UI/"; KEYVALUE="True"; etcdctl --endpoints="$ETCDENDPOINT" --cacert="$certificateAuthorityFile" put "$KEYNAME" -- "$KEYVALUE"
	etcdctl --endpoints="$ETCDENDPOINT" --cacert="$certificateAuthorityFile" role grant-permission webui --prefix=true readwrite "/UI/"
	# The server should be able to modify everything, and has its own "root" role.  Most coordination happens on the server, so this is fine.
	etcdctl --endpoints="$ETCDENDPOINT" --cacert="$certificateAuthorityFile" role add server
	etcdctl --endpoints="$ETCDENDPOINT" --cacert="$certificateAuthorityFile" role grant-permission server --prefix=true readwrite ""
	# The PROV role is designed for provision requests and is 'wide open' so that an initial host can request a provision key
	etcdctl --endpoints="$ETCDENDPOINT" --cacert="$certificateAuthorityFile" role add PROV
	etcdctl --endpoints="$ETCDENDPOINT" --cacert="$certificateAuthorityFile" role grant-permission PROV --prefix=true readwrite "/PROV/"
	etcdctl --endpoints="$ETCDENDPOINT" --cacert="$certificateAuthorityFile" role add ENROLL
	etcdctl --endpoints="$ETCDENDPOINT" --cacert="$certificateAuthorityFile" role grant-permission ENROLL --prefix=true readwrite "/ENROLL/"
	# DHCP role is a specific key for the DHCP IPC into the rest of the system
	etcdctl --endpoints="$ETCDENDPOINT" --cacert="$certificateAuthorityFile" role add DHCP
   	etcdctl --endpoints="$ETCDENDPOINT" --cacert="$certificateAuthorityFile" role grant-permission DHCP --prefix=true readwrite "/DHCP"
	echo "  Core etcd roles generated, moving on to user accounts.." >> "/root/logs/etcdlog.log"
	generate_etcd_core_users
}

generate_etcd_core_users(){
	# Generate basic etcd users
	# This should be invoked by the root user prior to everything getting spun up. 
	# This is because the etcd root cred should be available only root or wavelet-root.
	# The other creds are in the wavelet userland.
	# Test for etcd accessibility, fail if no.
	if [[ "$EUID" -ne 0 ]]; then 
	    echo "  Please run as root" >> "/root/logs/etcdlog.log"
	    exit
	fi
	echo "  Generating core user accounts.." >> "/root/logs/etcdlog.log"
	KEYNAME="Global_test"; KEYVALUE="True"; etcdctl --endpoints="$ETCDENDPOINT" --cacert="$certificateAuthorityFile" put "$KEYNAME" -- "$KEYVALUE"
	returnVal=$(etcdctl --endpoints="$ETCDENDPOINT" --cacert="$certificateAuthorityFile" get "$KEYNAME" --print-value-only)
	if [[ "$returnVal" == "True" ]];then
	    echo "  Test key value correct, generating accounts and enabling auth.." >> "/root/logs/etcdlog.log"
	    etcdctl --endpoints="$ETCDENDPOINT" --cacert="$certificateAuthorityFile" del "$KEYNAME"
	else
	    echo "  The test key value was not successfully retrieved.  Please review logs to troubleshoot!" >> /root/logs/etcdlog.log
	    exit 1
	fi
	# Ensure directories are present
	mkdir -p /var/home/wavelet-root/.ssh/secrets /var/home/wavelet-root/config
	mkdir -p /var/home/wavelet/.ssh/secrets /var/home/wavelet/config
	mkdir -p /root/.ssh/secrets /root/config
	mkdir -p /root/logs /var/home/wavelet-root/logs /var/home/wavelet/logs
	# Set permissions
	chown -R wavelet-root:wavelet-root /var/home/wavelet-root
	chown -R wavelet:wavelet /var/home/wavelet
	chmod 700 /var/home/wavelet-root/.ssh/secrets /var/home/wavelet/.ssh/secrets
	chmod 700 /root/.ssh/secrets
	echo "  Appropriate directories generated and ownership set to restricted.." >> "/root/logs/etcdlog.log"

	# Root credential (auth enable/disable, user and role account creation and modification)
	#  local user_context="$1" (root, wavelet-root, wavelet, webui)
	#  local credential_name="$2" (etcd user)
	#  local credential_value="$3" (password/factor)
	#  local purpose="${4:-etcd}"
	local PassWord;
	PassWord="$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')"
	encrypt_credential "wavelet-root" "root" "${PassWord}" "etcd"
	# TODO - disable in prod deployment
	echo "	Root credential generated: root:$PassWord" >> "/var/home/$user/logs/testCreds.log"
	etcdctl --endpoints="${ETCDENDPOINT}" --cacert="${certificateAuthorityFile}" user add root --new-user-password "${PassWord}"
	etcdctl --endpoints="${ETCDENDPOINT}" --cacert="${certificateAuthorityFile}" user grant-role root root
	# Server
	PassWord="$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')"
	encrypt_credential "wavelet" "svr" "${PassWord}" "etcd"
	etcdctl --endpoints="${ETCDENDPOINT}" --cacert="${certificateAuthorityFile}" user add svr --new-user-password "${PassWord}"
	etcdctl --endpoints="${ETCDENDPOINT}" --cacert="${certificateAuthorityFile}" user grant-role svr server
	# WebUI
	PassWord="$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')"
	encrypt_credential "wavelet" "webui" "${PassWord}" "etcd"
	etcdctl --endpoints="${ETCDENDPOINT}" --cacert="${certificateAuthorityFile}" user add webui --new-user-password "${PassWord}"
	etcdctl --endpoints="${ETCDENDPOINT}" --cacert="${certificateAuthorityFile}" user grant-role webui webui
	# Create the PROV user
	PassWord="$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')"
	encrypt_credential "wavelet-root" "PROV" "${PassWord}" "etcd"
	etcdctl --endpoints="${ETCDENDPOINT}" --cacert="${certificateAuthorityFile}" user add PROV --new-user-password "${PassWord}"
	etcdctl --endpoints="${ETCDENDPOINT}" --cacert="${certificateAuthorityFile}" user grant-role PROV PROV
	# Add the provision credential to the decoder host.   This allows the host to request an etcd username and roles to its own keys.
	sed -i "s|#PROVISIONPWHERE|$PassWord|g" /var/home/wavelet/config/decoder_custom.yml
	# Create the ENROLL user + pw
	PassWord="$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')"
	encrypt_credential "wavelet-root" "ENROLL" "${PassWord}" "etcd"
	etcdctl --endpoints="${ETCDENDPOINT}" --cacert="${certificateAuthorityFile}" user add ENROLL --new-user-password "$PassWord"
	etcdctl --endpoints="${ETCDENDPOINT}" --cacert="${certificateAuthorityFile}" user grant-role ENROLL ENROLL
	# This generates a password for the etcd enrollment key user within our ignition file for decoders on this cluster.
	# This is NOT the domain enrollment credential, it only allows a client to request domain enrollment!
	sed -i "s|#ENROLLPWHERE|$PassWord|g" /var/home/wavelet/config/decoder_custom.yml
	# DHCP user
	# We store this as a podman secret and perform no further work with it
	PassWord="$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')"
	etcdctl --endpoints="${ETCDENDPOINT}" --cacert="${certificateAuthorityFile}" user add DHCP --new-user-password "$PassWord"
	etcdctl --endpoints="${ETCDENDPOINT}" --cacert="${certificateAuthorityFile}" user grant-role DHCP DHCP
	podman secret create dhcpUser - <<<"$PassWord"
	echo "  Generated core etcd users and roles, enabling cluster authentication and running tests.." >> /root/logs/etcdlog.log
	etcdctl --endpoints="${ETCDENDPOINT}" --cacert="${certificateAuthorityFile}" auth enable
	sleep 2
	chown -R wavelet-root:wavelet-root /var/home/wavelet-root
	chown -R wavelet:wavelet /var/home/wavelet
	# Restart the kea DHCP server service to make the secret available as the env $dhcpUser
	sed -i '/^\[Container\]/a Secret=dhcpUser,type=env,target=dhcpUser' /etc/containers/systemd/kea.container
	systemctl daemon-reload && systemctl restart kea.service
	# Create a flag to tell us etcd auth is enabled, and remove the etcd provision flag from /var/
	echo "ETCD_AUTH_ENABLED=1" >> /etc/wavelet.conf
	rm -rf /var/server.etcd.provision
	chown -R wavelet-root:wavelet-root /var/home/wavelet-root; chown -R wavelet:wavelet /var/home/wavelet
	unset PassWord
	test_coreUserContexts
}

test_coreUserContexts(){
	# Runs through our core users in their appropriate contexts and exits 1 if anything fails.
	# Configuration constants
	# corresponding etcd keys
	declare -A USERS=(
		["root"]="/root_test"
		["ENROLL"]="/ENROLL/test"
		["PROV"]="/PROV/test"
		["svr"]="SVR"
		["webui"]="/UI/test"
	)
	# corresponding system user to run under (note we don't use etcd from system root account)
	declare -A CONTEXT=(
		["root"]="wavelet-root"
		["ENROLL"]="wavelet-root"
		["PROV"]="wavelet-root"
		["svr"]="wavelet"
		["webui"]="wavelet"
	)
	for etcdUser in "${!USERS[@]}"; do
	    local etcdpath; local context; local password
	    etcdpath="${USERS[$etcdUser]}"
	    # Get the user context (the system user account to run under)
	    context="${CONTEXT[$etcdUser]}"
	    # Decrypt credential to shared memory
	    log_file="/root/logs/testCreds.log"
	    memory_file="$(decrypt_credential_to_memory "$context" "$etcdUser")"
	    if [[ $? -ne 0 ]]; then
		    echo "  Failed to decrypt credential for $context" >> "$log_file"
		    return 1
	    fi
	    # Attempt to write to the test key in etcd
	    # Use ETCDCTL_USER and ETCDCTL_PASSWORD environment variables to avoid password exposure in logs and ps
	    local etcd_password="$(cat "$memory_file")"
	    if ! ETCDCTL_USER="$etcdUser" ETCDCTL_PASSWORD="$etcd_password" etcdctl --endpoints="$ETCDENDPOINT" --cacert="$certificateAuthorityFile" put "$etcdpath" -- "test"; then
		    echo "  Failed to execute etcd command for $context" >&2
		    return 1
	    fi
	    # Clean up: Remove the memory file after testing
	    echo " Removing test key.."
	    ETCDCTL_USER="$etcdUser" ETCDCTL_PASSWORD="$etcd_password" etcdctl --endpoints="$ETCDENDPOINT" --cacert="$certificateAuthorityFile" del "$etcdpath"
	    rm -f "$memory_file" || true
	done
	echo "	Core users provisioned and tested!"
}

encrypt_pw_data() {
	local user="$1"
	local password="$2"
	local log_file="/root/logs/wavelet_credentials.log"
	echo "	Encrypting password for user: $user" >> "${log_file}"
	# Map user parameter to user context
	local user_context
	case "$user" in
		"root") user_context="root";;
		"svr") user_context="wavelet-root";;
		"enroll") user_context="wavelet-root";;
		"webui") user_context="wavelet";;
		*) user_context="wavelet"; echo "	WARNING: Unmapped user '${user}', defaulting to 'wavelet' context" >> "${log_file}";;
	esac
	echo "	Mapped user '${user}' to context '${user_context}'" >> "${log_file}"
	# Create necessary directories if they don't exist
	local user_home="$user_context"
	if [[ "$user_context" == "root" ]]; then
		mkdir -p /root/.ssh/secrets /root/config
		chmod 700 /root/.ssh/secrets
	else
		mkdir -p "${user_home}/.ssh/secrets" "${user_home}/config"
		chmod 700 "${user_home}/.ssh/secrets"
		# Set proper ownership
		case "$user_context" in
			"wavelet-root") chown -R wavelet-root:wavelet-root "${user_home}/.ssh" "${user_home}/config"
			;;
			"wavelet") chown -R wavelet:wavelet "${user_home}/.ssh" "${user_home}/config"
			;;
		esac
	fi

	# Encrypt the credential
	local result=0
	encrypt_credential "$user_context" "${user}_password" "$password" "etcd" || result=$?
	if [[ $result -ne 0 ]]; then
	echo "    ERROR: Failed to encrypt credential for user '$user'" >> "${log_file}"
	return 1
	fi
	echo "    Successfully encrypted credential for user '$user'" >> "${log_file}"
	return 0
}

encrypt_webui_data() {
	# webui goes to different spots as they need to be accessible by php-fpm for the web processes.
	local pw; local password2; local result
	pw=$1
	password2="$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')"
	mkdir -p /var/home/wavelet/http-php/secrets/; chown -R wavelet:wavelet /var/home/wavelet/http-php/secrets/
	echo "${password2}" > /var/home/wavelet/http-php/secrets/pw2.txt
	echo "${pw}" | base64 | openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -out /var/home/wavelet/http-php/secrets/crypt.bin
	result=$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -in /var/home/wavelet/http-php/secrets/crypt.bin -d)
	result="$(echo $result | base64 -d)"
	if [[ "$result" == "$pw" ]]; then
	echo "  Password encrypted and tested successfully!"
	else
	echo "  Decrypt failed, something is wrong!"
	exit 1
	fi
	# Remember to chown and chmod
	chown -R wavelet:wavelet /var/home/wavelet/http-php/secrets/
	chmod 700 /var/home/wavelet/http-php/secrets/
}

test_auth() {
    local password2; local decrypt; local webuipw
	echo "  Testing auth for account: $1"
	if [[ $1 == "svr" ]]; then
	echo "  Testing svr auth.." >> /var/home/"${user}"/logs/etcdlog.log
	KEYNAME="svr_auth"; KEYVALUE="True"
	"$ETCDINTERACTIONMOD" "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	returnVal="$("$ETCDINTERACTIONMOD" 'read_etcd_global' $KEYNAME)"
	echo "  Returned: ${returnVal}" >> /var/home/"${user}"/logs/etcdlog.log
	if [[ "${returnVal}" == "True" ]]; then
		echo "  Test successful!" >> /var/home/"${user}"/logs/etcdlog.log
	else
		echo "  Test failed!" >> /var/home/"${user}"/logs/etcdlog.log
		exit 1
	fi
	else
	echo "  Testing webui auth.." >> /var/home/"${user}"/logs/etcdlog.log
	KEYNAME="/UI/ui_auth"
	password2=$(cat /var/home/wavelet/http-php/secrets/pw2.txt)
	decrypt=$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -in /var/home/wavelet/http-php/secrets/crypt.bin -d)
	webuipw=$(echo "${decrypt}" | base64 -d)
	# Use ETCDCTL_USER and ETCDCTL_PASSWORD environment variables to avoid password exposure in logs and ps
	ETCDCTL_USER="webui" ETCDCTL_PASSWORD="${webuipw}" etcdctl --endpoints="${ETCDENDPOINT}" --cacert="/etc/ipa/ca.crt" put "/UI/ui_auth" -- "True"
	# Log without password for security
	echo "  Attempting: etcdctl --endpoints=${ETCDENDPOINT} --cacert=${certificateAuthorityFile} get ${KEYNAME}" >> /var/home/"${user}"/logs/etcdlog.log
	returnVal=$(ETCDCTL_USER="webui" ETCDCTL_PASSWORD="${webuipw}" etcdctl --endpoints="${ETCDENDPOINT}" --cacert="${certificateAuthorityFile}" get "${KEYNAME}" --print-value-only)
	echo "  Returned: ${returnVal}" >> /var/home/"${user}"/logs/etcdlog.log
	if [[ "${returnVal}" == *"True"* ]]; then
		echo "  Test successful!" >> /var/home/"${user}"/logs/etcdlog.log
	else
		echo "  Test failed!" >> /var/home/"${user}"/logs/etcdlog.log
		exit 1
	fi
	fi
}

generate_etcd_host_role() {
	# This is called from a specific systemd watcher service to handle provision requests.
	# Hosts can modify keys under themselves: /"${hostNameSys}"/$, they should not be able to write global "root" keys.
	# These permissions can really only be added after the initial host provisioning is completed, because they do not exist prior to this.
	# This is processed on the ***server only*** from wavelet-root user.
	if [[ "$EUID" -ne 9337 ]]; then
		echo "	Please run as wavelet-root" >> /var/home/"${user}"/logs/etcdlog.log
		exit
	fi
	# Log directory setup
	user="wavelet-root"
	mkdir -p "/var/home/${user}/logs"
	mkdir -p "/var/home/${user}/config"
	# Get user arguments from secure credentials (will fail if run without etcd root user)
	generate_etcd_userarg "user=wavelet-root" "extraargs=root"
	export ETCDCTL_ENDPOINTS="https://$SVR_HOSTNAME:2379"
	export ETCDCTL_CACERT="/etc/ipa/ca.crt"
	if [[ $? -ne 0 ]]; then
		echo "	Failed to get secure etcd credentials" >> "/var/home/${user}/logs/etcdlog.log"
		exit 1
	fi
	echo "	Generating role and user for ETCD client.." >> "/var/home/${user}/logs/etcdlog.log"
	if [[ "$ETCDCTL_USER" != "root" ]]; then
		echo "	Etcd user incorrect, please check env!"
		exit 1
	fi
	# Get client hostname from PROV request
	clientHostName="$(etcdctl get /PROV/REQUEST --print-value-only)"
	if [[ -z "$clientHostName" ]]; then
		echo "		Client hostname is empty! Cannot continue!" >> "/var/home/${user}/logs/etcdlog.log"
		exit 1
	fi
	# Validate clientHostName against allowed characters
	if [[ ! "$clientHostName" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,62}$ ]]; then
		echo "		Client hostname '$clientHostName' contains invalid characters! Cannot continue!" >> "/var/home/${user}/logs/etcdlog.log"
		exit 1
	fi
	clientHostNameShort="${clientHostName:0:7}"
	echo "  Client hostname retrieved for: $clientHostName" >> /var/home/wavelet-root/logs/etcdlog.log
	# Create role for client
	etcdctl role add "$clientHostNameShort"
	# Helper functions for key and role operations
	createCmd() {
		etcdctl put "${1}" -- "${2}"
	}
	roleCmd() {
		# Read + Write and prefixes
		etcdctl role grant-permission "$clientHostNameShort" readwrite "${1}" --prefix=true
	}
	roleCmdReadOnly() {
		# ReadOnly and prefixes
		etcdctl role grant-permission "$clientHostNameShort" read "${1}" --prefix=true
	}
	roleCmdReadKeyOnly() {
		# Read that key only
		etcdctl role grant-permission "$clientHostNameShort" read "${1}" --prefix=false
	}
	# Generate then acquire the hash value for this host
	# Since everything starts its life in wavelet as a decoder, this is always "dec"
	event_generate_hash dec;
	# The host has full access to its own keys on the backend
	roleCmd "/HOSTS/$clientHostName"

	echo "	Generating /HOSTS/$clientHostName root keys and assigning prefix permissions.."
	# Read the client's assigned hash value from event_generate_hash here
	if [[ -z "$hostHash" ]]; then
		KEYNAME="/HOSTS/$clientHostName"; clientHash="$("$ETCDINTERACTIONMOD" 'read_etcd_global' $KEYNAME)"
	else
		clientHash="$hostHash"
	fi
	# Everyone should be able to read:
	# globals
	# the primary server group hash
	# the server host hash.
	roleCmdReadOnly "/UI/GLOBALS/"
	roleCmdReadOnly "/GROUPS/$(hostname)"
	roleCmdReadKeyOnly "/HOSTS/$(hostname)"
	# Read-only keys
	KEY="CA_CERT"; roleCmdReadOnly "${KEY}"
	KEY="SVR"; roleCmdReadOnly "${KEY}"
	# The hosts should be able to read all group states and keys
	KEY="/UI/GROUPS/"; roleCmdReadOnly "${KEY}"
	# Hosts should be able to read their own UI prefix
   	KEY="/UI/HOSTS/$clientHash"; roleCmdReadOnly "$KEY"
	# Generate client password and create user
	local PassWord; local password2; local result
	PassWord="$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')"
	echo "  Generating new user for: $clientHostNameShort" >> "/var/home/wavelet-root/logs/etcdlog.log"
	etcdctl user add "$clientHostNameShort" --new-user-password "${PassWord}"
	# Two-factor authentication setup
	password2="$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')"
	echo "${PassWord}" | openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" \
		-out "/var/home/wavelet-root/config/.$clientHostNameShort.enc"
	# Verify encryption worked
	echo "  Verifying password setup.." >> "/var/home/wavelet-root/logs/etcdlog.log"
	result="$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass pass:${password2} \
		-in /var/home/wavelet-root/config/.$clientHostNameShort.enc -d)"
	result="$(echo $result)"
	if [[ "$result" == "$PassWord" ]]; then
	    local clientArg
		echo "  Password encrypted and tested successfully!" >> "/var/home/wavelet-root/logs/etcdlog.log"
		# Ensure our successfully generated user credentials are assigned to our etcd role, otherwise we get permission denied error
		etcdctl user grant-role "$clientHostNameShort" "$clientHostNameShort"
		clientArg="$clientHostNameShort:$result"
		if etcdctl put "/HOSTS/$clientHostName/test" -- "test"; then
			echo " 	Etcd put with generated credentials:  $clientArg success!" >> "/var/home/wavelet-root/logs/etcdlog.log"
			# TODO - disable when deploying to prod
			echo "	Credential generated: $clientArg" >> "/var/home/$user/logs/testCreds.log"
		else
			echo "	Etcd failure!  Please check logs."
		fi
	else
		echo "  Decrypt failed, something is wrong!" >> /var/home/wavelet-root/logs/etcdlog.log
		echo "  Cleaning up user+Roles.." >> /var/home/wavelet-root/logs/etcdlog.log
		etcdctl user del "$clientHostNameShort"
		etcdctl role del "$clientHostNameShort"
		exit 1
	fi
	# Upload credentials to etcd for client retrieval
	etcdctl put "/PROV/CRYPT" -- "$(base64 <"/var/home/wavelet-root/config/.$clientHostNameShort.enc")"
	rm -rf "/var/home/wavelet-root/config/.$clientHostNameShort.enc"
	etcdctl put "/PROV/FACTOR2" -- "${password2}"
	# Cleanup
	unset PassWord
	rm -rf "/var/home/wavelet-root/config/${clientHostName}.crypt.bin"
	# Signal client that credentials are ready
	etcdctl put "/PROV/RESPONSE" -- "${clientHostName}"
	echo "	Written: /PROV/RESPONSE -- ${clientHostName}"
	echo "  Host credentials generated and parsed back to etcd cluster, host should retrieve these credentials and proceed from here.." >> "/var/home/wavelet-root/logs/etcdlog.log"
	exit 0
}

event_generate_hash(){
        # Generate a hashID for the host
		# arg is the device type I.E enc, dec, svr etc.
		local hashType="${1}"
		echo "		Host label/pretty hostname is:	$clientHostNameShort"
		echo "		Host persistent hostname is:	$clientHostName"
		hostHash=$(cat /proc/sys/kernel/random/uuid | sha256sum | tr -d ' \t\n-')
		echo -e "		Generated host hash:	$hostHash \n"
		# Check for pre-existing keys here
		KEYNAME="/HOSTS/$clientHostName"; hashExists="$("$ETCDINTERACTIONMOD" 'read_etcd_global' $KEYNAME)"
		if [[ -z "$hashExists" || "${#hashExists}" -le 1 ]]; then
			echo "		Generated hash value lookup provides: $hashExists, which is null or less than 1 char, therefore it is not valid."
			echo "		Populating initial device type template from hostname.."
			# Populate what will initially be used as the label variable from the webUI
			case "$hashType" in
				enc*)			KEYVALUE="enc";
				;;
				dec*)			KEYVALUE="dec";
				;;
				svr*)			KEYVALUE="svr";
				;;
				*)				echo -e "		Host type is invalid, exiting."	;	exit 0
				;;
			esac
			echo "		Populating host keys.."
			# Populate host data (orchestrator takes care of UI, after initial prefix generation)
			etcdctl put "/HOSTS/$clientHostName/control/type" -- "$KEYVALUE"
			etcdctl put "/HOSTS/$clientHostName" -- "$hostHash"
			etcdctl put "/UI/HOSTS/$hostHash" -- "$clientHostName"
		else
			echo "		/HOSTS/$clientHostName Hash value exists: $hashExists"
			echo "		Device already populated, taking no further action."
		fi
}

client_provision_get_data() {
	# This is run from the client side as 1337/wavelet, from wavelet_provision_watcher.service
	# It should not launch unless wavelet_provision.sh has done hostname/domain name checking.
	# It will run with the prepopulated ETCD environment vars
    local provPW; local output; local credName; local factor2; local password2	; local password1
	if [[ "$EUID" -ne 1337 ]]; then
		echo "Please run as wavelet" >> "/var/home/${user}/logs/etcdlog.log"
		exit 0
	fi
#	echo "\nDEBUG:	ENV"
#	echo "$(env)"
	# Setup
	user="wavelet"
	mkdir -p "/var/home/wavelet/logs"
	mkdir -p "/var/home/wavelet/.ssh/secrets"
	echo "  Getting client data from previous provision request.." >> "/var/home/wavelet/logs/etcdlog.log"
	# Get response from PROV
	provPW="$(cat /var/home/wavelet/config/provisionpw | xargs)"
	# Etcd, annoyingly, likes to complain and stop working if both get populated
	# So we actually have to manually set it here, even though population of it in bash doesn't work, it still causes etcd to fail (????)
	credName="${HOSTNAME:0:7}"
	# This is a binary crypt, so we parse it directly.
	etcdctl --user PROV:$provPW get /PROV/CRYPT --print-value-only | base64 -d  > "/var/home/wavelet/config/.${credName}.enc"
	factor2="$(etcdctl --user PROV:$provPW get /PROV/FACTOR2 --print-value-only)"
	echo "$factor2" > "/var/home/wavelet/.ssh/secrets/.$credName.key"
	# Test credentials by writing and reading a test key
	password2="$(cat /var/home/wavelet/.ssh/secrets/.$credName.key)"
	# Note that the **ETCD** passwords are NOT "double-base64" translated, because they do not contain escapeChars.
	password1="$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass pass:${password2} \
		-in /var/home/wavelet/config/.${credName}.enc -d)"
	if [[ -z "$password1" ]]; then
		echo "	ERR: no password available!"
		etcdctl --user PROV:$provPW get /PROV/CRYPT --print-value-only | base64 -d  > "/var/home/wavelet/config/.${credName}.enc"
		if [[ -z $(cat "/var/home/wavelet/config/.${credName}.enc") ]]; then
			echo "	ERR: password crypt file retrieval failed.  Cannot continue."
			exit 1
		fi
	fi
	clientArg="--user $credName:$password1"
	# Test write and read
	echo -e "Running:\n	etcdctl $clientArg put /HOSTS/${HOSTNAME}/Client_test -- True"
	result="$(etcdctl $clientArg put /HOSTS/${HOSTNAME}/Client_test -- True)"
	output="$(etcdctl $clientArg get /HOSTS/${HOSTNAME}/Client_test --print-value-only)"

	if [[ "$output" == "True" ]]; then
		echo "  Client test successful!" >> "/var/home/wavelet/logs/etcdlog.log"
		# Clean up provisioning keys
		echo "  Cleaning provision keys.." >> "/var/home/wavelet/logs/etcdlog.log"
		etcdctl --user "PROV:$provPW" del "/PROV/CRYPT"
		etcdctl --user "PROV:$provPW "del "/PROV/FACTOR2"
		etcdctl --user "PROV:$provPW" del "/PROV/RESPONSE"
		echo " 	Provisioning process completed. Client ready for etcd access.." >> "/var/home/wavelet/logs/etcdlog.log"
		echo "CLIENT_PROVISION_RQ_COMPLETE=1" >> "/etc/wavelet.conf"
		exit 0
	else
		echo "  Client test unsuccessful! Please see logs." >> "/var/home/wavelet/logs/etcdlog.log"
		echo "  We got back: $output" >> "/var/home/wavelet/logs/etcdlog.log"
		exit 1
	fi
}

client_provision_request(){
	# Called from wavelet_build and runs under wavelet/1337 context in conjunction with the watcher service.
	# Responsible for requesting etcd username+roles for this client machine.
	export ETCDCTL_CACERT="/etc/ipa/ca.crt"
	export ETCDCTL_ENDPOINTS="$ETCDENDPOINT"
	local provPW="$(cat /var/home/wavelet/config/provisionpw)"
	# Our CA and endpoints are now set in bash profile.
	# Etcd, annoyingly, likes to complain and stop working if both get populated
	etcdctl --user "PROV:$provPW" put "/PROV/REQUEST" -- "$hostNameSys"
}

# Main function to handle arguments
main() {
	# Get user info
	user="$(whoami)"
	hostNameSys="$(hostname)"
	mkdir -p "/var/home/$user/logs"
	echo -e "\n**New log**" >> "/var/home/$user/logs/etcdlog.log"

	# Process command line arguments
	action="$1"
	param1="$2"
	param2="$3"
	param3="$4"

	case "$action" in
	"generate_etcd_core_roles")
		generate_etcd_core_roles
		;;
	"generate_etcd_core_users")
		generate_etcd_core_users
		;;
	"generate_etcd_host_role")
		generate_etcd_host_role
		;;
	"client_provision_get_data")
		client_provision_get_data
		;;
	"client_provision_request")
		client_provision_request
		;;
	"encrypt_pw_data")
		encrypt_pw_data "$param1" "$param2"
		;;
	"encrypt_webui_data")
		encrypt_webui_data "$param1"
		;;
	"test_auth")
		test_auth "$param1"
		;;
	*)
		echo "	Unknown action: $action"
		echo "	Available actions:"
		echo "    	generate_etcd_core_roles"
		echo "		generate_etcd_core_users"
		echo "		generate_etcd_host_role"
		echo "		client_provision_get_data"
		echo "		encrypt_pw_data <user> <password>"
		echo "		encrypt_webui_data <password>"
		echo "		test_auth <account_type>"
		exit 1
		;;
	esac
}

init_wrapper_contexts() {
	# Handles configuring /var/lib/wavelet/bin directory where all the wrapper scripts live
	# Create the wavelet group if it doesn't exist
	if ! getent group wavelet-bin >/dev/null 2>&1; then
	groupadd wavelet-bin
	echo "	Created wavelet-bin system group" >> "/root/logs/etcdlog.log"
	fi
	# Add wavelet users to the wavelet-bin group
	usermod -a -G wavelet-bin wavelet 2>/dev/null || echo "	Warning: Could not add wavelet to wavelet-bin group"  >> /root/logs/etcdlog.log
	usermod -a -G wavelet-bin wavelet-root 2>/dev/null || echo "	Warning: Could not add wavelet-root to wavelet-bin group"  >> /root/logs/etcdlog.log
	# Create base directories
	mkdir -p /var/lib/wavelet/bin/{root,wavelet-root,wavelet}
	# Set ownership and permissions
	chown root:wavelet-bin "/var/lib/wavelet/bin"
	chown root:wavelet-bin "/var/lib/wavelet/bin/root"
	chown wavelet-root:wavelet-bin "/var/lib/wavelet/bin/wavelet-root"
	chown wavelet:wavelet-bin "/var/lib/wavelet/bin/wavelet"
	# Set directory permissions: owner can read/write/execute, group can read/write/execute, others have no access
	chmod 775 "/var/lib/wavelet/bin"
	chmod 775 "/var/lib/wavelet/bin/root"
	chmod 775 "/var/lib/wavelet/bin/wavelet-root"
	chmod 775 "/var/lib/wavelet/bin/wavelet"
	# Set SELinux contexts once - files created in these directories will inherit the context
	if command -v semanage >/dev/null 2>&1; then
	# Set the file context for the directories and all files within them
	semanage fcontext -a -t bin_t "/var/lib/wavelet/bin(/.*)?" 2>/dev/null || echo "	Note: SELinux context already exists"  >> "/root/logs/etcdlog.log"
	restorecon -Rv /var/lib/wavelet/bin 2>/dev/null || echo "  Note: Could not restore SELinux contexts"  >> "/root/logs/etcdlog.log"
	echo "	SELinux contexts set for /var/lib/wavelet/bin"  >> "/root/logs/etcdlog.log"
	else
	echo "	SELinux tools not available, skipping context setup"  >> "/root/logs/etcdlog.log"
	fi

	echo "	Wavelet bin directories initialized with group permissions"  >> "/root/logs/etcdlog.log"
}

revert_server(){
	# WIP
	# Resets the server
	# This removes all the build flags,
	# destroys the etcd cluster data,
	# Regenerates all userspace secrets and reprovisions from scratch
	# Reverts the server back to a "mint" condition before the wavelet_build module performs server bootstrap.
	# Must be run as root
	systemctl stop etcd-quadlet.service
	/usr/bin/rm -rf "/var/lib/etcd-data"
	/usr/bin/rm -rf /var/home/wavelet/{server_bootstrap_completed,encoder.firstrun,reflector_clients_ip.txt}
	/usr/bin/systemctl reboot -i
}

# Execute main if script is executed directly (not sourced)
trap cleanup EXIT

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi