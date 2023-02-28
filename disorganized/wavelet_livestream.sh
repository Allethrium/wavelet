#!/bin/sh
 SERVERLIST=wavelet_encoders
case $is_livestream in
	($true); ICMD='systemctl start ultragrid-livestream-client.service'
	
	($false)
	event_blank="1"
	event_seal="2"
	event_witness="3"
	event_evidence="4"
	event_evidence_hdmi="5"
	event_hybrid="6"
	event_record="7";
esac


 ICMD='systemctl start ultragrid-livestream-client.service'
 while read SERVERNAME
 do
    ssh -n $SERVERNAME $ICMD > $SERVERNAME_report.txt
 done < "$SERVERLIST"

wait 10
## run FFMPEG to commence livestream 
#
#
#
RTMP_URL="rtmp://a.rtmp.youtube.com/live2"
STREAM_KEY="youtubeapikeygoeshere"
eUTPUT=$RTMP_URL/$STREAM_KEY
ffmpeg  -i http://192.168.1.32:8554/ug.sdp/dev/video0 -c:v libx264 -preset veryfast -maxrate 3000k -bufsize 6000k -pix_fmt yuv420p -g 50 -an -f flv $OUTPUT
