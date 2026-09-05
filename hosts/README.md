# Hosts

Host-specific configurations. Installation and disk-layout procedures are
documented in [docs/INSTALL.md](../docs/INSTALL.md); this file only summarizes
the host variants.

| Host            | Device                        | Notes                                                               |
| --------------- | ----------------------------- | ------------------------------------------------------------------- |
| `samuels-terra` | Desktop workstation           | Ryzen 9 9950X3D + RX 9070 XT, dual 1440p, ASUS ROG Strix X870-I     |
| `samuels-ser9`  | Beelink SER9 Mini PC          | Headless Ollama server, SSH administration, Secure Boot + TPM2 LUKS |
| `samuels-razer` | Razer Blade Stealth 13 (2018) | Intel i7-8550U + UHD 620, 3200×1800 HiDPI, KDE, no Secure Boot      |

## Installation

Follow the authoritative [installation guide](../docs/INSTALL.md).

## Adding a New Host

The local flake discovers every directory below `hosts/` and creates the
corresponding `nixosConfigurations.<name>` automatically. No host entry needs
to be added to `flake.nix`; the shared main-disk layout is included by the host
configuration.

1. Create `hosts/new-host/` with:
   - `configuration.nix` — host-specific config
   - `disko.nix` — main-disk device ID; the shared layout is automatic
   - `hardware-configuration.nix` — wrapper for generated config
   - `home.nix` — optional host-specific home-manager overrides (e.g. idle timeouts)

   `disko.nix` contains destructive partitioning assumptions. Review the
   target device ID before running the installer. The main layout is shared
   and generated from the host features.

2. Generate the hardware configuration:

   ```bash
   nixos-generate-config --show-hardware-config > hosts/new-host/hardware-configuration.nix
   ```

3. Find and verify the disk ID before using it in Disko:

   ```bash
   ls -l /dev/disk/by-id/nvme-*
   ```

4. Build the new host:

   ```bash
    nix build .#nixosConfigurations.new-host.config.system.build.toplevel
   ```

Additional physical disks belong in the host's `disko.nix`, using the shared
`additionalDisk` helper. It partitions, optionally encrypts, formats, and mounts
the disk. See [INSTALL.md](../docs/INSTALL.md#additional-disks) for examples.

When using this repository as a flake input from another repository, use the
exported `lib.mkHost` function instead. See [docs/QUICKSTART.md](../docs/QUICKSTART.md).
