#!/bin/bash
#
#This allows you to configure wavelet devices.  Requires fully setup wavelet controller from initial spin-up script.
#Can run on another machine but please inspect the controller script to install all necessary dependencies!

configure_ignition(){
#myhostname=curl -L https://localhost:2379/v2/keys/butane_hostname
myhostname=hostname
echo '
#
# Tutorial
# https://invidious.tinfoil-hat.net/watch?v=cvWN8dXHaVo
#
# https://rollout.io/blog/infrastructure-as-code/
# https://www.plutora.com/blog/infrastructure-as-code
# https://dzone.com/articles/observability-and-beyond-building-resilient-applic
#
# This file aims to provide a usable base CoreOS image which can run Encoder/Decoder/Livestreamer tasks effectively
#ignition: 
#version: 3.0.0   
variant: fcos
version: 1.5.0
storage:
  files:
# Sets hostname
    - path: /etc/hostname
      mode: 0644
      overwrite: true
      contents: 
        inline: ${myhostname}
# Skel
    - path: /etc/skel/.bashrc
      mode: 420
      overwrite: true
      contents: 
        source: https://andymelville.net/wavelet/public/skel.txt
# Udev_rules (ENCODER but installed on all boxes anyway)
    - path: /etc/udev/rules.d/80-wavelet-encoder.rules
      mode: 420
      overwrite: true
      contents:
        source: https://andymelville.net/wavelet/public/80-wavelet-encoder.rules
#	udev_call  (required otherwise udev blocks /dev/ tree access until trigger is complete)
#	DetectV4l  (attempts to intelligently manage v4l devices with symlinks)

passwd: 
  users:
    - name: wavelet-root
      uid: 9337
      password_hash: $6$nP0Rno68wE$kLZixz9bqOzUspYONNXvH21razOeqkkxo.325Q1pfWtuHWoSAHaoUVrbJ0oqYYjO7f4/Qs5U5HOpm2n6WFASO0
      home_dir: /home/wavelet-root
    - name: wavelet
      uid: 1337
      password_hash: $6$0OV84d.JPTnYjv02$i8JnR90kRViFcTwjPKTB3g7p99DpIux8PJBI2n2ToNvcI7Epb1T2vLLRuansi8WQbxaQT7Ibl/RKWtAD5Otsz0
      home_dir: /home/wavelet
      ssh_authorized_keys_local:
          - id_ed25519.pub
systemd:
  units:
    - name: install-overlayed-rpms.service
      enabled: true
      contents: |
        [Unit]
        Description=Install Required Overlay Packages
        ConditionFirstBoot=yes
        Wants=network-online.target
        After=network-online.target
        After=multi-user.target
        [Service]
        Type=oneshot
        ExecStart=rpm-ostree install vim powerline powerline-fonts vim-powerline cockpit NetworkManager-wifi iw wireless-regdb wpa_supplicant etcd --reboot
        [Install]
        WantedBy=multi-user.target
    - name: etcd-member.service
      enabled: true
      contents: |
        [Unit]
        Description=Run etcd
        After=network-online.target
        Wants=network-online.target
        [Service]
        ExecStartPre=mkdir -p /var/lib/etcd
        ExecStartPre=-/bin/podman kill etcd
        ExecStartPre=-/bin/podman rm etcd
        ExecStartPre=-/bin/podman pull quay.io/coreos/etcd
        ExecStart=/bin/podman run --name etcd --volume /var/lib/etcd:/etcd-data:z --net=host quay.io/coreos/etcd:latest /usr/local/bin/etcd --data-dir /etcd-data --name node1 \
                        --initial-advertise-peer-urls http://0.0.0.0:2380 --listen-peer-urls http://0.0.0.0:2380 \
                        --advertise-client-urls http://0.0.0.0:2379 \
                        --listen-client-urls http://0.0.0.0:2379 \
                        --initial-cluster node1=http://192.168.1.32:2380
        ExecStop=/bin/podman stop etcd
        [Install]
        WantedBy=multi-user.target
" > /home/wavelet/ignition_base.yaml
}

configure_devices(){
	echo	'Would you like to configure Wavelet devices now?'
	echo	'Please note that device configuration can be run from a separate bash script configure_devices.sh at any time.'
	read -p '(y/n):' confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || echo "User declined to setup other devices, restarting.." exit 1 & wait 5 & shutdown -r now
		PS3='Please select from the following four options:'
		options=("1: Encoder" "2: Livestream" "3: Decoder" "4: Quit")
		select opt in ${options[@]} 
			do
				case $opt in
					'1: Encoder')
						echo '$REPLY input, which is $opt proceeding..'
						read -p 'Enter the desired hostname of the encoder in the format "enc1", "encoder1" or similar:' enc_hostname
						butane_hostname=$enc_hostname.$domain
					;;
					'2: Livestream')
						echo '$REPLY input, which is $opt proceeding..'
						read -p 'Enter the desired hostname of the livestream device in the format "lvstrm1", "livestream1":' lvstrm_hostname
						butane_hostname=$enc_hostname.$domain
					;;
					'3: Decoder')
						echo '$REPLY input, which is $opt proceeding..'
						read -p 'Enter the desired hostname of the Decoder in the format "dec1", "decoder1" or similar:' dec_hostname
						butane_hostname=$dec_hostname.$domain
					;;
					'4: Quit')
						break
					;;
					*)	echo 'invalid option $REPLY'
				;;
				esac
			done
	curl -L https://localhost:2379/v2/keys/butane_hostname -XPUT -d value=$butane_hostname
	configure_ignition
	echo "Ignition file configured, compiling and making available to iPXE.."
	butane /home/wavelet/ignition_base.yaml > /home/wavelet/http/media/ignition/config.ign --files-dir . 
	read -p "Please boot the target machine whilst it is connected via ethernet cable to the Wavelet switch.  It ought to boot from iPXE automatically and self-configure.  Hit Enter when done." </dev/tty
	read -p 'Would you like to configure an additional device? (y/n):' confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || echo "User declined to setup other devices, restarting.." exit 1 & wait 5 & shutdown -r now
	configure_devices
}
configure_devices
echo "script ran successfully!"
