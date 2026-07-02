# Boot to Windows

Small desktop launcher for rebooting a Linux dual-boot machine into Windows.

Install for the current user:

```sh
./install.sh
```

The launcher installs into the application menu as **Boot to Windows**. During
installation it may ask for administrator authentication once to install a
root-owned helper and a polkit rule. After that, clicking the desktop launcher
does not ask for a password.

To install only the user launcher and keep the old password prompt behavior:

```sh
./install.sh --no-polkit
```

Before rebooting, you can inspect what method will be used:

```sh
~/.local/bin/boot-to-windows --dry-run
```

Detection order:

1. `systemctl reboot --boot-loader-entry=...` for systemd-boot entries such as `auto-windows`.
2. UEFI `BootNext` through `efibootmgr`, followed by `systemctl reboot`.
3. `grub-reboot` for a detected Windows GRUB menu entry, followed by `systemctl reboot`.

Overrides:

```sh
BOOT_TO_WINDOWS_ENTRY=auto-windows boot-to-windows
BOOT_TO_WINDOWS_GRUB_ENTRY="Windows Boot Manager" boot-to-windows
```
