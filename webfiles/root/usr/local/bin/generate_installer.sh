#!/bin/bash
# This generates the appropriate installer .tar.xz files to simplify labbing
generate_tarfiles(){
				echo -e "Generating tar.xz files for upload to distribution server..\n"
				tar -cJf usrlocalbin.tar.xz -C /usr/local/bin/ .
				tar -cJf wavelethome.tar.xz -C /home/wavelet/http-php .
				echo -e "Packaging files together..\n"
				tar -cJf wavelet-files.tar.xz {./usrlocalbin.tar.xz,wavelethome.tar.xz}
				echo -e "Done."
				rm -rf {./usrlocalbin.tar.xz,wavelethome.tar.xz}
}

###
#
# Main
#
###

generate_tarfiles