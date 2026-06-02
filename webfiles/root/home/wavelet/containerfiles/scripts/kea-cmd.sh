#!/bin/bash
# For use in kea container

# Export the container environment.
# This insecure step is necessary because kea will not parse any environment vars from the parent env to a child process
export ETCDHOSTNAME="$ETCDHOSTNAME"
export dhcpUser="$dhcpUser"
cat > /tmp/kea-env.env <<EOF
ETCDHOSTNAME="$ETCDHOSTNAME"
dhcpUser="$dhcpUser"
EOF

# Start Kea DDNS in background & DHCP server in foreground
# Both are set in conf files to log to /var/log/kea/$.log
/usr/sbin/kea-dhcp4 -c /etc/kea/kea-dhcp4.conf &
/usr/sbin/kea-dhcp-ddns -c /etc/kea/kea-dhcp-ddns.conf