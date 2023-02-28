#!/bin/sh
 SERVERLIST=wavelet_hybrid
 ICMD='systemctl start ultragrid-screenshare.service'
 while read SERVERNAME
 do
    ssh -n $SERVERNAME $ICMD > $SERVERNAME_report.txt
 done < "$SERVERLIST"

