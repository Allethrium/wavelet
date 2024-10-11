FROM quay.io/fedora/fedora-bootc:40
ARG DKMS_KERNEL_VERSION
# Base packages and build tools
RUN	touch /etc/BOOTC_OVERLAY_WORKED.TXT
# clean up
RUN rm -rf /tmp/* && rm -rf /var/tmp/* && dnf clean all && \
	ostree container commit