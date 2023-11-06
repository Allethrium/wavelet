#!/bin/bash
# Encoder launcher script
# generates a systemd --user unit file for the UG appimage with the appropriate command lines
# Launches it as its own systemd --user service.

#Etcd Interaction
ETCDURI=http://192.168.1.32:2379/v2/keys
ETCDENDPOINT=192.168.1.32:2379
read_etcd(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get $(hostname)/${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_inputs(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get $(hostname)/inputs/${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_prefix(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix $(hostname)/${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for host $(hostname)"
}

read_etcd_global(){
        printvalue=$(etcdctl --endpoints=${ETCDENDPOINT} get ${KEYNAME} --print-value-only)
        echo -e "Key Name {$KEYNAME} read from etcd for value $printvalue for Global value"
}

write_etcd(){
        etcdctl --endpoints=${ETCDENDPOINT} put "$(hostname)/${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for $(hostname)"
}

write_etcd_global(){
        etcdctl --endpoints=${ETCDENDPOINT} put "${KEYNAME}" -- "${KEYVALUE}"
        echo -e "${KEYNAME} set to ${KEYVALUE} for Global value"
}

write_etcd_clientip(){
        etcdctl --endpoints=${ETCDENDPOINT} put decoderip/$(hostname) "${KEYVALUE}"
        echo -e "$(hostname) set to ${KEYVALUE} for Global value"
}
read_etcd_clients_ip() {
        return_etcd_clients_ip=$(etcdctl --endpoints=${ETCDENDPOINT} get --prefix decoderip/ --print-value-only)
}

event_encoder(){
# Register yourself with etcd as an encoder and your IP address
# 10/23 can add if/then logic + increment to support multiple encoders in future?
KEYNAME=encoder_ip_address
KEYVALUE=$(ip a | grep 192.168.1 | awk '/inet / {gsub(/\/.*/,"",$2); print $2}')
write_etcd_global
systemctl --user daemon-reload
systemctl --user enable watch_encoderflag.service --now
echo -e "now monitoring for encoder reset flag changes.. \n"

KEYNAME=INPUT_DEVICE_PRESENT
read_etcd
	if [[ "$printvalue" -eq 1 ]]; then
		echo -e "An input device is present on this host, continuing.. \n"
		:
	else 
		echo -e "No input devices are present on this system, Encoder cannot run! \n"
		exit 0
	fi

# Read etcd for appropriate configuration values
	read_uv_input() {
	# reads the control key for input and sets appropriate values by copying them from the values set by detectv4l.sh
		KEYNAME=uv_input
		read_etcd_global
		inputselection=${printvalue}
			case $inputselection in
			BLANK) 					echo -e "Blank Screen \n"												&& encoder_event_set_blank
			;;
			SEAL)					echo -e "NYS Seal Image \n"												&& encoder_event_set_seal
			;;
			EVIDENCECAM1)			echo -e "Evidence Document Camera \n"									&& encoder_event_set_documentcam
			;;
			HDMI1)					echo -e "Counsel HDMI Input"											&& encoder_event_set_hdmi1
			;;
			HDMI2)					echo -e "Other HDMI Input"												&& encoder_event_set_hdmi2
			;;
			HYBRID) 				echo -e "HDMI Input from PreConfigured Teams/Conferencing terminal" 	&& encoder_event_set_hybrid
			;;
			WITNESS) 				echo -e "Re-encoding stream from a Witness Video Camera"				&& encoder_event_set_witness
			;;
			COURTROOM) 				echo -e "Re-encoding stream from a wide-angle Courtroom Camera"			&& encoder_event_set_courtroom
			;;
			FOURSPLIT) 				echo -e "Four-way panel split activated \n"								&& encoder_event_set_fourway
			;;
			TWOSPLIT)				echo -e "Four-way panel split activated \n"								&& encoder_event_set_twoway
			;;
			PIP1)					echo -e "Four-way panel split activated \n"								&& encoder_event_set_pip1
			;;
			PIP2)					echo -e "Four-way panel split activated \n"								&& encoder_event_set_pip2
			;;
			*) 						echo -e "Input Key is incorrect, quitting"								&& :
			;;
			esac
		}

	# These short functions copy the etcd input values set in detectv4l.sh and assign them dynamically 
	# to the input_cmd based on the above event.
	# This way, detectv4l.sh is entirely responsible for defining device caps and input paths, 
	# the controller is entirely responsible for control channels and orchestration.
	# The Encoder / run_ug.sh script is ONLY responsible for pulling and concatenating the data, then running UltraGrid.

	# OK multiple encoders... 
	# If i'm not a server, I shouldn't be handling blank / seal,
	# there's absolutely no reason they can't be done on the server for efficiency purposes.
		encoder_event_set_blank(){
			# AppImage is VERY fussy about image formats.
			KEYNAME=uv_input_cmd
			KEYVALUE="-t testcard:pattern=blank"
			/usr/local/bin/wavelet_textgen.sh
			write_etcd
		}
		encoder_event_set_seal(){
			# Always set this to SW x265, *everything else breaks* due to pixel format issues w/ FFMPEG/lavc
			KEYNAME=uv_encoder
			KEYVALUE="libavcodec:encoder=libx265:gop=12:bitrate=33M:subsampling=444:q=12:bpp=10"
			write_etcd_global
			KEYNAME=uv_input_cmd
			KEYVALUE="-t file:/home/wavelet/seal.mp4:loop"
			/usr/local/bin/wavelet_textgen.sh
			cd /home/wavelet/
			ffmpeg -y -s 900x900 -video_size cif -i ny-stateseal.jpg -c:v libx265 seal.mp4
			write_etcd
		}
	# Each of these events needs to decide if this device is connected to this encoder, or not.
	# If it's not under my hostname, do nothing and terminate here, let the encoder with that device deal with it."
		encoder_event_set_documentcam(){
			KEYNAME=v4lDocumentCam
			read_etcd_inputs
			KEYNAME=uv_input_cmd
			KEYVALUE=$printvalue
				case ${printvalue} in
					*)	echo -e "This device has a Document Camera connected, proceeding.."
									/usr/local/bin/wavelet_textgen.sh
									write_etcd
					;;
					"")				echo -e "The there is no Document Camera on this machine, or there is no video input present at all, ending."; exit 0
					;;
				esac
			/usr/local/bin/wavelet_textgen.sh
		}
		encoder_event_set_hdmi1(){
			# assumed a Logitech HDMI-USB adapter for Counsel
			KEYNAME=hdmi_logitech
			read_etcd_inputs
			KEYNAME=uv_input_cmd
			KEYVALUE=$printvalue
				case ${printvalue} in
					*)	echo -e "This device has an LG USB HDMI Input device connected, proceeding.."
									/usr/local/bin/wavelet_textgen.sh
									write_etcd
					;;
					"")				echo -e "The there is no LG USB HDMI Input on this machine, or there is no video input present at all, ending."; exit 0
					;;
				esac
		}
		encoder_event_set_hdmi2(){
			KEYNAME=hdmi_magewell
			read_etcd_inputs
			KEYNAME=uv_input_cmd
			KEYVALUE=$printvalue
				case ${printvalue} in
					*)	echo -e "This device has Magewell USB Input device connected, proceeding.."; 
									/usr/local/bin/wavelet_textgen.sh
									write_etcd
					;;
					"")				echo -e "The there is no Magewell Input on this machine, or there is no video input present at all, ending."; exit 0
					;;
				esac
		}
		encoder_event_set_hybrid(){
			KEYNAME=hdmi3
			read_etcd_inputs
			KEYNAME=uv_input_cmd
			KEYVALUE=$printvalue
				case ${printvalue} in
					*)	echo -e "This device has a Hybrid Teams device connected, proceeding.."
									/usr/local/bin/wavelet_textgen.sh
									write_etcd
					;;
					"")				echo -e "The there is no Hybrid mode on this machine, or there is no video input present at all, ending."; exit 0
					;;
				esac
	}
		encoder_event_set_witness(){
			# If we do this right, this should be a Decklink/SDI input at some point.
			KEYNAME=close_camera
			read_etcd_inputs
			KEYNAME=uv_input_cmd
			KEYVALUE=$printvalue
				case ${printvalue} in
					*)	echo -e "Close Camera has been configured in etcd, proceeding.."
									/usr/local/bin/wavelet_textgen.sh
									write_etcd
					;;
					"")				echo -e "No Close camera device has been connected, ending process."; exit 0
					;;
				esac
	}
		encoder_event_set_courtroom(){
			# If we do this right, this should be a Decklink/SDI input at some point.
			# Might be worth investigating remote PTZ options to configure a camera for long shots appropriately.
			KEYNAME=far_camera
			read_etcd_inputs
			KEYNAME=uv_input_cmd
			KEYVALUE="-t rtsp://admin:cmiNDI2021@192.168.1.20/live/stream0"
			write_etcd
				case ${printvalue} in
					*)	echo -e "Far Camera has been configured in etcd, proceeding.."
									/usr/local/bin/wavelet_textgen.sh
					;;
					"")				echo -e "No far camera device has been connected, ending process."; exit 0
					;;
				esac
	}
		encoder_event_set_fourway(){
		# This block will attempt various four-way panel configurations depending on available devices
		# We need to get a little bit cleverer about how we parse all of these so that they can be assembled dynamically.
		# List all devices from etcd_inputs, parse and then assign them randomly to a panel?
		# That way, if someone is not satisfied with the layout, hitting it again will change the order of the inputs..
			KEYNAME=v4lDocumentCam
			read_etcd_inputs
				case ${printvalue} in
					*)	echo -e "This device has a Document Camera connected, proceeding.."
									PANEL1=$printvalue
					;;
					"")				echo -e "The there is no Document Camera on this machine, a blank panel displayed instead."; exit 0
					;;
				esac
			printvalue=""	
			KEYNAME=hdmi_logitech
			read_etcd_inputs
				case ${printvalue} in
					*)	echo -e "This device has a Logitech HDMI input connected, proceeding.."
									PANEL2=$printvalue
					;;
					"")				echo -e "The there is no LG Input on this machine, a blank panel displayed instead."; exit 0
					;;
				esac
			KEYNAME=hdmi_logitech_1
			read_etcd_inputs
				case ${printvalue} in
					*)	echo -e "This device has a Logitech HDMI input connected, proceeding.."
									PANEL2=$printvalue
					;;
					"")				echo -e "The there is no 2nd LG Input on this machine, a blank panel displayed instead."; exit 0
					;;
				esac
			KEYNAME=hdmi_magewell
			read_etcd_inputs
				case ${printvalue} in
					*)	echo -e "This device has a Magewell HDMI input connected, proceeding.."
									PANEL3=$printvalue
					;;
					"")				echo -e "The there is no Magewell input on this machine, a blank panel displayed instead."; exit 0
									#Can't use the seal image because it causes UG to crash in swmix mode
									PANEL3=""
					;;
				esac

			KEYNAME=hdmi_magewell_1
			read_etcd_inputs
				case ${printvalue} in
					*)	echo -e "This device has an additional Magewell HDMI input connected, proceeding.."
									PANEL4=$printvalue
					;;
					"")				echo -e "The there is no 2nd Magewell input on this machine, a blank panel displayed instead."; exit 0
									#PANEL3="-t file:/home/wavelet/seal.mp4:loop"
									PANEL4=""
					;;
				esac
			KEYNAME=uv_input_cmd
			KEYVALUE="-t swmix:1920:1080:30 ${PANEL1} ${PANEL2} ${PANEL3} ${PANEL4}"
			write_etcd
			/usr/local/bin/wavelet_textgen.sh
		}
		encoder_event_set_twoway(){
		# This block will attempt various four-way panel configurations depending on available devices
			KEYNAME=v4lDocumentCam
			read_etcd_inputs
				case ${printvalue} in
					*)	echo -e "This device has a Document Camera connected, proceeding.."
									PANEL1=$printvalue
					;;
					"")				echo -e "The there is no Document Camera on this machine, a blank panel displayed instead."; exit 0
					;;
				esac

			KEYNAME=hdmi_logitech
			read_etcd_inputs
				case ${printvalue} in
					*)	echo -e "This device has a Logitech HDMI input connected, proceeding.."
									PANEL2=$printvalue
					;;
					"")				echo -e "The there is no LG Input on this machine, a blank panel displayed instead."; exit 0
					;;
				esac

			KEYNAME=hdmi_magewell
			read_etcd_inputs
				case ${printvalue} in
					*)	echo -e "This device has a Magewell HDMI input connected, proceeding.."
									PANEL3=$printvalue
					;;
					"")				echo -e "The there is no Magewell input on this machine, a blank panel displayed instead."; exit 0
					;;
				esac

			KEYNAME=uv_input_cmd
			KEYVALUE="-t swmix:1920:1080:30:UYVY ${PANEL1} ${PANEL2}"
			write_etcd
			/usr/local/bin/wavelet_textgen.sh
		}
		encoder_event_set_pip1(){
		# This block will attempt various four-way panel configurations depending on available devices
		# Doesn't seem to work - I think we need UG to be able to define a path because it is not where the .rc file needs to be.
			KEYNAME=v4lDocumentCam
			read_etcd_inputs
				case ${printvalue} in
					*)	echo -e "This device has a Document Camera connected, proceeding.."
									PANEL1=$printvalue
					;;
					"")				echo -e "The there is no Document Camera on this machine, seal image will be displayed instead."; exit 0
					;;
				esac
			KEYNAME=hdmi_logitech
			read_etcd_inputs
				case ${printvalue} in
					*)	echo -e "This device has a Logitech HDMI input connected, proceeding.."
									PANEL2=$printvalue
					;;
					"")				echo -e "The there is no LG Input on this machine, seal image will be displayed instead."; exit 0
					;;
				esac
			KEYNAME=hdmi_magewell
			read_etcd_inputs
				case ${printvalue} in
					*)	echo -e "This device has a Magewell HDMI input connected, proceeding.."
									PANEL3=$printvalue
					;;
					"")				echo -e "The there is no Magewell input on this machine, seal image will be displayed instead."; exit 0
					;;
				esac
			echo "1920:1080:30
