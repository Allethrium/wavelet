#May need some udev rule to make sure it always maps to the right input device
#!/bin/bash

# write some logic here to query DHCPD for dynamic hostname-based encoder/decoder
#
# naming convention encoders
# enc$-crt$part$-room$-location$.wavelet.local
#
# naming convention decoders
# dec$-crt$part$-room$-location$.wavelet.local
#
# other categories
#
# recorder-
# livestream-
#
#
#pinghost() {
# if ping -c 1 -W 1 "$hostname_or_ip_address"; then
#  echo "$hostname_or_ip_address is alive"
#else
#  echo "$hostname_or_ip_address is down, removing from list"
#fi}


# Define event paramaters
event_blank="1"
event_seal="2"
event_witness="3"
event_evidence="4"
event_evidence_hdmi="5"
event_hybrid="6"
event_record="7"
event_livestream="0"

# Define event variable

# this reads in the log from the keylogger service, and tails only the last input byte
# it parses this event into a menu system and autolaunches scripts to perform tasks on the server and encoder/decoders
# properly configured user + ssh keypair sign in is required, SSH is communications channel
# polkit and systemd units must be preconfigured on encoders/decoders or the unprivileged wavelet user will be unable to manage them
# dependency software must be installed properly and on the correct versions on all application targets


# main thread, sits and waits for input, launches notification script from keylogger

main() {
wavelet_reflector && read -n 1 -p "Waiting for Event;" input & tailfrominput 
}

#executes scripts based off of input
waveletcontroller() {
case $LINE in
	#
	# 1
	#
	($event_blank) wavelet_kill_all && echo "Option One, Blank activated" && current_event="wavelet_blank" && wavelet_blank;;
	# Display a black screen on all devices
	#
	# 2
	#
	($event_seal) wavelet_kill_all && echo "Option Two, Seal activated" && current_event="wavelet_seal" && wavelet_seal;;
	# Display a static image of a court seal (find a better image!)
	#
	# 3
	#
	($event_witness) wavelet_kill_all && echo "Option Three, Witness activated" && current_event="wavelet_witness" && wavelet_witness;;
	# feed from Webcam or any kind of RTP/RTSP stream (not currently implemented)
	#
	# 4
	#
	($event_evidence) wavelet_kill_all && echo "Option Four, Document Camera activated" && current_event="wavelet_evidence" && wavelet_evidence;;
	# document camera (was script but implemented here as function)
	#
	# 5
	#
	($event_evidence_hdmi) wavelet_kill_all && echo "Option Five, HDMI Capture Input activated" && current_event="wavelet_evidence_hdmi" && wavelet_evidence_hdmi;;
	# display HDMI input from plaintiff or defendant or from other HDMI source
	#
	# 6
	#
	($event_hybrid) wavelet_kill_all && echo "Option Six, Hybrid Mode activated" && current_event="wavelet_hybrid" && wavelet_hybrid;;
	# Switch to a screen capture pulling a Teams meeting window via HDMI input.  
	# Target machine should be dual-homed to an internet capable connection, running Teams
	# The teams feed is ingested into UltraGrid for local display
	#
	# 7
	#
	($event_record) echo "Not implemented" && is_recording=false;;
#	if [ $recording = true ]; then
#		echo "Recording to archive file" && recording=true && wavelet_record_start
#	if [ $recording = false ]; then
#		($false) echo "Recording to archive file" && recording=true && wavelet_record_start;; 
	# does not kill any streams, instead copies stream and appends to a labeled MKV file (not implemented)
	#
	# 0
	#
	($event_livestream) event_livestream;;
	# starts and stops livestreaming as a toggle, then sets livestreamer variable appropriately.
esac
}



# inotify monitors logging file and executes tail -last byte on any changes, stores this in a variable, then calls waveletcontroller to do something with it

tailfrominput() {
	file=/var/tmp/keylogger.log
	#tail -F -c 1 $file | while read LINE ;do
	#watch -n 1 -t -e tail -c1 /home/labuser/Downloads/logkeys/test.log & while read LINE; do
	inotifywait -mq -e modify $file |
	while read events; do
		echo "Event discovered.."
		LINE=$(tail -c 1 $file )
		waveletcontroller "$LINE"
	done
}


# runs hd-rum-multi against the declared list of decoders
wavelet_reflector() {
     hd-rum 64M 5004 $(cat wavelet_decoders)
 }


