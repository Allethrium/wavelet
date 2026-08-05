#!/bin/bash
# Unified secure credential management for Wavelet
# Handles all three user contexts and deployment scenarios
# We cannot yet use TPM encrypted systemd-creds in user contexts, see below;
# https://github.com/systemd/systemd/issues/37598

# Check if the script is being sourced or executed directly
# If executed directly, show usage and exit
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "	Error: This script should be sourced by other scripts, not executed directly."
    echo "	Usage: source $(basename "${0}")"
    echo "	Available functions:"
    echo "		encrypt_credential <user_context> <cred_name> <cred_value> [purpose]"
    echo "		decrypt_credential_to_memory <user_context> <cred_name>"
    echo "		generate_etcd_userarg <user_context> [hostname] <target user>"
    echo "		generate_secure_systemd_service <user_context> <service_name> <etcd_key> <script> [args]"
    echo "		cleanup_secure_storage"
    echo "		init_secure_storage <user_context>"
    exit 1
fi

# Source settings
# TODO - reduce etcd calls based on data that are available from wavelet.conf now.
source "/etc/wavelet.conf"

lookup_context(){
    local user="${1:-}"
    if [[ -z "$user" ]]; then
        return 1
    fi
    local homedir
    homedir="$(getent passwd "$user" | cut -d: -f6)"
    echo "$homedir"
}

init_secure_storage() {
    local user_context="$1"
    # Create secure runtime directories
    RUNTIME_CREDS_DIR="/run/user/$(id -u)/wavelet"
    # Use mktemp -d for secure, unpredictable temporary directory instead of predictable /dev/shm/wavelet-$$ path
    SHARED_MEMORY_DIR="$(mktemp -d -t wavelet-creds-XXXXXX)"
    mkdir -p "${RUNTIME_CREDS_DIR}" "${SHARED_MEMORY_DIR}"
    chmod 700 "${RUNTIME_CREDS_DIR}" "${SHARED_MEMORY_DIR}"
}

cleanup_secure_storage() {
  # Secure cleanup of all credential storage
  # Memory-mapped secure storage for runtime credentials
  RUNTIME_CREDS_DIR="/run/user/$(id -u)/wavelet"
  # SHARED_MEMORY_DIR is now set by init_secure_storage via mktemp -d
  if [[ -n "${SHARED_MEMORY_DIR}" && -d "${SHARED_MEMORY_DIR}" ]]; then
    find "${SHARED_MEMORY_DIR}" -type f -exec shred -vfz -n 3 {} \; 2>/dev/null
    rm -rf "${SHARED_MEMORY_DIR}"
  fi
  if [[ -d "${RUNTIME_CREDS_DIR}" ]]; then
      find "${RUNTIME_CREDS_DIR}" -type f -exec shred -vfz -n 3 {} \; 2>/dev/null
      rm -rf "${RUNTIME_CREDS_DIR}"
  fi
}

