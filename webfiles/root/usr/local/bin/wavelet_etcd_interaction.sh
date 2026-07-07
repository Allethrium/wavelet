#!/bin/bash

# Wavelet etcd interaction.  Calls etcdctl which is installed on the base layer, detects if security layer is enabled and parses proper client certificates
# Effectively, it intercepts the etcd calls from the other modules and injects certificates as necessary

# Add our attempt at a password security solution here
ETCDSECURECREDENTIALSMOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_secure_credentials.sh" ]]; then
	source "/var/wavelet_ramfs/wavelet_secure_credentials.sh"
	ETCDSECURECREDENTIALSMOD="/var/wavelet_ramfs/wavelet_secure_credentials.sh"
else
	source "/usr/local/bin/wavelet_secure_credentials.sh"
	ETCDSECURECREDENTIALSMOD="/usr/local/bin/wavelet_secure_credentials.sh"
fi

# This script is called with args.
	# Arg 1 is action (simplified from previous version with read_etcd, read_etcd_global, write_etcd etc.)
	# Arg 2 is the input key name
	# Arg 3 is the input key value
	# Arg 4 is the print-value-only request (true if exists, false otherwise)

#   The module returns the input key/keyvalue and success if the action is modify, update, delete etc.
#   The module returns the key value if the command is 'get' as ${prinvalue}

main() {
	#echo -e "\nFunction:\nAction: ${action}\nKey Name: ${inputKeyName}\nKey Value: ${inputKeyValue}\nPrint Value Only?:${valueOnlySwitch}"
	# We need to add a separator to etcd doesn't try to process any command inputs starting with the -- delimeter as etcd flags
	set --
#	if [[ "$inputKeyValue" != "" ]]; then flagSeparator="-- "; fi
	# Here we are going to parse the entire command line, otherwise injected '' for unused variables mess with the results.
	# This may mean we get quotation marks back out during queries, which will need to be stripped by their processing modules.
	# Username / password along with other configuration options are now stored in subshell ENV
	# If they are not present before this module is run, generate_userArg is called to populate them
	# shellcheck disable=SC2086
	etcdCommand
	# Process feedback
	if  [[ "$fID" == "clearText" ]] || [[ "$fID" == "txn" ]]; then
		echo "$printvalue"
	elif [[ "$printvalue" = "OK" ]]; then
		# If we're performing a write, then we get OK back
		echo -e "		OK"
		exit 0
	elif [[ "$printvalue" = *"revision"* ]]; then
		# We're pulling other etcd data such as key revision
		echo "$printvalue"
	else
		# If we are performing a get operation, we need to decode from base64
		IFS=' '; echo "$printvalue" | base64 -d
	fi
}

etcdCommand(){
    if [[ "$fID" = "txn" ]]; then
    	echo -e "	Attempting:\n$(printf '\t\t%s\n' "$inputKeyName")" >> "/var/home/$user/logs/etcdlog.log"
    	etcdctl txn <<<"$inputKeyName"
        etcd_exit_code=$?
        if [[ "$etcd_exit_code" -ne 0 ]]; then
            echo "		Error: etcdctl command failed with code: $etcd_exit_code" >> "/var/home/$user/logs/etcdlog.log"
            exit "$etcd_exit_code"
        fi
    else
		echo -e "	Attempting:\n$(printf '\t\t%s\n' "${commandLine[*]}")" >> "/var/home/$user/logs/etcdlog.log"
		#echo -e "		DEBUG ENVIRONMENT:\n \
		#		ETCDCTL_USER		=	$ETCDCTL_USER\n \
		#		ETCDCTL_PASSWORD	=	$ETCDCTL_PASSWORD\n \
		#		ETCDCTL_ENDPOINTS	=	$ETCDCTL_ENDPOINTS\n \
		#		ETCDCTL_CACERT		=	$ETCDCTL_CACERT" >> /var/home/${user}/logs/etcdlog.log
        printvalue="$(etcdctl "${commandLine[@]}")"
        etcd_exit_code=$?
        if [[ $etcd_exit_code -ne 0 ]]; then
            echo "		Error: etcdctl command failed with code: $etcd_exit_code" >> "/var/home/$user/logs/etcdlog.log"
            exit "$etcd_exit_code"
        fi
    fi
}

