#!/bin/bash

# Wavelet HOST Janitor service, called from a systemd unit/timer combination setup by the reflector service.
# It runs a short foreach loop pinging every IP in the reflector clients list, best of three attempts of three pings each.
# Then removes them from the reflector subscription list if dead.

# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
read_etcd(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd" ${KEYNAME})
	echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)\n"
}
read_etcd_global(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_global" "${KEYNAME}") 
	echo -e "Key Name {$KEYNAME} read from etcd for Global Value $printvalue\n"
}
read_etcd_prefix(){
	printvalue=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_prefix" "${KEYNAME}")
	echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)\n"
}
read_etcd_clients_ip() {
	return_etcd_clients_ip=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_clients_ip")
}
read_etcd_clients_ip_sed() {
	# We need this to manage the \n that is returned from etcd.
	# the above is useful for generating the reference text file but this parses through sed to string everything into a string with no newlines.
	processed_clients_ip=$(/usr/local/bin/wavelet_etcd_interaction.sh "read_etcd_clients_ip" | sed ':a;N;$!ba;s/\n/ /g')
}
write_etcd(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name ${KEYNAME} set to ${KEYVALUE} under /$(hostname)/\n"
}
write_etcd_global(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_global" "${KEYNAME}" "${KEYVALUE}"
	echo -e "Key Name ${KEYNAME} set to ${KEYVALUE} for Global value\n"
}
write_etcd_client_ip(){
	/usr/local/bin/wavelet_etcd_interaction.sh "write_etcd_client_ip" "${KEYNAME}" "${KEYVALUE}"
}
delete_etcd_key(){
	/usr/local/bin/wavelet_etcd_interaction.sh "delete_etcd_key" "${KEYNAME}"
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
		KEYNAME="/decoderip/"; read_etcd_prefix
		deletevalue=$(${printvalue} | grep -i -B 1 "${i}" | sed 's/192.168.1.*//g' | sed 's/--//g' | sed '/^[[:space:]]*$/d')
		echo -e "Found ${deletevalue}"
		deleteArr=(${deletevalue})
		for i in ${deleteArr[@]}; do
			dosomething=$(delete_etcd_key ${i})
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
