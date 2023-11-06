#!/bin/bash
#
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
KEYNAME=REFLECTOR_ARGS
command=$(etcdctl --endpoints=${ETCDENDPOINT} get "${KEYNAME}" -- "${KEYVALUE}" --print-value-only)
echo -e "Requesting UG runtime parameters from hostname/UG_ARGS and applying to AppImage..\n"
echo -e "Command line foir video is:  ${command}"
/usr/local/bin/UltraGrid.AppImage ${command}
echo -e "Video Reflector started"
KEYNAME=AUDIO_REFLECTOR_ARGS
audio_command=$(etcdctl --endpoints=${ETCDENDPOINT} get "${KEYNAME}" -- "${KEYVALUE}" --print-value-only)
echo -e "Requesting UG runtime parameters from hostname/AUDIO_REFLECTOR_ARGS and applying to AppImage..\n"
echo -e "Command line for audio is:  ${audio_command}"
/usr/local/bin/UltraGrid.AppImage ${audio_command}
echo -e "Audio Reflector started"