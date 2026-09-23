# Installing Wavelet on Linux

This guide walks you through installing Wavelet using a **live USB Linux environment** as your deployment machine. This is the simplest way to get a clean, known-good environment for Wavelet's installer scripts.

The overall process:

1. Create a **bootable Linux USB stick** (a "live" environment).
2. Boot your deployment machine from it.
3. Download Wavelet, fill in a config file, and run the installer from that live environment.

> **Read the whole thing once before you start.** Wavelet is an *appliance*: once installed it is not meant to be updated, and it must **not** be plugged into your production/corporate network. See the [security note](#important-what-you-need-to-know-first) below.

---

## 1. What you need before you start

Have these ready:

- A **machine with internet access** that can boot from a USB stick — this becomes your *deployment machine*. A normal laptop or desktop works.
- A **second USB stick** (32 GB or larger) to create the live Linux environment on.
- A **server machine** to install Wavelet onto (this becomes the Wavelet server). It must be able to boot from USB or a disk image.
- **A Wi-Fi access point and a network switch** — ideally pre-configured before you begin. Wavelet's installer does *not* configure your Wi-Fi AP for you.
- **About 16 GB of free disk space** on the deployment machine (roughly 3 GB for the binary and installation files, plus about 12gb for the container layers and the local registry).
- A few values you'll need to make up yourself (pick sensible ones):
  - A **password** for the Wavelet system user accounts
  - A **Wi-Fi network name** (SSID)
  - An **IP address** for the server (static)
  - An **IP address** for the Wi-Fi access point (static)
  - The IP address of your **network gateway** (usually your router, e.g. `192.168.1.1`)

> Don't worry about the exact meaning of every term. The installer will ask for each one, and we explain it in the table below.

---

## 2. Create a live Linux USB stick

Pick a Linux distribution you're comfortable with. A good choice for this purpose is **Fedora Workstation** or **Debian Live** — both can run entirely from a live USB without installing anything.

### Download the live image

- **Fedora Workstation:** <https://fedoraproject.org/workstation/download>
- **Debian Live (GNOME desktop environment):** <https://www.debian.org/CD/live/>

You'll download a `.iso` file (around 2–3 GB).

### Write the image to a USB stick

Use a tool like [Rufus](https://rufus.ie/en/) (Windows), **BalenaEtcher** (Windows/macOS/Linux), or the `dd` command (Linux/macOS).

Example with `dd` on Linux (replace `/dev/sdX` with *your* USB device — **be careful, this erases it**):

```bash
sudo dd if=/path/to/fedora.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

> The live environment runs from RAM/USB. When you reboot later, nothing on the deployment machine itself needs to be permanently changed — you're only using this machine to prepare the Wavelet installer.

---

## 3. Boot into the live environment

1. Plug the live USB stick into the deployment machine.
2. Reboot and enter the boot menu (often `F12`, `Esc`, or `F8` — check your machine's manual) and choose **Boot from USB**.
3. Select **Try / Live** (rather than "Install") when prompted.

You'll end up at a Linux desktop. Open a **terminal** — all commands below are run there.

---

## 4. Get the Wavelet code

Open a terminal and clone the repository:

```bash
git clone https://github.com/Allethrium/wavelet
cd wavelet
```

> `git` is included by default on Fedora and Ubuntu live environments. If it isn't present, install it with `sudo dnf install git` (Fedora) or `sudo apt install git` (Ubuntu).

---

## 5. Decide: interactive prompts, or a config file

You can install Wavelet in two ways:

- **Config file (recommended if you're new):** you fill in one simple text file with your settings, and the installer reads it. Easiest to check before you run.
- **Command-line options:** you pass every setting on one long command.

Both produce the same result. This guide shows the **config file** way.

---

## 6. Create your config file

1. Copy the example config into a new file:

   ```bash
   cp wavelet_example.conf mywavelet.conf
   nano mywavelet.conf
   ```

2. Edit these lines, leaving everything else as-is:

   | Line | What it means | Example |
   |------|---------------|---------|
   | `PASSWORD=` | The login password for the Wavelet system | `PASSWORD=myStrongPassword1` |
   | `DOMAIN=` | A name for your Wavelet network. **Do not** end it in `.local`. | `DOMAIN=wavelet.mycompany` |
   | `SVR_IP=` | The static IP address for the Wavelet server | `SVR_IP=192.168.1.32` |
   | `SVR_GW=` | Your network gateway IP (usually your router) | `SVR_GW=192.168.1.1` |
   | `WIFI_SSID=` | The Wi-Fi network name your clients will connect to | `WIFI_SSID=Wavelet-1` |
   | `WIFI_BSSID=` | Part of your access point's MAC address (find it in the AP's settings page, it may also be on a label located on the device) | `WIFI_BSSID=00:01:02` |
   | `WIFI_IP_ADDR=` | The static IP address for the Wi-Fi access point | `WIFI_IP_ADDR=192.168.1.100` |
   | `WIFI_DEVICE_PASSWORD=` | The login password for your access point | `WIFI_DEVICE_PASSWORD=superGoodPassword` |
   | `WIFI_DEVICE_USER=` | The login username for your access point, we recommend you create an additional account that is not "Admin" or "Administrator" | `WIFI_DEVICE_USER=administrator` |

   Save and close the editor.

> Keep the line `WIFI_BSSID=` short — a partial MAC address is enough. The example file shows `00:01:02`.

---

## 7. Build the local download cache (recommended)

Wavelet can cache its large downloads on your deployment machine. This makes one big download now, but makes repeat installs much faster and lighter.

You'll need at least **16 GB free** (3 GB for the binary and installation files, and at least 10 GB to build the necessary container file layers and registry).

Find your machine's IP address if you don't know it:

```bash
hostname -I
```

Then run the registry build (replace `192.168.1.252` with *your* deployment machine's IP):

```bash
./build_registry.sh $(pwd) 192.168.1.252
```

Wait for it to finish. If you skip this step, the installer will download everything directly — this still works, it's just slower and will repeat each time you deploy a new Wavelet server.

---

## 8. Run the installer

```bash
./install_wavelet_server.sh -c=mywavelet.conf
```

The installer will now:

- Download the appropriate install media
- Customise it with your settings
- Generate the server disk image (ISO file) in your **Downloads** folder:
  - `wavelet_server.iso`

Wait for it to finish. The ISO will be written to `~/Downloads`.

---

## 9. Install the server

1. Write `wavelet_server.iso` to a USB stick (the same process as in step 2).
2. Boot the **server machine** from that USB stick.
3. Let it run. **It will reboot several times.** This is normal.
4. Installation is automatic as long as:
   - Your network settings are correct (the ones you put in the config file), and
   - The machine has a stable internet connection.
5. You'll know it's done when the screen shows a **browser window with the control console**.

> The server must be installed **first**. Decoder machines provision themselves from the server over the network automatically.

---

## 10. Install the decoders (clients)

Decoder machines do not need a USB stick. Once the server is up:

1. Connect each decoder machine to the Wavelet network (this requires a physical ethernet connection to the switch).
2. Boot it, allowing it to boot from the network (**PXE / UEFI HTTP boot**). This may need a one-time boot option change in the decoder's BIOS — check the system's vendor manual for "network boot" or "PXE boot".
3. Provisioning is fully automatic; the decoder system will reboot a few times and finalize by serving a stream from the Wavelet system. The process takes about seven minutes per device, and devices may be imaged concurrently.

---

## 11. You're done

Once decoders are provisioned, the system is ready to operate. See **[operation.md](operation.md)** for how to use it day-to-day.

---

## Command-line options reference

If you prefer to skip the config file, you can pass everything on the command line. Example:

```bash
./install_wavelet_server.sh \
  -p=myStrongPassword1 \
  --domain=wavelet.mycompany \
  --enablewifi \
  -ws=Wavelet-1 \
  -wb=00:01:02 \
  -wip=192.168.1.100 \
  -wp=StrongPassword1 \
  -wap=superGoodPassword \
  -wau=administrator \
  -ip=192.168.1.32 \
  -g=192.168.1.1 \
  -reg=192.168.1.252
```

The backslash `\` lets you continue the command on the next line in a terminal.

Common options:

| Option | Meaning |
|--------|---------|
| `-c=` / `--config=` | Use a config file instead of command-line options |
| `-p=` / `--password=` | Password for the Wavelet system |
| `--domain=` | Your Wavelet domain name (don't use `.local`) |
| `--enablewifi` | Enable Wi-Fi mode — **required** before any Wi-Fi option below |
| `-ws=` / `--wifissid=` | Wi-Fi network name |
| `-wb=` / `--wifibssid=` | Partial MAC of the access point |
| `-wip=` / `--wifiapip=` | Access point IP address |
| `-wp=` / `--wifipass=` | Wi-Fi password |
| `-wap=` / `--wifiappass=` | Access point login password |
| `-wau=` / `--wifiapuser=` | Access point login username |
| `-ip=` / `--serverip=` | Server static IP |
| `-g=` / `--servergateway=` | Network gateway IP |
| `-dns=` / `--serverdns=` | DNS server IP |
| `-4=` / `--ip4subnet=` | IPv4 subnet in CIDR notation (e.g. `192.168.1.0/24`) |
| `-6=` / `--ip6subnet=` | IPv6 subnet in CIDR notation |
| `-reg=` / `--localregistry=` | Local cache/registry IP (from step 7) |
| `-t=` / `--timezone=` | Timezone, e.g. `Europe/London` (default `America/New_York`) |
| `-d` / `--dev` | Pull from the development branch (for testing new features) |
| `-ugd` / `--ugdev` | Use the UltraGrid continuous build |
| `-b` / `--patched` | Use the patched UltraGrid build |
| `-h` / `--help` | Show the built-in help |

---

## Important: what you need to know first

- Wavelet is an **appliance** — software is not meant to be updated after installation.
- It only connects to the local Wavelet Wi-Fi network after installation has completed. It does **not** connect to the internet unless features such as livestreaming are required.
- **Never** plug it into a "flat" production network. Wavelet has a DHCP and DNS server built-in. These services will at best compete with existing infrastructure on your network and result in unreliable operation for both Wavelet and other devices on your network.
- If you need internet access for livestreaming, or remote management, you must segment the network yourself. Wavelet does not handle this for you.

We accept no liability for any consequences of ignoring these warnings.
