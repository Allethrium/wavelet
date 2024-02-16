# Needs to be set to the Fedora version on CoreOS stable stream, as it is our base image.
# In a script, you can set this using:
#   BUILDER_VERSION=$(curl -s "https://builds.coreos.fedoraproject.org/streams/stable.json" | jq -r '.architectures.x86_64.artifacts.metal.release' | cut -d '.' -f 1)
ARG BUILDER_VERSION=39

FROM quay.io/fedora/fedora-coreos:stable as kernel-query
#We can't use the `uname -r` as it will pick up the host kernel version
RUN rpm -qa kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' > /kernel-version.txt

# Using my intuition :|
FROM registry.fedoraproject.org/fedora:${BUILDER_VERSION} as builder
ARG BUILDER_VERSION
COPY --from=kernel-query /kernel-version.txt /kernel-version.txt
WORKDIR /etc/yum.repos.d
RUN curl -L -O https://src.fedoraproject.org/rpms/fedora-repos/raw/f${BUILDER_VERSION}/f/fedora-updates-archive.repo && \
	sed -i 's/enabled=AUTO_VALUE/enabled=true/' fedora-updates-archive.repo
RUN dnf install -y jq dkms gcc make wget \
	kernel-
	kernel-modules- \
	kernel-devel- \
	kernel-headers \
# Download the BM desktopvideo DKMS package:
RUN     wget https://andymelville.net/wavelet/desktopvideo-12.8a19.x86_64.rpm
WORKDIR /
RUN 	dnf install -y desktopvideo-*.rpm


# create overlay container and apply to base image
FROM quay.io/fedora/fedora-coreos:stable
COPY --from=builder /*.rpm /blackmagic
RUN rpm-ostree install \
	  /*.$(rpm -qa kernel --queryformat '%{ARCH}').rpm && \
	
	# Auto-load BlackMagic module
	depmod -a "$(rpm -qa kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')" && \
	echo "desktopvideo" > /etc/modules-load.d/desktopvideo.conf && \
	# we don't want any files on /var
	rm -rf /var/lib/pcp && \
	ostree container commit 