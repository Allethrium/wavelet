#!/bin/bash

# Wavelet HOST Janitor service, called from a systemd unit/timer combination setup by the reflector service.
# It runs a short foreach loop pinging every IP in the reflector clients list, best of three attempts of three pings each.
# Then removes them from the reflector subscription list if dead.

#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
read_etcd(){
	printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get /$(hostname)/${KEYNAME})
	echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for host $(hostname)"
}

read_etcd_global(){
	printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get "${KEYNAME}")
	echo -e "Key Name {$KEYNAME} read from etcd for value ${printvalue} for Global value"
}

write_etcd(){
	etcdctl --endpoints=${ETCDENDPOINT} put "/$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
	echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}

write_etcd_global(){
	etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
	echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
}

write_etcd_clientip(){
	etcdctl --endpoints=${ETCDENDPOINT} put /decoderip/$(hostname) "${KEYVALUE}"
	echo -e "$(hostname) set to ${KEYVALUE} for Global value"
}
read_etcd_clients_ip() {
	return_etcd_clients_ip=$(etcdctl --endpoints=${ETCDENDPOINT} get "/decoderip/" --prefix --print-value-only)
}
read_etcd_clients_ip_sed() {
	# We need this to manage the \n that etcd returns, 
	# the above is useful for generating the reference text file but this is better for immediate processing.
	processed_clients_ip=$(ETCDCTL_API=3 etcdctl --endpoints=${ETCDENDPOINT} get "/decoderip/" --prefix --print-value-only | sed ':a;N;$!ba;s/\n/ /g')
}


main(){
	read_etcd_clients_ip_sed
	arr=(${processed_clients_ip})
	
	try_ping_client(){
		if ping -c 3 -i 1 ${i} &> /dev/null; then
			echo -e "${i} is healthy, moving on to next host."
			exit 0
		fi
	}

   remove_client(){
		echo -e "Ping failed three times for ${i}!  Removing host from list!\n"
		deletevalue=$(etcdctl --endpoints=${ETCDENDPOINT} get "/decoderip/" --prefix | grep -i -B 1 "${i}" | sed 's/192.168.1.*//g' | sed 's/--//g' | sed '/^[[:space:]]*$/d')
		echo -e "Found ${deletevalue}"
		deleteArr=(${deletevalue})
		for i in ${deleteArr[@]}; do
			dosomething=$(etcdctl --endpoints=${ETCDENDPOINT} del "${i}")
		done
		echo -e "Deleted ${dosomething}!"
	}

	for i in ${arr[@]}; do
		n=0
		until [[ "${n}" -ge 3 ]]; do
			try_ping_client
			echo "Ping failed on attempt ${n}, waiting three seconds to try again."
			n=$((n+1))
			sleep 1
		done
		echo "Failed host ${i}"
		remove_client ${i}
	done
}

####
#
#
# Main
#
#
####

main