encrypt_credential() {
  # Encrypts the credential parsed in from rest of module
  local user_context="$1"; homedir="$(lookup_context "$1")"
  local credential_name="$2"
  local credential_value="$3"
#  local purpose="${4:-etcd}"
  local user_home="$homedir"
  local secrets_dir="${homedir}/.ssh/secrets"
  local config_dir="${homedir}/config"
  local log_file="${homedir}/logs/wavelet_credentials.log"
  # Ensure log directory exists
  mkdir -p "${homedir}/logs"
  echo "  Encrypting credential '${credential_name}' for ${user_context}" >> "${log_file}"
  # Create directories with proper permissions
  if [[ ! -d "${secrets_dir}" ]]; then
    echo "    Creating secrets directory: ${secrets_dir}" >> "${log_file}"
	if ! mkdir -p "$secrets_dir"; then
	  echo "    ERROR: Failed to create secrets directory" >> "${log_file}"
	  return 1
	fi
  fi
  if [[ ! -d "$config_dir" ]]; then
    echo "    Creating config directory: $config_dir" >> "${log_file}"
    if ! mkdir -p "$config_dir"; then
      echo "    ERROR: Failed to create config directory" >> "${log_file}"
      return 1
    fi
  fi
  # Generate strong encryption key using system entropy
  local encryption_key
  encryption_key="$(head -c 32 /dev/urandom | base64 -w 0 | tr -dc 'a-zA-Z0-9' | head -c 64)"
  # Store encryption key securely
  local key_file
  key_file="${secrets_dir}/.${credential_name}.key"
  echo "${encryption_key}" > "${key_file}"
  chmod 600 "${key_file}"
  # Encrypt the credential
  local cred_file="${config_dir}/.${credential_name}.enc"
  echo "${credential_value}" | openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 \
    -pass "pass:${encryption_key}" -out "${cred_file}"
  chmod 600 "${cred_file}"
  # with TPM (rootful only)
  # echo "${PassWord}" | openssl enc -e -aes-256-gcm -pbkdf2 -pass "pass:${encryption_key}" -out "test.bin"

  # Verify encryption for core user
  local test_decrypt
  test_decrypt="$(openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 \
        -pass "pass:${encryption_key}" -in "${cred_file}")"
    if [[ "$test_decrypt" == "$credential_value" ]]; then
        chmod 600 "$cred_file"
        # Set ownership based on user context
        case "$user_context" in
			"root") chown root:root "${key_file}" "${cred_file}" ;;
			"wavelet-root") chown wavelet-root:wavelet-root "${key_file}" "${cred_file}" ;;
			"wavelet") chown wavelet:wavelet "${key_file}" "${cred_file}" ;;
			# I REALLY do not like these have to be world-readable for the PHP process in the container to access them.
			# It may be better all around to copy them into the container rather than attempt volume mount.
			"webui") chown wavelet:wavelet "${key_file}" "${cred_file}"; chmod 0644 "${key_file}" "${cred_file}" ;;
        esac
        echo "    Credential: '${credential_name}' encrypted successfully for user: ${user_context}" >> "${log_file}"
        return 0
    else
        echo "    Encryption verification failed for ${credential_name}" >> "${log_file}"
        rm -f "${key_file}" "${cred_file}"
        return 1
    fi
}

decrypt_credential_to_memory() {
	# This keeps creds away from the filesystem
	local user_context; local homedir; local credential_name; local key_file; local cred_file
	user_context="$1"
	# Apparently this lookup just isn't working..
	homedir="$(lookup_context "$user_context")"
	credential_name="$2"
	#echo "			Searching for credential files for: ${credential_name}" >&2
	key_file="$homedir/.ssh/secrets/.$credential_name.key"
	cred_file="$homedir/config/.$credential_name.enc"
	if [[ ! -f "$key_file" || ! -f "$cred_file" ]]; then
		echo "			Credential files not found for $user_context" >&2
		return 1
	fi
	# Decrypt to shared memory
	init_secure_storage "$user_context"
	local memory_file="${SHARED_MEMORY_DIR}/${credential_name}"
	if openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 \
		-pass "pass:$(cat "$key_file")" -in "$cred_file" -out "$memory_file"; then
		chmod 600 "$memory_file"
		echo "$memory_file"
		return 0
	else
		echo "			Failed to decrypt $credential_name!" >&2
		return 1
	fi
}

generate_etcd_userarg() {
	local user_context
	local hostname
	# allow null in this var
	local additional_args
	local homedir
	hostNameSys="$(hostname)"
	for arg in "${@}"; do
		case "$arg" in
			user=*)
				user_context="${arg#*=}"
				;;
			hostname=*)
				hostname="${arg#*=}"
				;;
			extraargs=*)
				additional_args="${arg#*=}"
				;;
			*)
				echo "		Unknown parameter: $arg" >&2
				exit 1
				;;
		esac
	done
	homedir="$(lookup_context "$user_context")"
	#echo "    Called with user context: $user_context, hostname: $hostNameSys, and additional args: $additional_args"  >&2
	# Determine etcd user based on context and hostname
	if [[ "$hostNameSys" == *"svr"* ]]; then
		#echo "		Server host.  Checking user context.." >&2
		case "$user_context" in
			# The system root account will also use etcd-root account
			"root")
				etcd_user="root"
				;;
				# wavelet-root can be ENROLL, PROV or root, defined by additional_args
				# These will always be defined
			"wavelet-root")
				etcd_user="$additional_args"
				;;
				# The standard account when running serverside processes for etcd is "svr"
			"wavelet")
				etcd_user="svr"
				;;
				# Future feature for adding a presentation account with very limited access
				# It would be RO for the UG appImage commandline
				# Responsible for running video output without exposing a console.
			"presenter")
				etcd_user="presenter"
				;;
		esac
	else
		#echo "		Client Host.  Using client host credentials only.." >&2
		case "${user_context}" in
			# wavelet-root can be ENROLL or PROV, with credentials prepopulated by decoder.ign
			# These will always be defined as additional args
			"wavelet-root")
				etcd_user="$additional_args"
				;;
			# The standard account when running serverside processes for etcd is "svr"
			"wavelet")
				etcd_user="${hostNameSys:0:7}"
				;;
			# Future feature for adding a presentation account with very limited access
			# It would be RO for the UG appImage commandline
			# Responsible for running video output without exposing a console.
			"presenter")
				etcd_user="presenter"
				;;
		esac
	fi
	# Get password from secure storage
	#echo "		Getting credentials for user context: $user_context and ETCD credential: $etcd_user" >&2
	local password_file
	password_file="$(decrypt_credential_to_memory "$user_context" "$etcd_user")"
	if [[ -f "$password_file" ]]; then
		local password
		password="$(cat "$password_file")"
		# echo "--user ${etcd_user}:${password}"
		# Export our credentials for use in etcd
		export ETCDCTL_PASSWORD="$password"
		export ETCDCTL_USER="$etcd_user"
		# The systemd wrapper expects a UserArg var
		unset password
	else
		echo "		Failed to retrieve credentials for $etcd_user" >&2
		return 1
	fi
}

