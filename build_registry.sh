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
            # Clean up only intermediate <none> images, and untag the localhost tags
            podman image prune -f >/dev/null 2>&1
            # Don't want to untag encase the script fails
            #podman untag "localhost/$imageTarget"
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
    echo -e "\n	Building container: $imageTarget"
    # Build
    if podman build -t "localhost/$imageTarget" \
        ${env:+--env "$env"} \
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
	registry_addr=$(hostname -f)
	local registry_url="$registry_addr:5000"
	podman image prune -f >/dev/null 2>&1
	podman untag "localhost/$imageTarget"
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
	cd "$waveletdir"
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
	registry_addr=$(hostname)
	# Fallback to non lo if hostname fails
	if ! ping -c 1 "$registry_addr" &>/dev/null; then
		registry_addr=$(hostname -I | awk '{print $1}')
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

read_packages_csv(){
	local csv_file="$waveletdir/rpmbuild/packages.csv"
	local packages_list=()
	# Read CSV file (skip header line)
	while IFS=',' read -r pkg_name git_url version enabled description; do
		# Skip header line and commented lines
		if [[ "$pkg_name" == "package_name" || "$pkg_name" =~ ^#.*$ || -z "$pkg_name" ]]; then
			continue
		fi
		# Only include enabled packages
		if [[ "$enabled" == "true" ]]; then
			packages_list+=("$pkg_name|$git_url|$version|$description")
			echo "Found enabled package: $pkg_name"
		else
			echo "Skipping disabled package: $pkg_name"
		fi
	done < "$csv_file"
	printf '%s\n' "${packages_list[@]}"
}

build_packages(){
	# Build RPM package inside the container build environment
	echo -e "${GREEN}Starting package build process...${NC}"
	mkdir -p "$waveletdir/rpmbuild"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
	build_container_image "rpmbuild" "Containerfile.rpmbuild"
	local packages_array=()
	mapfile -t packages_array < <(read_packages_csv)
	if [[ ${#packages_array[@]} -eq 0 ]]; then
		echo -e "${RED}No enabled packages found in CSV file${NC}"
		return 1
	fi
	echo -e "${GREEN}Found ${#packages_array[@]} enabled packages to build${NC}"
	# Build each package or specific package if provided as argument
	if [[ -n "$1" && -n "$2" ]]; then
		# Single package build mode (for manual builds)
		local pkg_name="$2"
		local git_url="$1"
		echo -e "${GREEN}Building specific package: $pkg_name from $git_url${NC}"
		build_single_package "$git_url" "$pkg_name"
	else
		# Build all enabled packages from CSV
		for package_info in "${packages_array[@]}"; do
			IFS='|' read -r pkg_name git_url version description <<< "$package_info"
			echo -e "${GREEN}Building package: $pkg_name (v$version)${NC}"
			echo -e "  Description: $description"
			build_single_package "$git_url" "$pkg_name" "$version"
		done
	fi
	setup_rpm_repository

	echo -e "${GREEN}Package building complete!${NC}"
}

build_single_package(){
	local git_url="$1"
	local pkg_name="$2"
	local version="${3:-1.0.0}"
	# Check if spec file exists
	if [[ ! -f "$waveletdir/rpmbuild/SPECS/${pkg_name}.spec" ]]; then
		echo -e "${RED}Warning: No spec file found for: $pkg_name at $waveletdir/rpmbuild/SPECS/${pkg_name}.spec${NC}"
		echo -e "Skipping $pkg_name..."
		return 1
	fi
	# Build RPM using container
	echo "Building RPM for $pkg_name (version $version)..."
	if podman run --rm \
		-e GIT="$git_url" \
		-e PKG="$pkg_name" \
		-e VER="$version" \
		-v "$waveletdir/rpmbuild/SPECS:/root/rpmbuild/SPECS:z" \
		-v "$waveletdir/rpmbuild/SOURCES:/root/rpmbuild/SOURCES:z" \
		-v "$waveletdir/rpmbuild/RPMS:/root/rpmbuild/RPMS:z" \
		-v "$waveletdir/rpmbuild/SRPMS:/root/rpmbuild/SRPMS:z" \
		-v "$waveletdir/rpmbuild/BUILD:/root/rpmbuild/BUILD:z" \
		-v "$waveletdir/rpmbuild/BUILDROOT:/root/rpmbuild/BUILDROOT:z" \
		localhost/rpmbuild:latest \
		>> "$waveletdir/logs/build_registry.log"; then
		echo -e "${GREEN}	Successfully built $pkg_name${NC}"
		return 0
	else
		echo -e "${RED}	Failed to build $pkg_name - check build_registry.log for details${NC}"
		return 1
	fi
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
build_container_layer(){
	until build_container_image "$1" "$2";do
		build_container_layer "$1" "$2"
	done
}

check_firewall_ports() {
    echo "Firewall ports needed (run as root or use ufw/firewall-cmd as user):"
    echo "  5000/tcp,udp - Registry"
    echo "  8080/tcp     - HTTPD (http)"
    echo "  8443/tcp     - HTTPD (https)"
    echo "  5355/udp     - LLMNR/DNS-SD"
}

#####
#
# Main
#
#####

waveletdir=$(pwd)
mkdir -p "$waveletdir/logs"
exec >$waveletdir/logs/build_registry.log 2>&1
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


build_container_layer "coreos_overlay_client" "Containerfile.coreos.overlay.client"
build_container_layer "coreos_overlay_server" "Containerfile.coreos.overlay.server"

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