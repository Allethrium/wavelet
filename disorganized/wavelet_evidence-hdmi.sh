 #!/bin/sh
 SERVERLIST=wavelet_evidence
 ICMD='systemctl start ultragrid-screenshare-secondary.service'
 while read SERVERNAME
 do
    ssh -n $SERVERNAME $ICMD > $SERVERNAME_report.txt
 done < "$SERVERLIST"
