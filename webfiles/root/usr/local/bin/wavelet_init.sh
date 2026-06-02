#!/bin/bash

# This forms the basis of an init script when the Server starts.
# It runs once, sets initial values in etcd which the controller then handles appropriately.  
# This effectively starts the controller in a default state, on "best" settings


# Etcd Interaction hooks (calls wavelet_etcd_interaction.sh, which more intelligently handles security layer functions as necessary)
ETCDINTERACTIONHOOKS=""
if [[ -f "/var/wavelet_ramfs/etcd_interaction_hooks.sh" ]]; then
	source "/var/wavelet_ramfs/etcd_interaction_hooks.sh"
	ETCDINTERACTIONHOOKS="/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	source "/usr/local/bin/etcd_interaction_hooks.sh"
	ETCDINTERACTIONHOOKS="/usr/local/bin/etcd_interaction_hooks.sh"
fi

WAVELET_DETECTV4L_MOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_detectv4l.sh" ]]; then
	WAVELET_DETECTV4L_MOD="/var/wavelet_ramfs/wavelet_detectv4l.sh"
else
	WAVELET_DETECTV4L_MOD="/usr/local/bin/wavelet_detectv4l.sh"
fi


event_setKeys(){
	echo "	Populating standard values into etcd."
	echo "	The last step will trigger the Controller and Reflector functions, bringing the system up."
	# Init shouldn't be started before /UI/HOSTS/$hostHash has been populated, therefore mod revisions will be > 0
	KEYDATA="mod(\"/UI/HOSTS/$hostHash\") > \"0\"

put uv_videoport \"5004\"
put uv_audiooport \"5006\"
put /UI/HOSTS/$hostHash/control/blankStatus \"0\"
put /UI/HOSTS/$hostHash/control/resetStatus \"0\"
put /UI/HOSTS/$hostHash/control/revealStatus \"0\"
put /UI/HOSTS/$hostHash/control/rebootStatus \"0\"
put /UI/HOSTS/$hostHash/control/healthStatus \"0\"
put /UI/GROUPS/$groupHash/control/activeCodec \"libaom-av1\"
put /UI/GROUPS/$groupHash/control/sourceHash \"1\"
put /UI/GROUPS/$groupHash/control/staticImage \"https://$hostNameSys/images/init_staticImage.mp4\"

put uv_videoport \"5004\"
put uv_audiooport \"5006\"
put /UI/HOSTS/$hostHash/control/blankStatus \"0\"
put /UI/HOSTS/$hostHash/control/resetStatus \"0\"
put /UI/HOSTS/$hostHash/control/revealStatus \"0\"
put /UI/HOSTS/$hostHash/control/rebootStatus \"0\"
put /UI/HOSTS/$hostHash/control/healthStatus \"0\"
put /UI/GROUPS/$groupHash/control/activeCodec \"libaom-av1\"
put /UI/GROUPS/$groupHash/control/sourceHash \"1\"
put /UI/GROUPS/$groupHash/control/staticImage \"https://$hostNameSys/images/init_staticImage.mp4\"

"
	write_etcd_txn "$KEYDATA"
}

event_init_staticImage(){
	# Initialize wavelet, setting the local static image option.
	rm -rf /var/home/wavelet/config/staticImage.mp4
	staticImageFile="/var/home/wavelet/config/image.png"
	mkdir -p /var/home/wavelet/http-php/html/images
	# Generate an image
	if [[ ! -f /var/home/wavelet/config/staticImage.mp4 ]]; then
		# Write staticImage to the group/control/staticImage key so that it's available to init client hosts.
		echo "    No static image found, generating a basic default.."
		rm -rf "/var/home/wavelet/http-php/html/images/init_staticImage.mp4"
		ffmpeg \
			-fflags +genpts -loop 1 -i "$staticImageFile" \
			-t 10 -c:v mjpeg -q:v 0 "/var/home/wavelet/http-php/html/images/init_staticImage.mp4"
		rm -rf "/var/home/wavelet/config/staticImage.mp4"
    	cp -f "/var/home/wavelet/http-php/html/images/init_staticImage.mp4" "/var/home/wavelet/config/staticImage.mp4"
    	tries=0
    	check_filesize
    	staticImageCheckSum="$(sha256sum /var/home/wavelet/config/staticImage.mp4 | cut -d' ' -f1)"
    	echo "$staticImageCheckSum" > /var/home/wavelet/http-php/html/images/init_staticImage.sha256
	fi
	cd /var/home/wavelet/ || return
}

