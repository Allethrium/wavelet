#!/bin/bash
#
echo -e "Requesting UG runtime parameters from hostname/UG_ARGS and applying to AppImage.."
/usr/local/bin/UltraGrid.AppImage $(curl -sL http://192.168.1.32:2379/v2/keys/$(hostname)/UG_ARGS | jq ".node.value" | sed 's|["",]||g')