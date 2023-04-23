#!/bin/bash
set -x
echo "Udev sorter invoked by USB activity, waiting 2 seconds and calling sorter.."
sleep .5
/home/wavelet/detectv4l.sh &
