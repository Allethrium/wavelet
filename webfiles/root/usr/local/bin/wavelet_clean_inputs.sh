#!/bin/bash
# Clears all input devices
# This is useful to get rid of any cruft in the input device prefixes.
etcdctl --endpoints=http://192.168.1.32:2379 del "interface" --prefix
etcdctl --endpoints=http://192.168.1.32:2379 del "/interface" --prefix
etcdctl --endpoints=http://192.168.1.32:2379 del "/hash" --prefix
etcdctl --endpoints=http://192.168.1.32:2379 del "/short" --prefix
etcdctl --endpoints=http://192.168.1.32:2379 del "/long" --prefix
echo -e "\nInput Device data completely cleared.  Plug a device in to begin detection of input sources from scratch.\n"
exit 0