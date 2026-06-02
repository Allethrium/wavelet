#!/bin/bash

# Wavelet network sense script
# Due to security restrictions, this must live in /usr/share/kea/scripts/wavelet_network_sense.sh
# In Wavelet, this file is mapped from /usr/local/bin by a podman volume mount

detect_self(){
	# necessary because this script is spawned with restricted privileges, it can't call bin I.E $(hostname)
	# doing it this way isn't a problem, because once set the hostname of the server is static.
	UG_HOSTNAME="hostnamegoeshere"
	ETCDHOSTNAME="$UG_HOSTNAME"
	case "$UG_HOSTNAME" in
	svr*)	parse_input_opts
	;;
	*)	echo -e "	This device Hostname is not set appropriately for network sense, exiting \n"; exit 0
	;;
	esac
}

parse_input_opts(){
	# We need a valid lease4_address var to continue
	if [[ -n "$LEASE4_ADDRESS" ]]; then
		echo "	DHCP Lease located, continuing.."
		event_get_vars
	else
		exit 0
	fi
}

event_get_vars() {
    dhcpData="$LEASE4_ADDRESS:$LEASE4_HWADDR:$event"
    if [[ -z "$dhcpData" ]]; then
        exit 0
    fi
	# We now just use etcdctl directly.  This isn't great, but it's restricted to the one key and easier than implementing FIFO IPC.
	# Note the podman secret has a carriage return appended, which will break without the parameter expansion.
	printvalue=$(etcdctl --cacert="/etc/ipa/ca.crt" --endpoints="https://$ETCDHOSTNAME:2379" --user="DHCP:${dhcpUser%$'\n'}" get "/DHCP" --print-value-only)
	if [[ "$printvalue" == "$dhcpData" ]]; then
	    # don't write a duplicate again
	    exit 0
	fi
    etcdctl --cacert="/etc/ipa/ca.crt" --endpoints="https://$ETCDHOSTNAME:2379" --user="DHCP:${dhcpUser%$'\n'}" put "/DHCP" -- "$dhcpData"
}

main(){
	event="$1"
	detect_self
}


###
#
# Main
#
###


logName=/var/log/kea/kea_script_hook.log
exec >> "$logName" 2>&1
if [[ -f /tmp/kea-env.env ]]; then
    source /tmp/kea-env.env
else
    # we can't do anything without these env vars
    exit 0
fi

# From Kea docs https://reports.kea.isc.org/dev_guide/de/d53/libdhcp_run_script.html
# We only run on IPV4, and care only about committed leases or renewals, so other hooks should be discarded
case "$1" in
    "lease4_renew")
        main "$1"
        ;;
    "lease4_expire")
		exit 0
        ;;
    "lease4_recover")
        exit 0
        ;;
    "leases4_committed")
        main "$1"
        ;;
    "lease4_release")
        exit 0
        ;;
    "lease4_decline")
        exit 0
        ;;
    "lease6_renew")
        exit 0
        ;;
    "lease6_rebind")
        exit 0
        ;;
    "lease6_expire")
        exit 0
        ;;
    "lease6_recover")
        exit 0
        ;;
    "leases6_committed")
        exit 0
        ;;
    "lease6_release")
        exit 0
        ;;
    "lease6_decline")
        exit 0
        ;;
    "addr6_register")
        exit 0
    	;;
     *)
		exit 0
    	;;
esac