create_secure_etcd_wrapper() {
	# Additional args may specify a different etcd user
	local user_context; local homedir; local service_name; local etcd_key; local script_to_run;
	local additional_args; local user_home; local wrapper_script; local log_file
	user_context="$1"
	service_name="$2"
	etcd_key="$3"
	scriptPath="$4"
	additional_args="${5:-}"
	homedir="$(lookup_context "$user_context")"
	user_home="$homedir"
	# Ensure log directory exists
	mkdir -p "${homedir}/logs"
	log_file="${homedir}/logs/secure_creds.log"
	echo "Called with:" >> "$log_file"
	echo "	user_context = $user_context" >> "$log_file"
	echo "	homedir = $homedir" >> "$log_file"
	echo "	service_name = $service_name" >> "$log_file"
	echo "	etcd_key = $etcd_key" >> "$log_file"
	echo "	Script path = $scriptPath" >> "$log_file"
	echo "	Additional Args = $additional_args" >> "$log_file"
	echo "	user_home = $homedir" >> "$log_file"

	mkdir -p "/var/lib/wavelet/bin/$user_context"
	wrapper_script="/var/lib/wavelet/bin/${user_context}/${service_name}_wrapper.sh"
	# Update user's PATH only if not already done
	if ! grep -q 'PATH="/var/lib/wavelet/bin/'$user_context':$PATH"' "$user_home/.bashrc" 2>/dev/null; then
		echo 'export PATH="/var/lib/wavelet/bin/'$user_context':$PATH"' >> "$user_home/.bashrc"
	fi
	# Note the wrapper does NOT use the service name!
	# Note the wrapper may be retired as of systemd v258
	# We will be able to use TPM to handle things through systemd-creds
	credentialsFile=""
	if [[ -f "/var/wavelet_ramfs/wavelet_secure_credentials.sh" ]]; then
		credentialsFile="/var/wavelet_ramfs/wavelet_secure_credentials.sh"
	else
		credentialsFile="/usr/local/bin/wavelet_secure_credentials.sh"
	fi
	cat > "$wrapper_script" <<-EOF
		#!/bin/bash
		# ETCD Systemd wrapper
		set -euo pipefail
		USER_CONTEXT="$user_context"
		ETCD_KEY="$etcd_key"
		SCRIPT_TO_RUN="$scriptPath"
		ADDITIONAL_ARGS="${additional_args:-}"
		# Source the credential management functions
		source "${credentialsFile}"
		# Trap to ensure cleanup on exit
		trap 'cleanup_secure_storage' EXIT INT TERM
		# Set environment variables for etcdctl
		# This helps hide passwords from process list and systemd units
		# Note the subshell ()
		(
			generate_etcd_userarg "user=\$USER_CONTEXT" "extraargs=\$ADDITIONAL_ARGS"
			if [[ \$? -ne 0 ]]; then
				echo "Failed to generate etcd credentials" >&2
				exit 1
			fi
			export ETCDCTL_ENDPOINTS=https://${SVR_HOSTNAME}:2379
			export ETCDCTL_CACERT=/etc/ipa/ca.crt
			export ADDITIONAL_ARGS
			exec etcdctl watch \$ETCD_KEY --prefix -w simple -- /usr/bin/bash -c "\$SCRIPT_TO_RUN \$ADDITIONAL_ARGS"
		)
	EOF
	chown "${user_context}:${user_context}" "$wrapper_script"
	chmod 0700 "$wrapper_script"
	echo "  	Secure wrapper created: $wrapper_script"
}

