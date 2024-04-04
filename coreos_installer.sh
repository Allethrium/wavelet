# Be sure to specify the correct HDD - you can test this by booting a live linux distro, going to terminal
# try using lsblk at the terminal to list available drives and partitions.
#
#/usr/libexec/coreos-installer -d $hddSDx$ -b file:///$usbmountpoint$/fedora-coreos.raw.xz -i file:///$usbmountpoint$/ignition.json

echo "Removing old customized ISO files.."
rm -rf wavelet_server.iso
rm -rf wavelet_decoder.iso

echo -e "\n  Note: Put the drive controller for target device in AHCI mode from BIOS setup!  \n"
#read -p "Please input the FULL path of your destination device I.E /dev/nvme0n1.  Could also be /dev/vda if VM:" DESTINATION_DEVICE
DESTINATION_DEVICE="/dev/nvme0n1"
echo -e "Destination device is set to ${DESTINATION_DEVICE}, please verify!"
#read -p "Continue? (Y/N): " confirm && [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]] || exit

FILEPREFIX="fedora-coreos-"
if ls ./$FILEPREFIX* > /dev/null 2>&1; then
	echo "CoreOS image already exists."
	:
	else
	echo "No ISO found, downloading CoreOS ISO from internet.."
	coreos-installer download -s stable -a x86_64 -p metal -f iso
fi

IMAGEFILE=$(ls -t *.iso | head -n1)
echo "Generating Ignition files with Butane.."
butane --pretty --strict ./server_custom.yml --output server.ign
butane --pretty --strict ./encoder_custom.yml --output encoder.ign
butane --pretty --strict ./decoder_custom.yml --output decoder.ign
echo "Customizing ISO files with Ignition"
coreos-installer iso customize --dest-device ${DESTINATION_DEVICE} --dest-ignition decoder.ign -o $HOME/Downloads/wavelet_decoder.iso ${IMAGEFILE}
coreos-installer iso customize --dest-device ${DESTINATION_DEVICE} --dest-ignition encoder.ign -o $HOME/Downloads/wavelet_encoder.iso ${IMAGEFILE}
coreos-installer iso customize --dest-device ${DESTINATION_DEVICE} --dest-ignition server.ign -o $HOME/Downloads/wavelet_server.iso ${IMAGEFILE}
echo -e "Images generated, server will subsequently bootstrap everything. \n ensure it's setup before attempting to install another device, or their installation will fail. \n"
