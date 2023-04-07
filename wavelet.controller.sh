#May need some udev rule to make sure it always maps to the right input device
#!/bin/bash

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
# hybrid (ug to dual-home windows PC running teams)
# 

# Define event paramaters
event_blank="1"
event_seal="2"
event_witness="3"
event_evidence="4"
event_evidence_hdmi="5"
event_hybrid="6"
event_record="7"
event_livestream="0"
event_x264="A"
event_hevc="B"
event_av1="C"

# Define standard variables for encoders
# Needs the tag attached otherwise systemd is unable to parse the variables
uv_videoport="-P 5004"
uv_audioport="-P 5006"
uv_reflector="192.168.1.32"
uv_obs="192.168.1.254"
uv_encoder="-c libavcodec:encoder=hevc_vaapi:gop=2:bitrate=20M"
uv_gop="2"
uv_bitrate="20M"

# this reads in the log from the keylogger service, and tails only the last input byte
# it parses this event into a menu system and autolaunches scripts to perform tasks on the server and encoder/decoders
# properly configured user + ssh keypair sign in is required, SSH is communications channel
# polkit and systemd units must be preconfigured on encoders/decoders or the unprivileged wavelet user will be unable to manage them
# dependency software must be installed properly and on the correct versions on all application targets


# main thread, sits and waits for input, launches notification script from keylogger

main() {
read -n 1 -p "Waiting for Event;" input & tailfrominput 
}

#executes scripts based off of input
waveletcontroller() {
case $LINE in
	#
	# 1
	#
	($event_blank) wavelet_kill_all && echo "Option One, Blank activated" && current_event="wavelet-blank" && wavelet-blank;;
	# Display a black screen on all devices
	#
	# 2
	#
	($event_seal) wavelet_kill_all && echo "Option Two, Seal activated" && current_event="wavelet-seal" && wavelet-seal;;
	# Display a static image of a court seal (find a better image!)
	#
	# 3
	#
	($event_witness) wavelet_kill_all && echo "Option Three, Witness activated" && current_event="wavelet-witness" && wavelet-witness;;
	# feed from Webcam or any kind of RTP/RTSP stream (not currently implemented)
	#
	# 4
	#
	($event_evidence) wavelet_kill_all && echo "Option Four, Document Camera activated" && current_event="wavelet-evidence" && wavelet-evidence;;
	# document camera (was script but implemented here as function)
	#
	# 5
	#
	($event_evidence_hdmi) wavelet_kill_all && echo "Option Five, HDMI Capture Input activated" && current_event="wavelet-evidence-hdmi" && wavelet-evidence-hdmi;;
	# display HDMI input from plaintiff or defendant or from other HDMI source
	#
	# 6
	#
	($event_hybrid) wavelet_kill_all && echo "Option Six, Hybrid Mode activated" && current_event="wavelet-hybrid" && wavelet-hybrid;;
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
	#
	# video codec selection
	#
	($event_x264) event_x264 && echo "x264 video codec selected, updating encoder variables";;
	($event_hevc) event_hevc && echo "hevc video codec selected, updating encoder variables";;
	($event_av1) event_av1 && echo "|*****||EXPERIMENTAL AV1 codec selected, updating encoder vaiables||****|";;
esac
}



# inotify monitors logging file and executes tail -last byte on any changes, stores this in a variable, then calls waveletcontroller to do something with it

tailfrominput() {
	file=/var/log/logkeys.log
	inotifywait -mq -e modify $file |
	while read events; do
		echo "Event discovered.."
		LINE=$(tail -c 1 $file )
		waveletcontroller "$LINE"
	done
}


# runs hd-rum-multi against the declared list of decoders
# adding a nonexistant decoder might break this, so we had to add logic to check against a valid list of predefined hostnames
# .. or i could have just explicitly set IP addresses... sigh.
wavelet_reflector() {
	rm -rf wavelet_clients
	touch wavelet_clients
	sense_hostnames=(edge2 dec0 dec1 dec2 dec3 dec4 dec5 dec6 dec7 livestream teamshybrid badhostname audiodec0 audiocodec1 audiocodec2 audiocodec3)
	for i in "${sense_hostnames[@]}";
	do
		host -W 0 $i | awk '/has address/ { print $4 }'
	done > wavelet_clients
	hd-rum 8M 5004 `cat wavelet_clients` & 
	hd-rum 1M 5006 `cat wavelet_clients` &
}



