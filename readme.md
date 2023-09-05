Wavelet

Wavelet is a courtroom video appliance designed to avoid shortcomings and pitfalls of prior modernization attempts.

It does so by:

* Avoiding unnecessary cabling by utilizing modern Wireless technologies
* Leveraging the power of open source software, as free as humanly possible from proprietary vendor lock-ins.
* Being platform agnostic and portable between different systems and architectures
* Targeting low-cost hardware platforms

Wavelet at its most basic setup is composed of five components:

* Linux-based server
* Linux-based primary encoder
* Standalone Wireless Access Point
* Small Network Switch
* SBC-based primary decoder

More advanced setups may add additional encoders and decoders, however the core components of a switch, wireless AP and server are REQUIRED.

Wavelet is implemented over several open source applications, containerized and called by system or user-level systemd units.

In its current form, It utilizes a set of bash scripts combined with keypair-based SSH to control systemd services on the encoders and decoders in response to input from a keystroke recorder running on the server.

Disclaimer:

Wavelet is designed as an APPLIANCE.   This means that software is not supposed to be updated after installation is completed, and that the system
does not connect to any networks beyond the local WiFi network.  Until an appropriate network segmentation exists in the deployment environment this is unlikely to change.

Maintenance should be carried out on a dedicated laptop which can connect wirelessly to the system, by an individual familiar with common conventions used on this system.

Under no circumstances is the system designed to be connected to a secure production network, or to be managed remotely by enterprise patching or security applications.  Unauthorized modifications and hardening will almost certainly break the system.