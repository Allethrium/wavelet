 #!/bin/sh
 SERVERLIST=wavelet_encoders
 ICMD='systemctl stop ultragrid-*.service'
 while read SERVERNAME
 do
    ssh -n $SERVERNAME $ICMD > $SERVERNAME_report.txt
 done < "$SERVERLIST"
