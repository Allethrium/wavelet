#!/bin/bash
#
# Regenerates the plaintext credentials file from the pregenerated etcd steps, and re-saves it for systemd, runs as ROOT only
# I should probably expand this to the other systemd units, now that I know it exists.

mkdir -p /var/roothome/.ssh/secrets
cd /var/roothome/.ssh/secrets
local password2=$(cat /var/home/wavelet/config/pw2.txt); hostname=$(hostname);
local password1=$(openssl enc -e -aes-256-cbc -md sha512 -pbkdf2 -pass "pass:${password2}" -nosalt -in /var/home/wavelet/.ssh/secrets/$(hostname).crypt.bin -d | base64 -d);
systemd-creds encrypt --name=etcd_client_pass plaintext.txt ciphertext.cred
shred -u plaintext.txt