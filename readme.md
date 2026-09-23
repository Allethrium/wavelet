# Wavelet

Wavelet is a **local low-latency video appliance**.

It provides a quick "Pop-Up" solution for low-latency video transmission at venues where running network or HDMI cables is undesirable or impractical.

- Avoids unnecessary cabling by using modern wireless technologies
- Having an easy-to-use web interface for quick input configuration
- Leverages open source software, as free as humanly possible from proprietary vendor lock-ins
- Targeting low-cost and easily sourced hardware platforms*

<sub>* arm64 and potential RISC-V support is a stretch goal</sub>

## What's in a Wavelet system?

Wavelet is built from five parts:

1. **Linux-based core server**
2. **Wireless Access Point**
3. **Small network switch** (gigabit ethernet with proper jumbo-frame support)
4. **Decoder** (x86)
5. **Encoder Devices** (the source you're sending)

The core components of a switch, wireless AP and server are **required**.

The server runs a set of bash modules and the distributed keystore **etcd** to control systemd services on the encoders and decoders. These respond to input from a web interface running on the server. The control surface is reachable from any device connected to the local Wavelet network, and any decoder can be switched into UI Mode to access that interface.

## Documentation

- **[Installation — Linux](installation-linux.md)** — setup guide for deploying from a Linux machine or live USB environment.
- **[Operation](operation.md)** — a short, quick reference for operating Wavelet at a venue.

## Security & deployment notice

Wavelet is designed as an **appliance**:

- **Never deploy Wavelet on a "flat" production network.** We accept no liability for any consequences of ignoring this warning.
- Software is not intended to be updated after installation.
- The system does not connect to any network beyond the local Wavelet Wi-Fi.
- Maintenance should be done from a dedicated laptop connected wirelessly to the system, by someone familiar with this system's conventions (or via a monitor and keyboard attached to the server).
- If control channels for software updates, or internet access for livestreaming, are required; use appropriate network segmentation and security appliances.

## Built on open source

Wavelet builds upon the following projects. Their use does not imply endorsement by their authors.

*(Incomplete list — if your work is used and we forgot to credit you, let us know!)*

- [UltraGrid](https://github.com/CESNET/UltraGrid)
- [etcd](https://github.com/etcd-io/etcd)
- [Fedora CoreOS](https://github.com/coreos)
- [FFmpeg](https://git.ffmpeg.org/ffmpeg.git)
- [PipeWire](https://github.com/PipeWire)
- [ImageMagick](https://imagemagick.org/)
- [NDI (VIDEZ)](https://ndi.video/)

## License

[LICENSE.md](LICENSE.md)
