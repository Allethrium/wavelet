#!/bin/bash
# This sets up our local wavelet server registry
# Then copies all the wavelet stuff to the registry and maintains it as a local cache so we can avoid Gb's of downloads in the lab
#

RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"

export_container_image(){
    local imageTarget="$1"
    # Get registry address
    local registry_addr
    registry_addr=$(hostname -f)
    local registry_url="$registry_addr:5000"
    echo -e "\n	Exporting $imageTarget to registry $registry_url"
    # Tag and push
    if podman tag "localhost/$imageTarget" "$registry_addr/$imageTarget:latest"; then
        if podman push --format oci --tls-verify=false "localhost/$imageTarget" "$registry_url/$imageTarget:latest"; then
            echo -e "${GREEN}		Successfully pushed $imageTarget${NC}"
            # Remove local localhost/ image to avoid doubling storage in local podman storage
            # since the registry now holds the image
            return 0
        else
            echo -e "${RED}		Failed to push $imageTarget${NC}"
            return 1
        fi
    else
        echo -e "${RED}		Failed to tag $imageTarget${NC}"
        return 1
    fi
}

build_container_image(){
    local imageTarget="$1"
    local containerFile="$2"
    local env="$3"
    # Prepare --env arguments
    local podman_env_args=()
    if [[ -n "$env" ]]; then
        for e in $env; do
            podman_env_args+=("--env" "$e")
        done
    fi
    echo -e "\n	Building container: $imageTarget"
    # Build
	#   	--security-opt label=disable \
    if podman build -t "localhost/$imageTarget" \
    	--security-opt label=disable \
    	--network=host \
        "${podman_env_args[@]}" \
        -v="$waveletdir/webfiles/root/home/wavelet/containerfiles:/mount:z" \
        -f "$waveletdir/webfiles/root/home/wavelet/containerfiles/$containerFile" \
        >> "$waveletdir/logs/build_registry_$imageTarget.log" 2>&1; then
        echo -e "$GREEN	Built $imageTarget successfully${NC}"
        # Export to registry
        export_container_image "$imageTarget"
        return $?
    else
        echo -e "${RED}		Failed to build $imageTarget${NC}"
        return 1
    fi
}

pull_registry_images(){
	# Sets vars for appropriate package sources and places them in the wavelet server's local registry
	# In my lab environment, i setup a local registry that updates and tags everything with a cronjob
	# The process saves bandwidth and having to download gbs of container images every test
	# this could be adapted to an enterprise registry for scale deployments
	local registry_addr
	registry_addr="$(hostname -f)"
	local registry_url="$registry_addr:5000"
	podman image prune -f >/dev/null 2>&1
#	podman untag "localhost/$imageTarget"
	sourceList=()
  	sourceList+=("quay.io/coreos/etcd:v3.6.4")
	sourceList+=("quay.io/coreos/coreos-installer:release")
	sourceList+=("registry.fedoraproject.org/fedora:latest")
	sourceList+=("registry.fedoraproject.org/fedora:42") # needed to avoid RADIUSD bug
	sourceList+=("docker.io/library/nginx:alpine")
	sourceList+=("docker.io/library/php:fpm")
	sourceList+=("docker.io/redis:latest")
	sourceList+=("docker.io/library/httpd")
	sourceList+=("docker.io/library/registry")
	sourceList+=("quay.io/freeipa/freeipa-server:almalinux-10")
	# Work through our container image list, pull and tag to wavelet server registry
	for source in "${sourceList[@]}"; do
		sourceShort="${source##*/}"
		echo "	Processing container base image: ${source%%:*}"
		podman pull "$source" >> "$waveletdir/logs/build_registry.log"
		podman tag "$sourceShort" "localhost/${sourceShort%%:*}" >> "$waveletdir/logs/build_registry.log"
		echo "	Pushing tagged image localhost/${sourceShort%%:*} to LAN registry.."
		export_container_image "${sourceShort%%:*}"
	done
}