${PANEL1} 0	0	1920	1080
${PANEL2} 1620	780	1900	1060" > /home/wavelet/.ug-swmix.rc
			KEYNAME=uv_input_cmd
			KEYVALUE="-t swmix:file=/home/wavelet/.ug-swmix.rc"
			write_etcd
			/usr/local/bin/wavelet_textgen.sh
		}
		encoder_event_set_pip2(){
		# This block will attempt various four-way panel configurations depending on available devices
		# Doesn't seem to work - I think we need UG to be able to define a path because it is not where the .rc file needs to be.
			KEYNAME=v4lDocumentCam
			read_etcd_inputs
				case ${printvalue} in
					*)	echo -e "This device has a Document Camera connected, proceeding.."
									PANEL1=$printvalue
					;;
					"")				echo -e "The there is no Document Camera on this machine, seal image will be displayed instead."; exit 0
									#PANEL1="-t file:/home/wavelet/seal.mp4:loop"
					;;
				esac
			KEYNAME=hdmi_logitech
			read_etcd_inputs
				case ${printvalue} in
					*)	echo -e "This device has a Logitech HDMI input connected, proceeding.."
									PANEL2=$printvalue
					;;
					"")				echo -e "The there is no LG Input on this machine, seal image will be displayed instead."; exit 0
					;;
				esac
			KEYNAME=hdmi_magewell
			read_etcd_inputs
				case ${printvalue} in
					*)	echo -e "This device has a Magewell HDMI input connected, proceeding.."
									PANEL3=$printvalue
					;;
					"")				echo -e "The there is no Magewell input on this machine, seal image will be displayed instead."; exit 0
					;;
				esac
			echo "1920:1080:30
