#!/bin/bash
# Bootstrapper for v4l device handling - note that both commands have & at the end
# The scripts won't work unless the immediate udev job is completed
# Udev blocks access to the /dev/ folder for scripts if it hasn't finished doing its thing
# therefore THIS script must be terminated before the detection/removal scripts will work!
set -x
exec >/home/wavelet/udev_call.log 2>&1
echo "Udev sorter invoked by USB activity, waiting 2 seconds and calling sorter.."
sleep .5
check=$@
if [ "${check}" = "remove" ]; then
	echo -e " \n UDEV called with remove, executing device enumeration to remove stale devices.\n  
				Note all devices with v4l paths which do not exist will be pruned.. \n"
	/bin/su -c "/usr/local/bin/wavelet_removedevice.sh" - wavelet &
	else
	echo -e " \n UDEV called without remove, assuming device has been added, calling detectv4l.sh \n"
	/bin/su -c "/usr/local/bin/wavelet_detectv4l.sh" - wavelet &
fi