# wavelet scripted functions
# this is where things actually happen
#
#
#
#
assemble_systemd() {
                rm -rf $envfile
                echo -e "filter=$filter" > $envfile
		echo -e "input=$input" >> $envfile
		echo -e "port=$uv_videoport" >> $envfile
		echo -e "dest=$uv_reflector" >> $envfile
		echo -e "encoder=$uv_encoder" >> $envfile
#		echo -e "gop=$uv_gop" >> $envfile
#		echo -e "bitrate=$uv_bitrate" >> $envfile
}

event_livestream() {
	# Livestream switches an additional dedicated livestream decoder ON, it also switches all of the standard encoder boxes to notify that livestreaming is enabled
	# by adding a text box on the top right of the screen.
        if [ $livestreaming = "0" ]; then 
                echo "Option Zero, Livestream currently inactive, Livestream activating"
		SERVERLIST=wavelet_livestream
		ICMD1='systemctl --user start wavelet_start_decoder.service'
		ICMD2='systemctl --user start wavelet_livestream.service'
			while read SERVERNAME
				do
					ssh -n $SERVERNAME $ICMD1 > $SERVERNAME_report.txt
				done < "$SERVERLIST"
		#Runs on the encoder, kills current streaming, replaces image file with Livestream prompt and then restarts the service.
		livestreaming="1"
		echo "Current event is $current_event"
		echo "Livestreaming Activated, restarting video source on $current_event..."
		$current_event	
        else 
                echo "Option Zero, Livestream currently active, Livestream deactivating"
		# Runs on dedicated livestream box and on encoder
		wavelet_kill_livestream
fi
}

wavelet_kill_all() {
	SERVERLIST=wavelet_encoders
	ICMD='systemctl --user stop wavelet.service'
	while read SERVERNAME
		do
			ssh -n $SERVERNAME $ICMD > $SERVERNAME_report.txt
		done < "$SERVERLIST"
}

wavelet-blank() {
        SERVERLIST=wavelet_encoders
	current_event="wavelet-blank"
	envfile=/home/wavelet/uv_service.env
	input='-t file:/home/wavelet/blank1080.pam:loop'
	if [ $livestreaming = "0" ]; then
		echo "Livestreaming is off, starting systemd unit on Encoder."
	        filter="--capture-filter text:color=FF0000:x=15:y=30:t='Blank'"
		assemble_systemd
		ICMD0="systemctl --user stop wavelet.service && rm -rf /home/wavelet/uv_service.env"
		ICMD1="systemctl --user daemon-reload && systemctl --user start wavelet.service"
			while read SERVERNAME
		                do
		                        ssh -n $SERVERNAME $ICMD0
					scp /home/wavelet/uv_service.env wavelet@$SERVERNAME:/home/wavelet/
					ssh -n $SERVERNAME $ICMD1
		                done < "$SERVERLIST"
	else
		echo "Livestreaming is enabled, configuring livestream systemd unit for $current_event"
	        filter="--capture-filter text:color=FF0000:x=15:y=30:t='LiveStream Enabled'"
		assemble_systemd
		ICMD0="systemctl --user stop wavelet.service && rm -rf /home/wavelet/uv_service.env"
		ICMD1="systemctl --user daemon-reload && systemctl --user start wavelet.service"
		        while read SERVERNAME
				do
					ssh -n $SERVERNAME $ICMD0
					scp /home/wavelet/uv_service.env wavelet@$SERVERNAME:/home/wavelet/
					ssh -n $SERVERNAME $ICMD1
				done < "$SERVERLIST"
	fi
}

# the rest of these are broken momentarily until I fix the live/notlive/systemd/environment variable thing.

