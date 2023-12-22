#!/bin/bash
# This module runs off all decoders, and monitors the output of the UltraGrid service.
# If five consecutive error messages pop up, I am planning for this module to case them
# It will then generate an error image and display that instead, or it will restart UltraGrid.AppImage.service
# may build in additional troubleshooting in the future.

tail -fn0 logfile | \
while read line ; do
        echo "$line" | grep "pattern"
        if [ $? = 0 ]
        then
                ... do something ...
        fi
done

