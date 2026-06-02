#!/bin/bash

# monitors directory for .crt file creation or modification and copies the certificate out to wavelet
mkdir -p /root/logs
exec >/root/logs/certfilter.log 2>&1

# Source directories (FreeIPA/certmonger managed)
SRC_CERTS="/etc/pki/tls/certs"
SRC_PRIVATE="/etc/pki/tls/private"

FILES=("httpd.crt:httpd.key"
	"radius.pem:radius.key"
	"radsec.crt:radsec.key"
	"client*.crt:client*.key"
	"provision.crt:provision.key"
)

while true; do
	while IFS= read -r event; do
		# We react only to created files, we don't do anything on deletion or even modification.
		filename=$(basename "$event")
		for pair in "${FILES[@]}"; do
			certfile="${pair%:*}"
			keyfile="${pair#*:}"
			case $certfile in
				# Set detination directory appropriately based off certificate filenames
				rad*)		DEST="/var/home/wavelet-root/config/raddb/certs" # Radius server certs + RADSEC certs
				;;
				httpd*)		DEST="/var/home/wavelet/http-php/certs" # TLS certificate for all HTTPS functions (Registry, nginx, apache)
				;;
				client*)	DEST="/var/home/wavelet-root/config/raddb/certs" # This may only be needed if we do mutual auth
				;;
				provision*)	DEST="/var/home/wavelet/http/ignition" # Ignition provision certificate for client host enrollment
				;;
				*)			continue # Files which do not match should remain root-only
				;;
			esac
			if [[ "$filename" == "$certfile" || "$filename" == "$keyfile" ]]; then
				if [[ "$filename" == *".key" ]]; then
					src_dir="$SRC_PRIVATE"
				else
					src_dir="$SRC_CERTS"
				fi
				echo "	Copy modified $src_dir/$filename to $DEST"
				echo -e "	WAVELET TRIGGER CERTIFICATE UPDATE: $filename TO $DEST" | systemd-cat --identifier=certificate_filter --priority=5
				# mkdir if not exists
				mkdir -p "$DEST"
				cat "$src_dir/$filename" > "$DEST/$filename" && chown wavelet-root "$DEST/$filename" && chmod 0600 "$DEST/$filename"
				break
			fi
		done
	done < <(inotifywait -m -e create,modify "$SRC_CERTS" "$SRC_PRIVATE" --format '%w%f')
done