wavelet-seal() {
        SERVERLIST=wavelet_encoders
        current_event="wavelet-seal"
        envfile=/home/wavelet/uv_service.env
        input='-t file:/home/wavelet/ny-stateseal.pam:loop'
        if [ $livestreaming = "0" ]; then
        	echo "Livestreaming is off, starting systemd unit on Encoder."
	        filter="--capture-filter text:color=FF0000:x=10:y=30:t='S'"
		assemble_systemd
		ICMD0="systemctl --user stop wavelet.service"
		ICMD1="systemctl --user daemon-reload && systemctl --user start wavelet.service"
			while read SERVERNAME
				do
					ssh -n $SERVERNAME $ICMD0
					scp /home/wavelet/uv_service.env wavelet@$SERVERNAME:/home/wavelet/
					ssh -n $SERVERNAME $ICMD1
				done < "$SERVERLIST"
	else
		echo "Livestreaming is enabled, configuring livestream systemd unit for $current_event" 
		filter="--capture-filter text:color=FF0000:x=10:y=30:t='LiveStream Enabled'"
		assemble_systemd
		ICMD0="systemctl --user stop wavelet.service"
		ICMD1="systemctl --user daemon-reload && systemctl --user start wavelet.service"
			while read SERVERNAME
				do
					ssh -n $SERVERNAME $ICMD0
					scp /home/wavelet/uv_service.env wavelet@$SERVERNAME:/home/wavelet/
					ssh -n $SERVERNAME $ICMD1
				done < "$SERVERLIST"
	fi
}

wavelet-evidence() {
        SERVERLIST=wavelet_encoders
	current_event="wavelet-evidence"
	envfile=/home/wavelet/uv_service.env
	# Note the device and settings ("caps") for the document camera are device and setup dependent.
	# Still want to circle back and get some kind of useful autosensing working for this
	input="-t v4l2:codec=MJPG:size=1920x1080:tpf=1/30:convert=RGB:device=/dev/video4"
	if [ $livestreaming = "0" ]; then
		echo "Livestreaming is off, starting systemd unit on Encoder."
		filter="--capture-filter text:color=FF0000:x=15:y=30:t='Ev1'"
		assemble_systemd
		ICMD0="systemctl --user stop wavelet.service"
		ICMD1="systemctl --user daemon-reload && systemctl --user start wavelet.service"
		while read SERVERNAME
			do
				ssh -n $SERVERNAME $ICMD0
				scp /home/wavelet/uv_service.env wavelet@$SERVERNAME:/home/wavelet/
				ssh -n $SERVERNAME $ICMD1
			done < "$SERVERLIST"
		else
			echo "Livestreaming is enabled, configuring livestream systemd unit for $current_event"
	
		filter="--capture-filter text:color=FF0000:x=15:y=30:t='Ev1 LiveStream Enabled'"
		assemble_systemd
		ICMD0="systemctl --user stop wavelet.service"
		ICMD1="systemctl --user daemon-reload && systemctl --user start wavelet.service"
		while read SERVERNAME
			do
				ssh -n $SERVERNAME $ICMD0
				scp /home/wavelet/uv_service.env wavelet@$SERVERNAME:/home/wavelet/
				ssh -n $SERVERNAME $ICMD1
			done < "$SERVERLIST"
	fi
}

wavelet-evidence-hdmi() {
	current_event="wavelet-evidence-hdmi"
        SERVERLIST=wavelet_encoders
	envfile=/home/wavelet/uv_service.env
	input="-t v4l2:codec=MJPG:size=1920x1080:tpf=1/30:convert=RGB:device=/dev/video0"
	if [ $livestreaming = "0" ]; then
		echo "Livestreaming is off, starting systemd unit on Encoder."
		filter="--capture-filter text:color=FF0000:x=15:y=30:t='Cnsl'"
		assemble_systemd
		ICMD0="systemctl --user stop wavelet.service"
		ICMD1="systemctl --user daemon-reload && systemctl --user start wavelet.service"
		while read SERVERNAME
			do
				ssh -n $SERVERNAME $ICMD0
				scp /home/wavelet/uv_service.env wavelet@$SERVERNAME:/home/wavelet/
				ssh -n $SERVERNAME $ICMD1
			done < "$SERVERLIST"
	else
		echo "Livestreaming is enabled, configuring livestream systemd unit for $current_event"
		filter="--capture-filter text:color=FF0000:x=15:y=30:t='Cnsl LiveStream Enabled'"
		assemble_systemd
		ICMD0="systemctl --user stop wavelet.service"
		ICMD1="systemctl --user daemon-reload && systemctl --user start wavelet.service"
		while read SERVERNAME
			do
				ssh -n $SERVERNAME $ICMD0
				scp /home/wavelet/uv_service.env wavelet@$SERVERNAME:/home/wavelet/
				ssh -n $SERVERNAME $ICMD1
			done < "$SERVERLIST"
	fi
}