check_filesize(){
	while [[ $tries -lt 4 ]]; do
		if [[ ! -s "/var/home/wavelet/config/staticImage.mp4" ]]; then
			echo "Error: Generated static image file is empty"
			cp -f "/var/home/wavelet/http-php/html/images/init_staticImage.mp4" "/var/home/wavelet/config/staticImage.mp4"
			(( tries++ ))
		else
			break
		fi
	done

	if [[ $tries -ge 5 ]]; then
		echo "  Attempts to generate viable initial static image exceeded!"
		exit 1
	fi
}


#####
#
# Main
#
#####


start_timer
trap 'stop_timer "$timer_id_out"; echo "Total: ${timer_duration}s" >&2' EXIT

exec >/var/home/wavelet/logs/initialize.log 2>&1
hostNameSys="$(hostname)"
printvalue=""

echo -e " Etcd cluster is up and responding, continuing.."
exec > /var/home/wavelet/logs/initialize.log 2>&1

# Populate available devices
WAVELET_DETECTV4L_MOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_detectv4l.sh" ]]; then
	WAVELET_DETECTV4L_MOD="/var/wavelet_ramfs/etcd_interaction_hooks.sh"
else
	WAVELET_DETECTV4L_MOD="/usr/local/bin/wavelet_detectv4l.sh"
fi

ETCDINTERACTIONMOD=""
if [[ -f "/var/wavelet_ramfs/wavelet_etcd_interaction.sh" ]]; then
	ETCDINTERACTIONMOD="/var/wavelet_ramfs/wavelet_etcd_interaction.sh"
else
	ETCDINTERACTIONMOD="/usr/local/bin/wavelet_etcd_interaction.sh"
fi

# Wait until etcd cluster is up
until result=$("$ETCDINTERACTIONMOD" "check_status"); do
	if [[ $? -ne 0 ]]; then
		echo "Command failed!"
	fi
	echo "$result"
	if [[ $result != "OK" ]]; then
		echo -e "Etcd still down.. looping until it is available"
		sleep .1
	else
		break
	fi
done

"$WAVELET_DETECTV4L_MOD" "redetect"

KEYNAME="/GROUPS/$hostNameSys"; read_etcd_global; groupHash="$printvalue"
KEYNAME="/HOSTS/$hostNameSys"; read_etcd_global; hostHash="$printvalue"
KEYNAME="/UI/GROUPS/$groupHash/control/persistInput"; read_etcd_global
until systemctl is-active --user wavelet_client_controller.service; do
	sleep .1
done
if [[ "$printvalue" == "1" ]]; then
	# This will trigger a source update refresh, so if we were the encoder, we will start our process.
	# Otherwise, nothing should have been affected.
	touch /var/home/wavelet/config/inputPersist.flag
	KEYNAME="/UI/GROUPS/$groupHash/control/sourceHash"; read_etcd_global
	if [[ -n "$printvalue" ]]; then
		echo "    Input persistence is enabled, ensuring sourceHash is reset to: $printvalue"
		KEYVALUE="$printvalue"; write_etcd_global
	else
		echo "	No group sourceHash available!, falling back to static image!"
		event_setKeys
	fi
else
	echo "    Input persistence is not enabled, starting with the static image input.."
	rm /var/home/wavelet/config/inputPersist.flag
	event_init_staticImage
	event_setKeys
fi