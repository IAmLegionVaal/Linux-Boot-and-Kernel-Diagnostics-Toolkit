# Linux Boot and Kernel Diagnostics Toolkit

A Linux support toolkit for investigating boot and kernel problems and applying selected guarded repairs.

## Diagnostic script

```bash
chmod +x src/boot_kernel_diagnostics.sh
sudo ./src/boot_kernel_diagnostics.sh
```

The diagnostic script collects boot timing, failed units, kernel warnings, loaded modules, initramfs and GRUB context, firmware messages and previous-boot errors.

## Repair script

Preview a repair:

```bash
chmod +x src/boot_kernel_repair.sh
sudo ./src/boot_kernel_repair.sh --rebuild-initramfs --dry-run
```

Rebuild initramfs images:

```bash
sudo ./src/boot_kernel_repair.sh --rebuild-initramfs
```

Regenerate GRUB configuration:

```bash
sudo ./src/boot_kernel_repair.sh --update-bootloader
```

Repair one boot-related service:

```bash
sudo ./src/boot_kernel_repair.sh --service NetworkManager-wait-online.service
```

Enable and start the selected service while repairing it:

```bash
sudo ./src/boot_kernel_repair.sh \
  --service example.service \
  --enable-service
```

## What the repair does

- Clears stale failed-unit state.
- Reloads systemd and repairs one selected boot-related service.
- Rebuilds initramfs using the installed distribution tool.
- Regenerates GRUB using the installed distribution tool and detected configuration path.
- Captures boot, kernel, service and `/boot` state before and after repair.
- Backs up `/etc/default/grub` when present.
- Supports dry-run, confirmation prompts, logs and clear exit codes.

## Safety and limitations

Initramfs and bootloader repairs can affect the next boot. Maintain console or recovery access and verify backups before use. The tool does not change kernel command-line parameters, remove kernels, install drivers or reboot automatically.

## Author

Dewald Pretorius — L2 IT Support Engineer
