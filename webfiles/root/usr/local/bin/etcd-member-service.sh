#!/bin/bash
# Runs etcd in a container on the local machine to generate a persistent cluster. 

# TODO - Add TLS and password security

echo -e "[Unit]
Description=etcd member service container
After=local-fs.target

[Container]
ContainerName=etcd-container
Image=quay.io/coreos/etcd:latest
Network=host
Volume=/etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt
Volume=/var/lib/etcd:/etcd-data
PublishPort=2379:2379
PublishPort=2380:2380
Environment=--name wavelet_$(hostname)
Environment=--data-dir /etcd-data
Environment=--initial-advertise-peer-urls http://0.0.0.0:2380
Environment=--listen-peer-urls http://0.0.0.0:2380 
Environment=--advertise-client-urls http://0.0.0.0:2379
Environment=--listen-client-urls http://0.0.0.0:2379
Environment=--initial-cluster wavelet_svr=http://192.168.1.32:2380
Environment=--initial-cluster-state existing
Exec=/usr/local/bin/etcd

[Service]
TimeOutStartSec=300
Restart=always

[Install]
# Start by default on boot
WantedBy=multi-user.target default.target
" > /home/wavelet/.config/containers/systemd/etcd.container