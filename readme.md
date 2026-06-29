### Wavelet

Wavelet is a local video appliance.  

Wavelet is designed to provide a quick 'Pop-Up' solution for low-latency video transmission at venues where running network or HDMI cables is undesirable, or impractical.

It does so by:

* Avoiding unnecessary cabling by using modern Wireless technologies
* Leveraging the power of open source software, as free as humanly possible from proprietary vendor lock-ins.
* Being platform-agnostic and usable on different systems and eventually alternative architectures*
* Having an easy-to-use web interface, which can be used to quickly configure input options
* Targeting low-cost and easily sourced hardware platforms

<sub>* arm64 and RISC-V support is a stretch goal</sub>

Wavelet at its most basic setup is composed of five parts:

* Linux-based core server
* Wireless Access Point
* Small Network Switch supporting at least gigabit ethernet with a proper jumbo frame implementation
* An x86 decoder (decoder ARM SBC support, and hopefully RISC-V support in the future is possible)

The core components of a switch, wireless AP and server are REQUIRED.

Wavelet is implemented over several open source applications, called by system or user-level systemd units.

In its current form, It uses a set of bash modules combined with the distributed keystore system etcd to control systemd services on the encoders and decoders.   These operate in response to input from a simple web server/PHP Script running on the server.   

This control surface is accessible from any device connected via Wi-Fi, and any wavelet decoder device may be switched into UI Mode for access to this interface once provisioned.

The server by default also runs an instance of the web interface, which is useful for initial setup and configuration.

## Disclaimer:

Wavelet is designed as an APPLIANCE.   
This means that software is not supposed to be updated after installation is completed, and that the system does not connect to any networks beyond the local Wavelet Wi-Fi network.  
If control channels for software updates or internet access for livestreaming are necessary, appropriate network segmentation should be carefully considered.   
Under no circumstances should the system be deployed on a "flat" production network.  We accept no liability for any consequences of ignoring this warning.

Maintenance should be carried out on a dedicated laptop which can connect wirelessly to the system, by an individual familiar with common conventions used on this system.   
It can also be performed by connecting a monitor and input devices to the server.

Under no circumstances is the system designed to be connected to a secure production network, to be managed remotely by enterprise patching or security applications.  
Modifications and hardening will almost certainly break the system or introduce unacceptable performance and stability tradeoffs.

Should this get any traction with a large number of deployments, properly managing the system with a back-end infrastructure is something we can look in to.

The system builds upon the following projects.  Their use in this project does not imply an endorsement on the part of their authors.

(Incomplete list: If your stuff was used, and we neglected to credit you, feel free to let us know!):

* UltraGrid      -  https://github.com/CESNET/UltraGrid
* etcd           -  https://github.com/etcd-io/etcd
* Fedora CoreOS  -  https://github.com/coreos
* FFMPEG         -  https://git.ffmpeg.org/ffmpeg.git
* PipeWire       -  https://github.com/PipeWire
* ImageMagick    -  https://imagemagick.org/


## INSTALLATION

To install: ```git clone``` this repo to a linux machine with internet access.  This can be a full installation, a liveCD if you are just testing, etc.

My test lab, for instance, has a machine running with a static IP address (above .200) well out of the server DHCP range.  
This allows an engineer to ssh into the server whilst it's installing and check logs for progress.

Wavelet's installation scripts can cache the larger components in a local http server and container registry on your deployment environment.   
This results in one large sequence of downloads but will drastically reduce bandwidth requirements and decrease installation time for further deployments.

To configure the registry to cache heavy files and container layers on the deployment machine:
run: ```./build_registry.sh $(pwd)-or-full-path-to-wavelet-git $(hostname -i)-or-my-ip-address```

Then, to install the wavelet server, you can run the command below with appropriate input arguments
run: ```./install_wavelet_server.sh```

Full example:
run: ```./build_registry.sh /home/user/Downloads/wavelet 192.168.0.2```

The command below will configure wavelet with:
    pull from working/dev branch
    "labmode" to skip configuration prompts and take everything from the command line inputs
    a username password of "testlab123" for the wavelet clients
    downloading the UltraGrid continouous/dev package for newer features
    a Wi-Fi BSSID (AP MAC address) matching "77:47:..."
    a Wi-Fi PSK of "StrongPassWord1"
    Wi-Fi AP IP Address statically set to 192.168.0.100
    Wi-Fi AP username/pass set to waveletAPUser/password123
    Registry IP address set to 192.168.0.2 (same as our deployment machine)
    System gateway of 192.168.0.1

run: ```$PWD/install_wavelet_server.sh -d -l -ugd -p=testlab123 -ws=Wavelet-1 -wb=77:47 -wp=StrongPassword1 -wip=192.168.0.100 -wap=waveletAPUser -wau=password123 --domain=wavelet.allethrium -reg=192.168.0.2 -g=192.168.0.1```

To configure wavelet to pull from my armelvil test branch, add a "d" argument like so: ```./install_wavelet_server.sh -d``` - given this is still under very active experimentation, if something's broken this will get new updates I haven't pushed to the main branch.

Please note it's a good idea to have your Wi-Fi access point and switch infrastructure pre-configured.   
A stretch goal is to leverage IaaS techniques to support provisioning of some target devices as part of the installation process, but that is for the future.

The installer will download appropriate install media and customize the images appropriately after you have intelligently answered the prompts.

You can then navigate to $HOME/Downloads where the installer will have generated an ISO for the Server and Decoders (decoder image generation will soon be depreciated)

The server must be installed first and will soon support provisioning client devices directly from itself via PXE / HTTP boot.

Boot the target machine from the server ISO and allow it to run.   As long as your environment is correctly configured with the network settings you specify in the installer and has a stable internet connection, installation is completely automated.  The machine will reboot several times during the process, and once the display shows a browser window with the control console up, it is complete.

The decoders must be imaged whilst connected via ethernet to the server.  They will automatically activate Wi-Fi and disable ethernet by default once imaging is completed.   

I would recommend Ruckus/CommScope APs as their unleashed software is easy to configure and latency is good.