#!/bin/bash
# Called as root because DNF needs superuser privileges, so must set perms after everything is completed.
# Can still run if local dhcp is not running, however engineers will need to configure PXE appropriately for their environment
exec >/home/wavelet/local_rpm.log 2>&1
echo -e "ensuring DNSmasq is operating and available.."
systemctl enable dnsmasq.service --now

echo -e "Setting Date/Time to default inception location America/New_York.."
timedatectl set-timezone America/New_York

releasever=$(python -c 'import dnf, json; db = dnf.dnf.Base(); print("releasever=%s" % (db.conf.releasever))' | sed -e 's/releasever=//g')
echo -e "Fedora CoreOS releasever is ${releasever}\n"
export DKMS_KERNEL_VERSION=$(uname -r)
repodir="/home/wavelet/http/repo_mirror/fedora/releases/${releasever}/x86_64/"
mkdir -p ${repodir}

# Build & run containerfile
podman build -t localrpm --build-arg DKMS_KERNEL_VERSION=${DKMS_KERNEL_VERSION} -f /home/wavelet/containerfiles/Containerfile.tftpboot
podman run --privileged --security-opt label=disable -v ${repodir}:/output/ localrpm

# May not need these parts anymore
#createrepo /home/wavelet/http/repo_mirror/fedora/releases/${releasever}/x86_64/
#chown -R wavelet:wavelet /home/wavelet/
#find /home/wavelet/http -type d -exec chmod 755 {} +
touch /home/wavelet/local_rpm_setup.complete
chown wavelet:wavelet /home/wavelet/local_rpm_setup.complete
echo -e "\n
[local]
name=local repo
baseurl=file://${repodir}
enabled=1
gpgcheck=0
exit 0" > /etc/yum.repos.d/local.repo
echo -e "\n
[local]
name=local repo
baseurl=http://192.168.1.32:8080/repo/
enabled=1
gpgcheck=0" > /home/wavelet/https/repo/local.repo
echo -e "Repository generated for both local and http clients, continuing installation procedure.."