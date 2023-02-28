#May need some udev rule to make sure it always maps to the right input device
#!/bin/bash


# Define event paramaters
event_blank="1"
event_seal="2"
event_witness="3"
event_evidence="4"
event_evidence_hdmi="5"
event_hybrid="6"
event_record="7"
event_livestream="0"

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
	($event_blank) ./wavelet_kill_all.sh && ./wavelet_blankscreen.sh && echo "Option One, Blank activated" ;; # display black screen
	($event_seal) ./wavelet_kill_all.sh && ./wavelet_seal.sh && echo "Option Two, Seal activated" ;; # TBD - just display a static image (dickbutt.jpg)
	($event_witness) ./wavelet_kill_all.sh && ./wavelet_witness.sh && echo "Option Three, Witness activated";; # feed from Webcam
	($event_evidence) ./wavelet_kill_all.sh && ./wavelet_evidence.sh && echo "Option Four, Document Camera activated";; # document camera basically
	($event_evidence_hdmi) ./wavelet_kill_all.sh && ./wavelet_evidence-hdmi.sh && echo "Option Five, HDMI Capture Input activated";; # display HDMI intpu from plaintiff or defendant or from other HDMI source
	($event_hybrid) ./wavelet_kill_all.sh && ./wavelet_hybrid.sh && echo "Option Six, Hybrid Mode activated";; # Switch to a screen capture pulling a Teams meeting window
	($event_record) ./wavelet_record.sh ;; # does not kill any streams, instead copies stream and appends to a labeled MKV file
	($event_livestream) ./wavelet_livestream.sh && echo "Option Zero, Livestream enabled" # does not kill anything, turns on livestreaming and switchers decoders to notify that livestreaming is on
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

# Brings up necessary services and executes main thread
# unifi container, should start with OS but do it here too
#systemctl start unifictl-container.service
# keylogger necessary to get keystroke input from device
#systemctl start wavelet-keylogger.service
#hd-rum multi is the 1-many reflector required to properly distribute ultragrid packets through network
#/home/labuser/Downloads/UltraGrid-1.7.7/hd-rum 64M 5004 192.168.1.10 192.168.1.25 192.168.1.7 192.168.1.21 192.168.1.29
# main function
main 