configure_httpd(){
  # Spins up an HTTPD server which will provide the coreos images
	echo -e "Generating Apache Podman container and systemd service file"
	mkdir -p ~/.config/var/www
	mkdir -p ~/.config/var/lib/httpd
	cat > ~/.config/var/lib/httpd/httpd.conf << EOF
# minimized apache server config for local cache server
ServerRoot "/usr/local/apache2"
Listen 8080
LoadModule mpm_event_module modules/mod_mpm_event.so
LoadModule authn_file_module modules/mod_authn_file.so
LoadModule authn_core_module modules/mod_authn_core.so
LoadModule authz_host_module modules/mod_authz_host.so
LoadModule authz_groupfile_module modules/mod_authz_groupfile.so
LoadModule authz_user_module modules/mod_authz_user.so
LoadModule authz_core_module modules/mod_authz_core.so
LoadModule access_compat_module modules/mod_access_compat.so
LoadModule auth_basic_module modules/mod_auth_basic.so
LoadModule cache_module modules/mod_cache.so
LoadModule cache_disk_module modules/mod_cache_disk.so
LoadModule cache_socache_module modules/mod_cache_socache.so
LoadModule socache_shmcb_module modules/mod_socache_shmcb.so
LoadModule reqtimeout_module modules/mod_reqtimeout.so
LoadModule filter_module modules/mod_filter.so
LoadModule mime_module modules/mod_mime.so
LoadModule log_config_module modules/mod_log_config.so
LoadModule env_module modules/mod_env.so
LoadModule headers_module modules/mod_headers.so
LoadModule setenvif_module modules/mod_setenvif.so
LoadModule version_module modules/mod_version.so
LoadModule ssl_module modules/mod_ssl.so
LoadModule http2_module modules/mod_http2.so
LoadModule unixd_module modules/mod_unixd.so
LoadModule status_module modules/mod_status.so
LoadModule autoindex_module modules/mod_autoindex.so
LoadModule dir_module modules/mod_dir.so
LoadModule alias_module modules/mod_alias.so
LoadModule rewrite_module modules/mod_rewrite.so

<IfModule unixd_module>
User www-data
Group www-data
</IfModule>

ServerAdmin you@example.com
ServerName localhost

Protocols h2c http/1.1
H2Upgrade on
H2Push on
H2PushPriority * after
<IfModule mpm_event_module>
    StartServers             3
    MinSpareThreads         25
    MaxSpareThreads         75
    ThreadsPerChild         25
    MaxRequestWorkers      150
    MaxConnectionsPerChild   0
</IfModule>

<IfModule cache_module>
    CacheIgnoreNoLastMod On
    CacheDirLevels       2
    CacheDirLength       2
</IfModule>

<Directory />
    AllowOverride none
    Require all denied
</Directory>

DocumentRoot "/usr/local/apache2/htdocs"
<Directory "/usr/local/apache2/htdocs">
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

<IfModule dir_module>
    DirectoryIndex index.html
</IfModule>

<Files ".ht*">
    Require all denied
</Files>
ErrorLog /proc/self/fd/2
LogLevel warn

<IfModule log_config_module>
    LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined
    LogFormat "%h %l %u %t \"%r\" %>s %b" common
    <IfModule logio_module>
      LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" %I %O" combinedio
    </IfModule>
    CustomLog /proc/self/fd/1 common
</IfModule>

<IfModule alias_module>
    ScriptAlias /cgi-bin/ "/usr/local/apache2/cgi-bin/"
</IfModule>

<Directory "/usr/local/apache2/cgi-bin">
    AllowOverride None
    Options None
    Require all granted
</Directory>

<IfModule headers_module>
    RequestHeader unset Proxy early
</IfModule>

<IfModule mime_module>
    TypesConfig conf/mime.types
    AddType application/x-compress .Z
    AddType application/x-gzip .gz .tgz
</IfModule>
MaxRanges unlimited
EnableMMAP on
EnableSendfile on
# Configure mod_proxy_html to understand HTML4/XHTML1
<IfModule proxy_html_module>
Include conf/extra/proxy-html.conf
</IfModule>

# Secure (SSL/TLS) connections
SSLRandomSeed startup file:/dev/urandom 512
Listen 8443 https
SSLCipherSuite HIGH:MEDIUM:!SSLv3:!kRSA
SSLProxyCipherSuite HIGH:MEDIUM:!SSLv3:!kRSA
SSLHonorCipherOrder on
SSLProtocol all -SSLv3
SSLProxyProtocol all -SSLv3
SSLPassPhraseDialog  builtin
SSLSessionCache        "shmcb:/usr/local/apache2/logs/ssl_scache(512000)"
SSLSessionCacheTimeout  300
EOF
	podman pull docker.io/library/httpd:latest
	echo -e "[Unit]
Description=HTTPD Quadlet
After=local-fs.target

[Container]
ContainerName=httpd
Image=httpd:latest
PublishPort=8080:80
PublishPort=8443:443
Network=host
Volume=%h/.config/var/www:/usr/local/apache2/htdocs:ro,z
Volume=%h/.config/var/lib/httpd/httpd.conf:/usr/local/apache2/conf/httpd.conf:ro,z
Tmpfs=/run
Tmpfs=/tmp
Exec=httpd-foreground

[Service]
Restart=always
RestartSec=5

[Install]
# Start by default on boot
WantedBy=default.target" > ~/.config/containers/systemd/httpd.container
	echo -e "\nApache Podman container generated, service has been enabled in systemd, starting service now..\n"
	# Note we don't specify a firewall zone here, but could add detection logic?
	podman pull docker.io/library/httpd:latest
	systemctl --user daemon-reload; systemctl --user restart httpd.service
	# We can use this to generate some of our wavelet files and deploy them from a local httpd server instead of internet.
	echo "Test" > ~/.config/var/www/test.txt
	sleep 2
	# Do a curl test here to ensure we have expected output
	cmd="$(curl localhost:8080/test.txt)"
	if [[ $cmd == "Test" ]]; then
		echo "Test successful, HTTPD server is running!"
	else
		echo "HTTPD server is not functional, check container and firewall settings!"
		exit 1
	fi
	cd ~/.config/var/www || exit
	# UltraGrid AppImage (continuous + version)
	echo "Downloading UltraGrid AppImages (patched Continuous, and current targeted upstream release)"
	wget -nc https://github.com/armelvil/UltraGrid/releases/download/continuous/UltraGrid-continuous-x86_64.AppImage
	wget -nc https://github.com/CESNET/UltraGrid/releases/download/v1.10.1/UltraGrid-1.10.1-x86_64.AppImage
	# CoreOS ISO files
	REGISTRY_REF="quay.io/coreos/coreos-installer:latest"
	podman run --security-opt label=disable \
		--pull=always \
		--rm \
		-v .:/data -w /data \
		"$REGISTRY_REF" download -f pxe
	cd "$waveletdir" || return
}