generate_secure_systemd_service() {
	# We need to ensure we are not using the keyname for our systemD service name
	local user_context; local service_name; local etcd_key; local script_to_run; local additional_args; local log_file
	for arg in "$@"; do
		case "$arg" in
			user=*)
				user_context="${arg#*=}"
				;;
			serviceName=*)
				service_name="${arg#*=}"
				;;
			key=*)
				etcd_key="${arg#*=}"
				;;
			modulePath=*)
				script_path="${arg#*=}"
				;;
			additionalArg=*)
				additional_args="${arg#*=}"
				;;
		esac
	done
	homedir="$(lookup_context "$user_context")"
	# Ensure log directory exists
	mkdir -p "${homedir}/logs"
	log_file="${homedir}/logs/wavelet_serviceGen.log"
	# We don't want a complex etcd key as the service name
	if [[ "$service_name" == "${etcd_key,,}" ]]; then
		service_name="${script_to_run,,}"
	fi
	# Define the name of the systemd unit, matches the target script
	local service_file="${homedir}/.config/systemd/user/${service_name,,}.service"
	# Ensure systemd user directory exists
	mkdir -p "$(dirname "${service_file}")"
	if [[ "$(hostname)" == *"svr"* ]]; then
		afterBlock="After=network-online.target etcd-quadlet.service"
		wantsBlock="Wants=network-online.target etcd-quadlet.service"
	else
		afterBlock="After=network-online.target"
		wantsBlock="Wants=network-online.target"
	fi
	# Determine the script location
	# Test for ramfs file availability
	if [[ -f "/var/wavelet_ramfs/wavelet_secure_credentials.sh" ]]; then
		credentialsFile="/var/wavelet_ramfs/wavelet_secure_credentials.sh"
	else
		credentialsFile="/usr/local/bin/wavelet_secure_credentials.sh"
	fi

	echo "	Attempting to generate secure systemd service.." >> "${log_file}"
	echo "		User: $user_context" >> "${log_file}"
	echo "		Service Name: $service_name" >> "${log_file}"
	echo "		Watched Key: $etcd_key" >> "${log_file}"
	echo "		Module Name: $script_to_run" >> "${log_file}"
	echo "		Module Full Path: $script_path" >> "${log_file}"
	echo "		Additional Arguments: $additional_args" >> "${log_file}"
	create_secure_etcd_wrapper \
		"$user_context" \
		"${service_name,,}" \
		"$etcd_key" \
		"$script_path" \
		"$additional_args"
	cat > "$service_file" <<-EOF
		[Unit]
		Description=Wavelet ${service_name}
		${afterBlock}
		${wantsBlock}

		[Service]
		Type=simple
		ExecStart=/var/lib/wavelet/bin/${user_context}/${service_name}_wrapper.sh "${user_context}" "${etcd_key}" "${script_path}" "${additional_args}"
		Restart=always
		RestartSec=10s
		# Security hardening
		NoNewPrivileges=true
		PrivateTmp=true
		ProtectSystem=strict
		# ProtectHome=true
		RuntimeDirectory=${service_name}
		RuntimeDirectoryMode=0700
		# Memory protection
		MemoryDenyWriteExecute=true
		SystemCallArchitectures=native

		[Install]
		WantedBy=default.target
	EOF
  # Set proper ownership
  # This probably isn't necessary as service generation occurs only under the context in which it is run
  case "$user_context" in
    "root")         chown root:root "$service_file"
    ;;
    "wavelet-root") chown wavelet-root:wavelet-root "$service_file"
    ;;
    "wavelet")      chown wavelet:wavelet "$service_file"
    ;;
    "webui")        chown wavelet:wavelet "$service_file"
    ;;
  esac
}

# Remove command-line interface logic that runs automatically
# Instead, export the functions for use by other scripts