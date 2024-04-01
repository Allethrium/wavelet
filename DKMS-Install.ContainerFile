# Needs to be set to the Fedora version on CoreOS stable stream, as it is our base image.
# In a script, you can set this using:
#   BUILDER_VERSION=$(curl -s "https://builds.coreos.fedoraproject.org/streams/stable.json" | jq -r '.architectures.x86_64.artifacts.metal.release' | cut -d '.' -f 1)
ARG BUILDER_VERSION=39

# Run with the following command:
# podman build -f blackmagic-dtv-install.Containerfile
# Builds, downloads DKMS module (have to host blackmagic driver on another host as the official source doesn't provide a proper DL link)
# Then applies generated packages to another OStree overlay
# should be run every time a new kernel is installed!

# Get the host system kernel version
FROM quay.io/fedora/fedora-coreos:stable as kernel-query
RUN rpm -qa kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' > /kernel-version.txt

# Generate the builder container:
FROM registry.fedoraproject.org/fedora:${BUILDER_VERSION} as builder
ARG BUILDER_VERSION
COPY --from=kernel-query /kernel-version.txt /kernel-version.txt
WORKDIR /etc/yum.repos.d
RUN curl -L -O https://src.fedoraproject.org/rpms/fedora-repos/raw/f${BUILDER_VERSION}/f/fedora-updates-archive.repo && \
	sed -i 's/enabled=AUTO_VALUE/enabled=true/' fedora-updates-archive.repo
RUN dnf install -y jq dkms gcc make wget
RUN dnf install-y kernel kernel-core kernel-modules kernel-devel kernel-headers

# Download the BM desktopvideo DKMS package:
RUN     wget https://andymelville.net/wavelet/desktopvideo-12.8a19.x86_64.rpm
RUN 	dnf install -y desktopvideo-*.rpm

# At this point we need to 'clean up' the container and remove "too many levels of symbolic links" generator.
# So we need to determine what's necessary for only the AKMOD/KMOD

# create overlay container and apply to base image
FROM quay.io/fedora/fedora-coreos:stable
COPY --from=builder /* /
#RUN rpm-ostree install \
#	  /*.$(rpm -qa kernel --queryformat '%{ARCH}').rpm && \
	
	# Auto-load BlackMagic module
RUN	depmod -a "$(rpm -qa kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
	echo "desktopvideo" > /etc/modules-load.d/desktopvideo.conf && \
	# we don't want any files on /var
	rm -rf /var/lib/pcp && \
	ostree container commit 