get_registry_reference(){
	local image_name="$1"
	local registry_addr="${REGISTRY_ADDR:-localhost}"
	# Try registry address first, fall back to localhost
	output="$(curl http://localhost:5000/v2/_catalog | jq)"
	echo -e "	Available registry images:\n$output"
	if [[ "$output" != *"coreos-installer"* ]]; then
		echo "$registry_addr:5000/$image_name"
	else
		echo "localhost:5000/$image_name"
	fi
}

get_registry_for_push(){
    local registry_addr
	# Use hostname command to get proper hostname
	registry_addr="$(hostname)"
	# Fallback to non lo if hostname fails
	if ! ping -c 1 "$registry_addr" &>/dev/null; then
		registry_addr="$(hostname -I | awk '{print $1}')"
	fi
    # Quick connectivity test
	if curl -q "http://$(hostname -f):5000/v2"; then
		echo -e "${GREEN}Registry running and responding to curl!${NC}"
		hostname -f
		return 0
	else
		echo -e "${RED}Registry not responding, restarting and trying again..${NC}"
		systemctl --user restart registry.service
		sleep 2
		configure_registry
	fi
}

build_ffmpeg_rpm(){
    local ffmpeg_dir="$waveletdir/webfiles/root/home/wavelet/containerfiles"
    local output_dir="$HOME/.config/var/www/rpms"
    local containerfile="Containerfile.build-ffmpeg-$ffmpeg_version"
    local image_name="ffmpeg-builder"
    echo -e "\n${GREEN}Building FFmpeg $ffmpeg_version RPM...${NC}"
    mkdir -p "$output_dir"
    # Build the builder image
    #         --security-opt label=disable \
    if ! podman build \
        -t "localhost/$image_name" \
        -f "$ffmpeg_dir/$containerfile" \
        "$ffmpeg_dir" \
        >> "$waveletdir/logs/build_registry_ffmpeg.log" 2>&1; then
        echo -e "${RED}Failed to build FFmpeg builder image — check build_registry_ffmpeg.log${NC}"
        return 1
    fi
    # The containerfile already copies RPMs to /output/rpms inside the image.
    # Create a container from the image, copy the /output/rpms directory to the host, then remove the container.
    local container_name="ffmpeg-builder-run"
    if ! podman create --name "$container_name" --security-opt label=disable "localhost/$image_name" >> "$waveletdir/logs/build_registry_ffmpeg.log" 2>&1; then
        echo -e "${RED}Failed to create FFmpeg builder container — check build_registry_ffmpeg.log${NC}"
        podman rmi -f "localhost/$image_name" >/dev/null 2>&1 || true
        return 1
    fi
    if ! podman cp "$container_name:/output/rpms/." "$output_dir" >> "$waveletdir/logs/build_registry_ffmpeg.log" 2>&1; then
        echo -e "${RED}Failed to copy FFmpeg RPMs from container — check build_registry_ffmpeg.log${NC}"
        podman rm -f "$container_name" >/dev/null 2>&1
        podman rmi -f "localhost/$image_name" >/dev/null 2>&1 || true
        return 1
    fi
    # Clean up the container and the builder image
    podman rm -f "$container_name" >/dev/null 2>&1
    podman rmi -f "localhost/$image_name" >/dev/null 2>&1 || true
    # List copied RPMs for verification
    echo -e "${GREEN}Copied RPMs to $output_dir:${NC}"
    ls -la "$output_dir"/*.rpm 2>/dev/null || echo "No RPMs found in $output_dir"
    echo -e "${GREEN}FFmpeg RPMs available at http://$(hostname -f):8080/rpms/${NC}"
}

setup_rpm_repository(){
	echo "Setting up RPM repository..."
	mkdir -p ~/.config/var/www/rpms
	find "$waveletdir/rpmbuild/RPMS" -name "*.rpm" -exec cp {} ~/.config/var/www/rpms \; 2>/dev/null || true
	if command -v createrepo_c &> /dev/null; then
		echo "Generating repository metadata..."
		createrepo_c ~/.config/var/www/rpms
		cat > ~/.config/var/www/rpms/wavelet-local.repo << EOF
[wavelet-local]
name=Wavelet Local Repository
baseurl=http://svr.wavelet.allethrium:8080/rpms/
enabled=1
gpgcheck=0
skip_if_unavailable=1
EOF
		echo "Repository configuration file created at ~/.config/var/www/rpms/wavelet-local.repo"
		generate_package_list
	else
		echo -e "${RED}Warning: createrepo_c not found - repository metadata not generated${NC}"
	fi
}

configure_registry(){
	# Sets up the registry
	mkdir -p "$HOME/.config/containers/systemd/registry/registry.conf.d"
 	arg="docker.io/library/registry:3"
	echo -e "[Unit]
Description=Wavelet container registry
After=network-online.target
Wants=network-online.target

[Container]
ContainerName=registry
Image=$arg
AutoUpdate=local
PublishPort=5000:5000/tcp
PublishPort=5000:5000/udp
Network=host
# Needed to supress trace error logspam
Environment=REGISTRY_LOG_LEVEL=info
Environment=OTEL_TRACES_EXPORTER=none
Volume=%h/.config/containers/systemd/registry/:/var/lib/registry/:z

[Service]
Restart=always

[Install]
WantedBy=multi-user.target" > ~/.config/containers/systemd/registry.container
 	echo -e "[[registry]]
prefix = \"*.$(dnsdomainname)\"
location = \"$ip:5000\"
insecure = true

[[registry]]
prefix = \"localhost:5000\"
location = \"$ip:5000\"
insecure = true" > ~/.config/containers/systemd/registry/registry.conf.d/01-local-registry.conf
	systemctl --user daemon-reload && systemctl --user restart registry.service
	sleep 2
	if curl -q "http://$(hostname -f):5000/v2"; then
		echo -e "${GREEN}Registry running and responding to curl!${NC}"
	else
		echo -e "${RED}Registry not responding, restarting and trying again..${NC}"
		systemctl --user restart registry.service
		sleep 2
		configure_registry
	fi
}

check_firewall_ports() {
    echo "Firewall ports needed (run as root or use ufw/firewall-cmd as user):"
    echo "  5000/tcp,udp - Registry"
    echo "  8080/tcp     - HTTPD (http)"
    echo "  8443/tcp     - HTTPD (https)"
    echo "  5355/udp     - LLMNR/DNS-SD"
}

detect_fcos_version(){
    local fcos_image="quay.io/fedora/fedora-coreos:stable"
    # Pull the image if not present
    podman pull "$fcos_image" >/dev/null 2>&1
    # Try to get the version from /etc/os-release by running a container
    local fcos_version
    fcos_version=$(podman run --rm "$fcos_image" cat /etc/os-release 2>/dev/null | grep ^VERSION_ID= | cut -d= -f2 | tr -d '"')
    # Ensure it's just the major version number (e.g., "44" from "44.20240101.3.0" or "44")
    fcos_version="${fcos_version%%.*}"
    if [[ -z "$fcos_version" || ! "$fcos_version" =~ ^[0-9]+$ ]]; then
        fcos_version="44"
    fi
    echo "$fcos_version"
}


#####
#
# Main
#
#####


waveletdir=$(pwd)
mkdir -p "$waveletdir/logs"
exec >"$waveletdir/logs/build_registry.log" 2>&1
#if [[ "$EUID" -ne 0 ]]; then
#  	echo "	This script must be run with root access"
#  	exit 1
#fi

if [[ $(hostname) == "localhost" ]]; then
	echo -e "${RED}Your machine seems to be called localhost"
	echo -e "This will result in the wavelet server being unable to contact the registry."
	echo -e "Please rename your system to something unique using hostnamectl or by editing /etc/hostname before proceding.${NC}"
fi

# shellcheck disable=SC2199
if [[ -z "${@}" ]]; then
	echo "	Wavelet registry build usage:"
	echo "	./build_registry.sh <path-to-wavelet-git> <registry-IP-address>"
	exit 1
fi

echo "  Container build and pull logs are available in the generated logfiles, in the execution dir."

if [[ "$1" == */ ]]; then
  echo "    Removing trailing / from directory arg"
  waveletdir="${1%/*}"
