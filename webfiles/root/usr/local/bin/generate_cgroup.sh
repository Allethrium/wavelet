#!/bin/bash

# This is called from a rootful systemd unit and is designed to generate a user-moddable cgroup we can utilize for intelligent resource pinning

mount -t tmpfs cgroup_root /sys/fs/cgroup
mkdir /sys/fs/cgroup/cpuset
mount -t cgroup -o cpuset cpuset /sys/fs/cgroup/cpuset
mkdir /sys/fs/cgroup/cpuset/wavelet
chown -R wavelet /sys/fs/cgroup/cpuset/wavelet/