#!/bin/bash
# Calls etcd_interaction in order to provision a client

# Do some security checking and screening, discard if it isn't REQUEST-hostname pattern
# screen for binary data, html, regex, other possible active content and discard.

# check hostname w/ DNS
verifiedHostName=$(whatever comes out of here)
requestingClient=${verifiedHostName}
# call etcd interaction

/usr/local/bin/wavelet_etcd_interaction.sh "generate_etcd_host_role" 0 ${requestingClient}