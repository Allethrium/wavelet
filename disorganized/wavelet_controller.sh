#May need some udev rule to make sure it always maps to the right input device
#!/bin/bash

# Define event paramaters
event_blank="1"
event_seal="2"
event_witness="3"
event_evidence="4"
event_evidence_pip="5"
event_hybrid="6"
event_record="7"

while read LINE; do
case $LINE in
    ($event_blank) ./wavelet_kill_all.sh && ./wavelet_blankscreen.sh && echo "Option One, Blank activated" ;; # display black screen
    ($event_seal) ./wavelet_kill_all.sh && ./wavelet_seal.sh && echo "Option Two, Seal activated" ;; # TBD - just display a static image (dickbutt.jpg)
    ($event_witness) ./wavelet_kill_all.sh && ./wavelet_witness.sh && echo "Option Three, Witness activated";; # feed from Webcam
    ($event_evidence) ./wavelet_kill_all.sh && ./wavelet_evidence.sh && echo "Option Four, Document Camera activated";; # document camera basically
    ($event_evidence_pip) ./wavelet_kill_all.sh && ./wavelet_evidence_pip.sh && echo "Option Five, Doc with Witness PIP activated";; # display picture-in picture combo of Evidence, Witness in smaller frame
    ($event_hybrid) ./wavelet_kill_all.sh && ./wavelet_hybrid.sh && echo "Option Six, Hybrid Mode activated";; # Switch to a screen capture pulling a Teams meeting window
    ($event_record) ./wavelet_record.sh ;; # does not kill any streams, instead copies stream and appends to a labeled MKV file
	esac
done 