generate_service() {
	# Determine user context based on current user
	local wavelet_module_path; local user_context
	case "$(id -u)" in
		0) user_context="root" ;;
		9337) user_context="wavelet-root" ;;
		1337) user_context="wavelet" ;;
		*) user_context="wavelet" ;;  # Default fallback
	esac
	echo "Parsing to systemd unit generation.."
	echo "	User Context: $user_context"
	echo "	Key Name: $key"
	echo "	Target Module: $wavelet_module"
	echo "	Arguments: $additional_arg"
	# Test and find ramdisk version if available, fallback to standard module
	if [[ -f "/var/wavelet_ramfs/${wavelet_module}.sh" ]]; then
		wavelet_module_path="/var/wavelet_ramfs/$wavelet_module.sh"
	else
		wavelet_module_path="/usr/local/bin/$wavelet_module.sh"
	fi
	echo "	Module Path: $wavelet_module_path"
	generate_secure_systemd_service \
		user="$user_context" \
		serviceName="${wavelet_module,,}" \
		key="$key" \
		modulePath="$wavelet_module_path" \
		additionalArg="$additional_arg"
	echo "  Systemd service generated:	${wavelet_module,,}.service"
	echo "  Remember to run 'systemctl --user daemon-reload'"
}

cleanup_etcd_credentials() {
    unset ETCD_USER
    unset ETCD_EXTRA_ARGS
    unset ETCD_ENDPOINTS
    unset ETCD_CERT_FILE
    unset ETCD_KEY_FILE
    unset ETCD_CA_FILE
}

set_userArg() {
  local current_user_context
  case "$(id -u)" in
	0) current_user_context="root" ;;
	9337) current_user_context="wavelet-root" ;;
	1337) current_user_context="wavelet" ;;
	*) current_user_context="wavelet" ;;
  esac
  if [[ -n $extraargs ]]; then
	  additionalArg="$extraargs"
  fi
	generate_etcd_userarg "user=$current_user_context" "extraargs=$additionalArg"
	# generate_etcd_userarg in wavelet_secure_credentials should now have exported appropriate etcd ENV.
  if [[ -z "$ETCDCTL_PASSWORD" ]]; then
	echo "  Failed to get secure etcd credentials for $current_user_context on host: $hostNameSys" \
	  >> "/var/home/${user}/logs/etcdlog.log"
	exit 1
  fi
  ETCDCTL_ENDPOINTS="https://$(cat /var/home/wavelet/config/serverhostname.txt):2379"
  ETCDCTL_CACERT="/etc/ipa/ca.crt"
  export ETCDCTL_ENDPOINTS; export ETCDCTL_CACERT
  echo "  Running in user context: ${current_user_context}" >> "/var/home/${user}/logs/etcdlog.log"
}


#####
#
#  Main
#
#####


# Clean up credentials on any exit.
trap cleanup_etcd_credentials EXIT

for arg in "$@"; do
	if [[ "$arg" == extraargs=* ]]; then
		extraargs="${arg#extraargs=}"
	fi
done

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
user="$(whoami)"
hostNameSys="$(hostname)"
mkdir -p /var/home/"${user}"/logs
echo -e "\n**New log**" >> /var/home/"${user}"/logs/etcdlog.log
fID=""
# Validate required environment variables
if [ -z "${ETCDCTL_ENDPOINTS:-}" ] || \
   [ -z "${ETCDCTL_CACERT:-}" ] || \
   [ -z "${ETCDCTL_USER:-}" ] || \
   [ -z "${ETCDCTL_PASSWORD:-}" ]; then
	#echo "etcd vars not populated, setting userargs.." >&2
	set_userArg
fi