wavelet-hybrid() {
	current_event="wavelet-hybrid"
	SERVERLIST=wavelet_encoders
	envfile=/home/wavelet/uv_service.env
	input='-t v4l2:codec=MJPG:size=1920x1080:tpf=1/30:convert=RGB:device=/dev/video2'
	if [ $livestreaming = "0" ]; then
		echo "Livestreaming is off, starting systemd unit on Encoder."
		filter="--capture-filter text:color=FF0000:x=15:y=30:t='Gallery'"
		assemble_systemd
		ICMD0="systemctl --user stop wavelet.service"
		ICMD1="systemctl --user daemon-reload && systemctl --user start wavelet.service"
		while read SERVERNAME
			do
				ssh -n $SERVERNAME $ICMD0
				scp /home/wavelet/uv_service.env wavelet@$SERVERNAME:/home/wavelet/
				ssh -n $SERVERNAME $ICMD1
			done < "$SERVERLIST"
		else
		echo "Livestreaming is enabled, configuring livestream systemd unit for $current_event"
		filter="--capture-filter text:color=FF0000:x=15:y=30:t='Gallery LiveStream Enabled'"
		assemble_systemd
		ICMD0="systemctl --user stop wavelet.service"
		ICMD1="systemctl --user daemon-reload && systemctl --user start wavelet.service"
		while read SERVERNAME
			do
				ssh -n $SERVERNAME $ICMD0
				scp /home/wavelet/uv_service.env wavelet@$SERVERNAME:/home/wavelet/
				ssh -n $SERVERNAME $ICMD1
			done < "$SERVERLIST"
	fi
}

wavelet_kill_livestream() {
                # Runs on dedicated livestream box, attempts to kill livestream on system restart.
                # This is a security feature
                SERVERLIST=wavelet_livestream
                ICMD1='systemctl --user stop wavelet_start_decoder.service'
                ICMD2='systemctl --user stop wavelet_livestream.service'
                while read SERVERNAME
                        do
				ssh -n $SERVERNAME $ICMD1 > $SERVERNAME_report.txt
                        	ssh -n $SERVERNAME $ICMD2 > $SERVERNAME_report.txt
                        done < "$SERVERLIST"
		# Runs on encoder box, stops service, swaps watermark.
		echo "Current event is $current_event"
		echo "Livestreaming deactivated...restarting encoder..."
		livestreaming="0"
		$current_event
}


# These events contain additional codec-specific settings that have been found to work acceptably well on the system.
# Since they are tuned by hand, you probably won't want to modify them unless you know exactly what you're doing.
# Proper operation depends on bandwidth, latency, network quality, encoder speed.  It's highly hardware dependent.
# These operate in conjunction with the standard defined variables set above.  
# Standard settings are 
# hevc_vaapi encoder
# GOP=2 (keyframe interval every other frame, higher causes obvious drops on slower client decoders)
# bitrate 2M/s, lower introduces quality drops.

event_x264() {
	uv_encoder="-c libavcodec:encoder=h264_vaapi:gop=5:bitrate=50M"
	echo "x264 VA-API acceleration activated, GOP=5, BR=50M"
	uv_gop="2"
	uv_bitrate="50M"
}

event_hevc() {
	uv_encoder="-c libavcodec:encoder=hevc_vaapi:gop=2:bitrate=50M"
	echo "HEVC VA-API acceleration activated, GOP=2, BR=50M"
	uv_gop="2"
	uv_bitrate="50M"
}			

even_av1() {
	uv_encoder="libavcodec:encoder=av1_vaapi:gop=5:bitrate=7M"
	echo "Experimented AV1 acceleration activated (needs 12th gen+ Intel CPU for encoder)"
	uv_gop="5"
	uv_bitrate="50M"
												        }

# execute main function
# always set livestreaming and recording to off, kill encoder  as initial values when starting the application!
# This ensures a system reset.
wavelet_kill_all
wavelet_kill_livestream
current_event="wavelet_seal"
systemctl restart wavelet-keylogger.service
recording=0
wavelet_reflector 
main
wavelet_seal