# wavelet scripted functions
# this is where things actually happen
#
#
#
event_livestream() {
	# Livestream switches an additional dedicated livestream decoder ON, it also switches all of the standard decoder boxes to notify that livestreaming is enabled.
        if [ $livestreaming = "0" ]; then 
                echo "Option Zero, Livestream currently inactive, Livestream activating"
		SERVERLIST=wavelet_livestream
		ICMD1='systemctl --user start wavelet-livestream-decoder.service'
		ICMD2='systemctl --user start wavelet-livestream.service'
		while read SERVERNAME
			do
				ssh -n wavelet@$SERVERNAME $ICMD1 > $SERVERNAME_report.txt
			done < "$SERVERLIST"
		#Runs on the encoder, kills current streaming, replaces image file with Livestream prompt and then restarts the service.
		SERVERLIST=wavelet_encoders
		ICMD0="systemctl stop ultragrid-*.service"
		ICMD1="rm -f /home/labuser/encoder_active_watermark.pam"
		ICMD2="cp /home/labuser/livestream_watermark.pam /home/labuser/encoder_active_watermark.pam"
#		ICMD3="systemctl start ultragrid-usbcam.service"
		while read SERVERNAME
			do
				ssh -n labuser@$SERVERNAME $ICMD0 > $SERVERNAME_report.txt
				ssh -n labuser@$SERVERNAME $ICMD1 > $SERVERNAME_report.txt
				ssh -n labuser@$SERVERNAME $ICMD2 > $SERVERNAME_report.txt
#				ssh -n labuser@$SERVERNAME $ICMD3 > $SERVERNAME_report.txt
			done < "$SERVERLIST"
		livestreaming="1"
		echo "Livestreaming Activated" 
		$current_event
        else 
                echo "Option Zero, Livestream currently active, Livestream deactivating"
		# Runs on dedicated livestream box and on encoder
		wavelet_kill_livestream
#                SERVERLIST=wavelet_livestream
#                ICMD1='systemctl --user stop wavelet_start_decoder.service'
#		ICMD2='kill ffmpeg blablabla"
#                while read SERVERNAME
#                        do
#                                ssh -n wavelet@$SERVERNAME $ICMD1 > $SERVERNAME_report.txt
#			#	ssh -n wavelet@$SERVERNAME $ICMD2 > $SERVERNAME_report.txt
#                        done < "$SERVERLIST"
# 		SERVERLIST=wavelet_encoders
#		ICMD0="systemctl stop ultragrid-*.service" 
#		ICMD1="rm -f /home/labuser/encoder_active_watermark.pam"
#		ICMD2="cp /home/labuser/documentcam.pam /home/labuser/encoder_active_watermark.pam"
#		while read SERVERNAME
#                        do
#				ssh -n labuser@$SERVERNAME $ICMD0 > $SERVERNAME_report.txt
#				ssh -n labuser@$SERVERNAME $ICMD1 > $SERVERNAME_report.txt
#				ssh -n labuser@$SERVERNAME $ICMD2 > $SERVERNAME_report.txt
#                        done < "$SERVERLIST"
#		livestreaming="0"
#		echo "Livestreaming Disabled" 
#		$current_event
fi
echo $livestreaming
}



wavelet_kill_all() {
	SERVERLIST=wavelet_encoders
	ICMD='systemctl stop ultragrid-*.service'
	while read SERVERNAME
		do
			ssh -n $SERVERNAME $ICMD > $SERVERNAME_report.txt
		done < "$SERVERLIST"
}


wavelet_blank() {
        SERVERLIST=wavelet_encoders
        ICMD="systemctl start ultragrid-blank.service"
        while read SERVERNAME
                do
                        ssh -n $SERVERNAME $ICMD > $SERVERNAME_report.txt
                done < "$SERVERLIST"
}


wavelet_seal() {
	SERVERLIST=wavelet_encoders
	ICMD="systemctl start ultragrid-seal.service"
	while read SERVERNAME
		do
			ssh -n $SERVERNAME $ICMD > $SERVERNAME_report.txt
                done < "$SERVERLIST"
}


wavelet_evidence() {
	SERVERLIST=wavelet_evidence
	ICMD='systemctl start ultragrid-usbcam.service'
	while read SERVERNAME
		do
			ssh -n $SERVERNAME $ICMD > $SERVERNAME_report.txt
		done < "$SERVERLIST"
}

wavelet_evidence_hdmi() {
	SERVERLIST=wavelet_evidence
	ICMD='systemctl start ultragrid-evidence-hdmi.service'
	while read SERVERNAME
		do
			ssh -n $SERVERNAME $ICMD > $SERVERNAME_report.txt
		done < "$SERVERLIST"
}

wavelet_hybrid() {
        SERVERLIST=wavelet_evidence
        ICMD='systemctl start ultragrid-hybrid.service'
        while read SERVERNAME
	        do
	        ssh -n $SERVERNAME $ICMD > $SERVERNAME_report.txt
	done < "$SERVERLIST"
}

wavelet_kill_livestream() {
                # Runs on dedicated livestream box, attempts to kill livestream on system restart.
                # This is a security feature
                SERVERLIST=wavelet_livestream
                ICMD1='systemctl --user stop wavelet-livestream-decoder.service'
                ICMD2='systemctl --user stop wavelet-livestream.service'
                while read SERVERNAME
                        do
                               ssh -n wavelet@$SERVERNAME $ICMD1 > $SERVERNAME_report.txt
                               ssh -n wavelet@$SERVERNAME $ICMD2 > $SERVERNAME_report.txt
                        done < "$SERVERLIST"
		# Runs on encoder box, stops service, swaps watermark.
                SERVERLIST=wavelet_encoders
                ICMD0="systemctl stop ultragrid-*.service" 
                ICMD1="rm -f /home/labuser/encoder_active_watermark.pam"
                ICMD2="cp /home/labuser/documentcam.pam /home/labuser/encoder_active_watermark.pam"
                while read SERVERNAME
                        do
                                ssh -n labuser@$SERVERNAME $ICMD0 > $SERVERNAME_report.txt
                                ssh -n labuser@$SERVERNAME $ICMD1 > $SERVERNAME_report.txt
                                ssh -n labuser@$SERVERNAME $ICMD2 > $SERVERNAME_report.txt
                        done < "$SERVERLIST"
                livestreaming="0"
}

# Brings up necessary services and executes main thread
# keylogger necessary to get keystroke input from device
# I still need to write this part...
# systemctl start wavelet-keylogger.service


# execute main function
# always set livestreaming and recording to offi, kill encoder  as initial values when starting the application!
# This ensures a system reset.
wavelet_kill_all
wavelet_kill_livestream
recording=0
main 
