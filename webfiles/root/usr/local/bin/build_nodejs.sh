#!/bin/bash

# This module spins up a node.js container capable of supporting Angular and REACT for the new webUI
# this is for an interactive podman shell, we'll add RUN directives after we get everything running to our satisfaction in order to perform the steps we'll test manually first
# the angular app itself is cloned from github along with everything else (or will be once I put the mockup in there)

# won't need this once we up the angular app because /wavelet/nodejs will be already created
mkdir -p /home/wavelet/container-angular-webui /home/wavelet/nodejs
chown -R wavelet:wavelet /home/wavelet/container-angular-webui /home/wavelet/nodejs

echo -e "# Dockerfile
FROM node:alpine

# copy local app files and dirs to the defined directory
COPY . /home/wavelet/nodejs

# Set the working directory
WORKDIR /home/wavelet/nodejs

# Set the entrypoint to a shell
RUN npm install -g @angular/cli

RUN npm install

CMD ["ng", "serve", "--host", "0.0.0.0"]" > /home/wavelet/container-angular-webui/Dockerfile

cd /home/wavelet/container-angular-webui
podman build -t container-angular-webui .
podman run --name container-angular-webui --network host node:alpine -v /home/wavelet/nodejs:/home/wavelet/nodejs:Z
