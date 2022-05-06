# HomeAssistant Supervised Installer

> This installation method is for advanced users only

## Make sure you understand [the requirements](https://github.com/home-assistant/architecture/blob/master/adr/0014-home-assistant-supervised.md)

# Install Home Assistant Supervised

This installation method provides the full Home Assistant experience on a regular operating system. This means, all components from the Home Assistant method are used, except for the Home Assistant Operating System. This system will run the Home Assistant Supervisor. The Supervisor is not just an application, it is a full appliance that manages the whole system. It will clean up, repair or reset settings to default if they no longer match expected values.

By not using the Home Assistant Operating System, the user is responsible for making sure that all required components are installed and maintained. Required components and their versions will change over time. Home Assistant Supervised is provided as-is as a foundation for community supported do-it-yourself solutions. We only accept bug reports for issues that have been reproduced on a freshly installed, fully updated Debian with no additional packages.

This method is considered advanced and should only be used if one is an expert in managing a Linux operating system, Docker and networking.

## Installation

Run the following commands as root (`su -` or `sudo su -` on machines with sudo installed):

### Install dependencies

#### Debian 

```bash
apt -i install \
  jq \
  wget \
  curl \
  udisks2 \
  libglib2.0-bin \
  network-manager \
  dbus
curl -fsSL get.docker.com | sh
```

#### Arch

```bash
pacman -S apparmor jq udisks2 networkmanager
pacman -S docker
systemctl enable docker
systemctl start docker
systemctl enable NetworkManager
systemctl start NetworkManager
systemctl stop systemd-networkd
systemctl disable systemd-networkd
```

### Install supervised

```bash
./install.sh
```

### Uninstall supervised

> Disclaimer: Some resources might be left in the system.
>             Check the `install.sh` for all details.

```bash
./uninstall.sh
```

## Supported Machine types

- generic-x86-64
- odroid-c2
- odroid-n2
- odroid-xu
- qemuarm
- qemuarm-64
- qemux86
- qemux86-64
- raspberrypi
- raspberrypi2
- raspberrypi3
- raspberrypi4
- raspberrypi3-64
- raspberrypi4-64
- tinker
- khadas-vim3

## Troubleshooting

If somethings going wrong, use `journalctl -f` to get your system logs. If you are not familiar with Linux and how you can fix issues, we recommend to use our Home Assistant OS.
