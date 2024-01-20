#!/bin/bash
# Runs etcd in a container on the local machine to generate a persistent cluster. 
# May not use in the final analysis but wanted it to be a feature.

# find hostname and store in variable, apply that to the below
# TODO - Add TLS and password security

/bin/podman run --name etcd --net=host \
                    quay.io/coreos/etcd:latest /usr/local/bin/etcd              \
                            --data-dir /etcd-data --name wavelet_$(hostname)                  \
                            --initial-advertise-peer-urls http://0.0.0.0:2380 \
                            --listen-peer-urls http://0.0.0.0:2380           \
                            --advertise-client-urls http://0.0.0.0:2379       \
                            --listen-client-urls http://0.0.0.0:2379        \
                            --initial-cluster wavelet_svr=http://192.168.1.32:2380 \
                            --initial-cluster-state existing