###Wavelet

Wavelet is a local video appliance leveraging other projects such as UltraGrid.  It designed to provide a quick 'Pop-Up' solution for venues where running network or HDMI cables is undesirable, or impractical.

It does so by:

* Avoiding unnecessary cabling by utilizing modern Wireless technologies
* Leveraging the power of open source software, as free as humanly possible from proprietary vendor lock-ins.
* Being platform agnostic and usable on different systems and architectures
* Having an easy to use web interface which can be used to quickly configure input options
* Targeting low-cost and easily sourced hardware platforms

Wavelet at its most basic setup is composed of five components:

* Linux-based server
* (Optional) Linux-based primary encoder
* Wireless Access Point
* Small Network Switch supporting at least gigabit ethernet with a proper jumbo frame implementation
* An x86 decoder (decoder ARM SBC support, and hopefully RISC-V suport in the future is possible)

More advanced setups may add additional encoders and decoders, however the core components of a switch, wireless AP and server are REQUIRED.

Wavelet is implemented over several open source applications, called by system or user-level systemd units.

In its current form, It utilizes a set of bash modules combined with the distributed keystore system etcd to control systemd services on the encoders and decoders in response to input from a simple web server/PHP Script running on the server.   This control surface is accessible from any device connected via WiFi.

##Disclaimer:

Wavelet is designed as an APPLIANCE.   This means that software is not supposed to be updated after installation is completed, and that the system does not connect to any networks beyond the local Wavelet WiFi network.  If control channels for software updates or internet access for livestreaming are necessary, appropriate network segmentation should be carefully considered.   Under no circumstances should the system be deployed on a "flat" production network.   If you do this and something bad happens... well I warned you, and I'm not responsible for cleaning up the mess.

Technical reasons for this include a necessity for speedy processing of incoming network packets, therefore host firewalls should be disabled on the encoders, decoder and servers.  Enabling firewall processing introduces a latency penalty which is undesirable in this system's use case.  Whilst the system has some security, it is so latency-focused in design that more common security mitigations were found to be an issue.

Maintenance should be carried out on a dedicated laptop which can connect wirelessly to the system, by an individual familiar with common conventions used on this system.   It can also be performed by connecting a monitor and input devices to the server, as I've implemented a control console of sorts.

Under no circumstances is the system designed to be connected to a secure production network, or to be managed remotely by enterprise patching or security applications.  Unauthorized modifications and hardening will almost certainly break the system or introduce unacceptable performance tradeoffs.

Should this get any traction with a large number of deployments, properly managing the system with an existing infrastructure is something I'll be interested in looking into.

The system builds upon the following projects (Incomplete list - If your stuff was used and we neglected to credit, feel free to let me know!):

* UltraGrid      -  https://github.com/CESNET/UltraGrid
* etcd           -  https://github.com/etcd-io/etcd
* Fedora CoreOS  -  https://github.com/coreos
* FFMPEG         -  https://git.ffmpeg.org/ffmpeg.git
* PipeWire       -  https://github.com/PipeWire
* ImageMagick    -  https://imagemagick.org/

###INSTALLATION

To install, simply git clone this repo to a linux machine with internet access.  This can be a full installation, a liveCD, etc.

My test lab, for instance, has a machine running with a static IP address (above .200) well out of the server DHCP range.  This allows me to ssh into the server whilst it's installing and check logs for progress.

run :
```./install_wavelet_server.sh```

Please note it's a good idea to have your WiFi access point and switch infrastructure pre-configured.   A stretch goal is to leverage IaaS techniques to support provisioning of some target devices as part of the installation process, but that is for the future.

The installer will download appropriate install media, and customize the images appropriately after you have intelligently answered the prompts.

You can then navigate to $HOME/Downloads where the installer will have generated an ISO for the Server and Decoders (decoder image generation will soon be depreciated)

The server must be installed first, and will soon support provisioning client devices directly from itself via PXE / HTTP boot.

Boot the target machine from the server ISO and allow it to run.   As long as your environment is correctly configured with the network settings you specify in the installer and has a stable internet connection, installation is completely automated.  The machine will reboot several times during the process, and once the display shows a browser window with the control console up, it is complete.

The decoders must be imaged whilst connected via ethernet to the server.   Currently, decoders can be subsequently moved between different wavelet servers, but I am considering making security changes (implementing an IDM) that may complicate this.  Once imaged, running connectwifi.sh should automatically connect them to an available and properly configured Wireless network.

I would recommend Ruckus/CommScope APs as their unleashed software is easy to configure and the APs themselves are very fast.  I have heard good things about Engenius APs, and have gotten reasonable performance out of newer Ubiquiti APs, although they are noticeably slower than Ruckus.  My access to other hardware is limited but send me one, and i'll try to work with it and return it in good condition :)

This document will continue to change and evolve as further solutions are explored and verified.

Wavelet can be spun up in a virtual test environment by running:
```./provision_libvirt_testserver.sh```

For this to work, you'll need a properly configured QEMU/libvirt environment and be comfortable editing the script to set your appropriate networking parameters.  