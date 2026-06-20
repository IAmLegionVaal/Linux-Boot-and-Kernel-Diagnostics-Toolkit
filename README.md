# Linux Boot and Kernel Diagnostics Toolkit

A read-only Bash toolkit for investigating slow boots, failed units, kernel warnings, driver problems, initramfs issues, GRUB context, firmware messages, and previous-boot failures.

## Checks performed

- Distribution, kernel, uptime, boot ID, and kernel command line
- `systemd-analyze` time, blame, and critical-chain evidence
- Failed units and boot targets
- Current and previous boot errors
- Kernel warnings, taint state, loaded modules, and module failures
- Initramfs and GRUB file inventory
- Firmware, ACPI, storage, network-driver, and out-of-memory indicators
- Boot history from `journalctl --list-boots`
- Text, CSV, and JSON reports

## Usage

```bash
chmod +x src/boot_kernel_diagnostics.sh
sudo ./src/boot_kernel_diagnostics.sh
```

Review a wider log window:

```bash
sudo ./src/boot_kernel_diagnostics.sh --hours 72 --output /tmp/boot-diagnostics
```

## Safety

The toolkit does not rebuild initramfs, update GRUB, load or unload modules, change kernel parameters, edit bootloader files, or reboot the host.

## Requirements

- Bash 4+
- A `systemd`-based Linux distribution for complete boot timing evidence
- Root privileges for complete kernel and journal access

## Validation ideas

- Healthy boot
- Failed service during startup
- Slow startup unit
- Previous boot with kernel errors
- Missing driver or firmware warning
- Non-systemd host to confirm graceful degradation

## Author

Dewald Pretorius — L2 IT Support Engineer
