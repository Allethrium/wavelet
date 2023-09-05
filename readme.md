Wavelet

Wavelet is a local video appliance leveraging other projects such as UltraGrid.  It designed to provide a quick 'Pop-Up' solution for venues where running network or HDMI cables is undesirable or impractical.   

It does so by:

* Avoiding unnecessary cabling by utilizing modern Wireless technologies
* Leveraging the power of open source software, as free as humanly possible from proprietary vendor lock-ins.
* Being platform agnostic and usable on different systems and architectures
* (Eventually) Targeting low-cost hardware platforms

Wavelet at its most basic setup is composed of five components:

* Linux-based server
* (Optional) Linux-based primary encoder
* Wireless Access Point
* Small Network Switch
* An x86 decoder (ARM SBC support is possible)

More advanced setups may add additional encoders and decoders, however the core components of a switch, wireless AP and server are REQUIRED.

Wavelet is implemented over several open source applications, called by system or user-level systemd units.

In its current form, It utilizes a set of bash scripts combined with the distributed keystore system etcd to control systemd services on the encoders and decoders in response to input from a simple web server/PHP Script running on the server.   This control surface is accessible from any device connected via WiFi.

Disclaimer:

Wavelet is designed as an APPLIANCE.   This means that software is not supposed to be updated after installation is completed, and that the system
does not connect to any networks beyond the local WiFi network.  Until an appropriate network segmentation exists in the deployment environment this is unlikely to change.

Maintenance should be carried out on a dedicated laptop which can connect wirelessly to the system, by an individual familiar with common conventions used on this system.

Under no circumstances is the system designed to be connected to a secure production network, or to be managed remotely by enterprise patching or security applications.  Unauthorized modifications and hardening will almost certainly break the system or introduce unacceptable performance tradeoffs.

The system builds upon the following projects (Incomplete list - If your stuff was used and we neglected to credit, feel free to let me know!):

UltraGrid      -  https://github.com/CESNET/UltraGrid
etcd           -  https://github.com/etcd-io/etcd
Fedora CoreOS  -  https://github.com/coreos
FFMPEG         -  https://git.ffmpeg.org/ffmpeg.git
PipeWire       -  https://github.com/PipeWire
ImageMagick    -  https://imagemagick.org/
