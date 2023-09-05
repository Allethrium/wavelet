#!/bin/bash
# Starts wavelet reflector with preprovisioned commandline params
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
KEYNAME=REFLECTOR_ARGS
command=$(etcdctl --endpoints=${ETCDENDPOINT} get "${KEYNAME}" -- "${KEYVALUE}" --print-value-only)
echo -e "Requesting UG runtime parameters from hostname/UG_ARGS and applying to AppImage..\n"
echo -e "Command line is:  ${command}"
/usr/local/bin/UltraGrid.AppImage ${command}
echo -e "Reflector started"