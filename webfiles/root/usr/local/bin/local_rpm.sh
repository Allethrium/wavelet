#!/bin/bash
# Called as root because DNF needs superuser privileges, so must set perms after everything is completed.
# DNF running on RPM-ostree currently broken, this step will not work until it's resolved.
exec >/home/wavelet/local_rpm.log 2>&1
echo -e "ensuring DNSmasq is operating and available.."
systemctl enable dnsmasq.service --now

echo -e "Setting Date/Time to default inception location America/New_York.."
timedatectl set-timezone America/New_York

echo -e "generating a local folder in /http server directory and creating an RPM repository to serve packages locally \n"
echo -e "This will recatalog and copy all the packages currently in use on this system.  Download of about ~1Gb is required, which is the slowest operation here.\n"
echo -e "We do this so that new downloads aren't performed on every single additional device that's added."
# Added this so we don't get caught out the next time I rebase..
releasever=$(python -c 'import dnf, json; db = dnf.dnf.Base(); print("releasever=%s" % (db.conf.releasever))' | sed -e 's/releasever=//g')
echo -e "Fedora CoreOS releasever is ${releasever}\n"

# dnf downloads only installed packages
# This is a lazy way to do it - there may be unnecessary packages redownloaded here which we do not need to add.
mkdir -p /home/wavelet/http/repo_mirror/fedora/releases/${releasever}/x86_64/
#rpm --import https://yum.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB
#rpmkeys --import https://yum.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB

# We spin up a local repository to speed up imaging tasks for the clients.  It would make more sense to maintain a full local repository mirror, but I don't have the bandwidth in my lab to do this.
dnf reinstall -y --nogpgcheck --downloadonly --downloaddir=/home/wavelet/http/repo_mirror/fedora/releases/${releasever}/x86_64/ `rpm -qa`
createrepo /home/wavelet/http/repo_mirror/fedora/releases/${releasever}/x86_64/
chown -R wavelet:wavelet /home/wavelet/
find /home/wavelet/http -type d -exec chmod 755 {} +

touch /home/wavelet/local_rpm_setup.complete
chown wavelet:wavelet /home/wavelet/local_rpm_setup.complete
exit 0