case "$action" in
	# Read an etcd value stored under a hostname - note the preceding / 
	# Etcd does not have a hierarchical structure so we're 'simulating' directories by adding the /
	# This reads only the device LOCAL key in /HOSTS/hostname - it won't read the UI keys, you need to use Global for that.
	# non-global reads/writes assume base64 encoded content.
	read_etcd)
		declare -A commandLine=([3]="get" [2]="/HOSTS/$hostNameSys/$inputKeyName" [1]="--print-value-only");
		;;
	# Read an etcd value set globally - may still be hostname but would be defined in inputKeyName
	read_etcd_global)
		declare -A commandLine=([3]="get" [2]="$inputKeyName" [1]="--print-value-only"); fID="clearText";
		;;
	# Read a set of etcd values by prefix.  I.E a list of IP addresses
	read_etcd_prefix)
		declare -A commandLine=([3]="get" [2]="/HOSTS/$hostNameSys/$inputKeyName" [1]="--prefix" [0]="--print-value-only");
		;;
	# For global keys, values only
	read_etcd_prefix_global)
		declare -A commandLine=([3]="get" [2]="$inputKeyName" [1]="--prefix" [0]="--print-value-only"); fID="clearText";
		;;
	# For global keys + values, returned in a list I.E key-value-key-value, IFS is newline (\n)
	read_etcd_prefix_list)
		declare -A commandLine=([3]="get" [2]="$inputKeyName" [1]="--prefix"); fID="clearText";
		;;
	# For global keys ONLY, returned in a list, IFS is newline (\n)
	read_etcd_prefix_keys)
		declare -A commandLine=([3]="get" [2]="$inputKeyName" [1]="--prefix" [0]="--keys-only=true"); fID="clearText";
		;;
	# For global values ONLY, returned as a list, IFS is newline (\n)
	read_etcd_prefix_values)
		declare -A commandLine=([3]="get" [2]="$inputKeyName" [1]="--prefix" [0]="--print-value-only"); fID="clearText";
		;;
	read_etcd_json_revision)
		declare -A commandLine=([3]="$inputKeyName" [2]="get -w json");
		;;
	read_etcd_revisionID)
		declare -A commandLine=([2]="get" [1]="$inputKeyName" [0]="--rev=$revisionID");
		;;
	# Write an etcd value under a hostname.  Keys here are base64
	# Note -w 0 to disable base64 line wrapping, or we get a newline \n after every 76 chars.
	write_etcd)
		inputKeyValue=$(echo "$inputKeyValue" | base64 -w 0); declare -A commandLine=([3]="put" [2]="/HOSTS/$hostNameSys/$inputKeyName" [1]="--" [0]="$inputKeyValue");
		;;
	# Write a global etcd value where the key is root and not considered "under" a host.  Keys here are clear text.
	write_etcd_global)
		declare -A commandLine=([3]="put" [2]="$inputKeyName" [1]="--" [0]="$inputKeyValue");
		;;
	# Writes a transaction based on the existence of the first input key, with all subsequent keys being writes with special char delimiters
	write_etcd_txn)
		fID="txn"
		;;
	# returns value list of IP Addresses, special case to parse directly to command (used for read_etcd_clients and the sed variant)
	read_etcd_clients*)
		declare -A commandLine=([3]="get" [2]="--prefix" [1]="/HOSTS/$hostNameSys/DECODER_SUB_LIST" [0]="--print-value-only"); fID="clearText";
		;;
	# Delete a key
	delete_etcd_key)
		declare -A commandLine=([1]="del" [0]="/HOSTS/$hostNameSys/$inputKeyName"); fID="clearText";
		;;
	# Delete a global key (must define full key prefix)
	delete_etcd_key_global)
		declare -A commandLine=([3]="del" [2]="$inputKeyName"); fID="clearText";
		;;
	# Delete a global key (must define full key prefix)
	delete_etcd_prefix_global)
		declare -A commandLine=([3]="del" [2]="$inputKeyName" [1]="--prefix"); fID="clearText";
		;;
	# Generate a systemd service for watching an etcd key
	generate_service)
		for arg in "$@"; do
			case "$arg" in
				-key=*)
					key="${arg#*=}";;
				-module=*)
					wavelet_module="${arg#*=}" ;;
				-additional=*)
					additional_arg="${arg#*=}" ;;
			esac
		done
		generate_service
		# Do not continue to main, and exit here.
		exit 0
		;;
	# Check cluster status and access by writing a key, should return "OK"
	check_status)
		declare -A commandLine=([3]="put" [2]="/HOSTS/$hostNameSys/STATUSCHECK" [1]="--" [0]="1"); fID="clearText";
		;;
	# Call management functions - these are now handled by wavelet_etcd_management.sh
	generate_etcd_host_role|client_provision_get_data|encrypt_pw_data|encrypt_webui_data|test_auth)
		echo "  This function has been moved to wavelet_etcd_management.sh. Please use that script instead."
		echo "  Example: /usr/local/bin/wavelet_etcd_management.sh $action $inputKeyName $inputKeyValue"
		exit 1
		;;
	# Default case for unrecognized actions
	*)
		echo "  Unrecognized action: $action"; exit 1;
		;;
esac

main