else
  waveletdir="$1"
fi

if [[ -n $2 ]]; then
  echo "  Setting registry IP to user definition!"
  echo "  If you have a server with multiple NICs and specified an IP, ensure you have added an entry in /etc/hosts"
  ip="$2"
else
  ip=$(hostname -I | cut -d " " -f 1)
fi

if [[ -z "$waveletdir" ]]; then
  echo "This script will not run without providing the path to the wavelet install directory!"
  exit 1
fi

configure_registry
configure_httpd
# Registry seems problematic unless restarted twice?
systemctl --user restart registry.service

# Detect FCOS version from the latest FCOS image
FCOS_VERSION=$(detect_fcos_version)

# Build the FFMPEG 7.1.4 package
# ffmpeg_version currently @ 7.1.4 until NDI compatibility/ABI issues resolved with 8.1
ffmpeg_version="7.1.4"

# Check if FFmpeg RPMs already exist to avoid needlessly rebuilding
output_dir="$HOME/.config/var/www/rpms"

echo "FCOS Version: $FCOS_VERSION"
echo "ffmpeg version: $ffmpeg_version"
if [[ -f "$output_dir/ffmpeg-$ffmpeg_version-1.fc$FCOS_VERSION.x86_64.rpm" ]] && [[ -f "$output_dir/ffmpeg-libs-$ffmpeg_version-1.fc$FCOS_VERSION.x86_64.rpm" ]]; then
    echo -e "${GREEN}FFmpeg $ffmpeg_version RPMs already exist in $output_dir, skipping build.${NC}"
