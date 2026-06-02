#!/bin/bash
# This generates the appropriate installer .tar.gz files to simplify the setup ignition files
# tar file is uncompressed immediately on ignition startup and effectively installs Wavelet onto the machine
# Necessary because HTML/PHP gives Ignition problems downloading the file directly
# Don't do etc, let ignition handle that.
generate_tarfiles(){
		echo -e "Generating tar.gz files for upload to distribution server..\n"
		tar -cJf usrlocalbin.tar.xz --owner=root:0 -C ./webfiles/root/usr/local/bin/ .
		tar -cJf wavelethome.tar.xz --owner=wavelet:1337 -C ./webfiles/root/home/wavelet/ .
		echo -e "Packaging files together..\n"
		tar -cf wavelet-files.tar.gz {./usrlocalbin.tar.xz,wavelethome.tar.xz}
		echo -e "Done."
		rm -rf {./usrlocalbin.tar.xz,wavelethome.tar.xz}
}

###
#
# Main
#
###

generate_tarfiles