${PANEL2}   0   0 1920 1080
${PANEL3} 1620 780 1900 1060" > /home/wavelet/.ug-swmix.rc
			KEYNAME=uv_input_cmd
			KEYVALUE="-t swmix:file=/home/wavelet/.ug-swmix.rc"
			write_etcd
			/usr/local/bin/wavelet_textgen.sh
		}




# Main
read_uv_input


# Reads Filter settings, should be banner.pam most of the time
KEYNAME=uv_filter_cmd
read_etcd_global
filtervar=${printvalue}

# Reads Input settings from detectv4l.sh or another source
KEYNAME=uv_input_cmd
read_etcd
inputvar=${printvalue}

# Reads Encoder codec settings, should be populated from the Controller
KEYNAME=uv_encoder
read_etcd_global
encodervar=${printvalue}

# Videoport is always 5004 unless we are doing some strange future project requiring bidirectionality or conference modes
KEYNAME=uv_videoport
read_etcd_global
video_port=${printvalue}

# Audio Port is always 5006, unless UltraGrid has gotten far better at handling audio we likely won't use this.
KEYNAME=uv_audioport
read_etcd_global
audio_port=${printvalue}

# Destination IP is the IP address of the UG Reflector
destinationipv4="192.168.1.32"


# Currently -f V:rs:200:250 on the end specifies reed-solomon forward error correction 
# Audio runs as a multiplied stream, if enabled at all.
# Disabled traffic shaping for additional speed
echo -e "Assembled command is: \n --tool uv $filtervar -f V:rs:200:250 -l unlimited ${inputvar} -c ${encodervar} -P ${uv_videoport} -m 9000 ${destinationipv4} \n"
ugargs="--tool uv $filtervar -f V:rs:200:255 -l unlimited ${inputvar} -c ${encodervar} -P ${video_port} -m 9000 ${destinationipv4}"
KEYNAME=UG_ARGS
KEYVALUE=${ugargs}
write_etcd
echo -e "Verifying stored command line"
read_etcd
echo "
[Unit]
Description=UltraGrid AppImage executable
After=network-online.target
Wants=network-online.target
[Service]
ExecStart=/usr/local/bin/UltraGrid.AppImage ${ugargs}
KillSignal=SIGTERM
[Install]
WantedBy=default.target" > /home/wavelet/.config/systemd/user/UltraGrid.AppImage.service
systemctl --user daemon-reload
systemctl --user restart UltraGrid.AppImage.service
echo -e "Encoder systemd units instructed to start..\n"
}

# Main
set -x
exec >/home/wavelet/encoder.log 2>&1
event_encoder