else
    build_ffmpeg_rpm
fi

# Copy FFmpeg RPMs to containerfiles build context for local override
ffmpeg_rpms_dir="$waveletdir/webfiles/root/home/wavelet/containerfiles/rpms"
mkdir -p "$ffmpeg_rpms_dir"
cp "$output_dir"/ffmpeg-${ffmpeg_version}-*.fc${FCOS_VERSION}.x86_64.rpm "$ffmpeg_rpms_dir/" 2>/dev/null || true
cp "$output_dir"/ffmpeg-libs-${ffmpeg_version}-*.fc${FCOS_VERSION}.x86_64.rpm "$ffmpeg_rpms_dir/" 2>/dev/null || true

# Build the OCI container layers for the client, then utilize that as a base for the server layer.
build_container_image "coreos_overlay_client" "Containerfile.coreos.overlay.client"
build_container_image "coreos_overlay_server" "Containerfile.coreos.overlay.server"

# Build additional container images.  Many of these had to be from-scratch due to limitations in the official containers.
build_container_image "tftpd" "Containerfile.tftpd"
build_container_image "tftpboot" "Containerfile.tftpboot"
build_container_image "isc-kea" "Containerfile.isc-kea"
build_container_image "radiusd" "Containerfile.radiusd"
build_container_image "php-fpm-redis" "Containerfile.php-fpm-redis"

pull_registry_images
echo -e "${GREEN}Registry base images generated and stored in the registry on this host."
echo "Wavelet setup can be configured to utilize this registry by defining -reg=$(hostname) via install_wavelet_server.sh"
echo "This is so that the wavelet installer may download the application tarball"
check_firewall_ports