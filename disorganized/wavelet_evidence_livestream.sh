 #!/bin/sh
 SERVERLIST=wavelet_evidence
 ICMD='systemctl start ultragrid-usbcam-livestream.service'
 while read SERVERNAME
 do
    ssh -n $SERVERNAME $ICMD > $SERVERNAME_report.txt
 done < "$SERVERLIST"
