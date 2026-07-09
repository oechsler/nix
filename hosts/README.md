# Hosts

Host-specific configurations.

| Host | Device | Notes |
|------|--------|-------|
| `samuels-pc` | Desktop workstation | Ryzen 9 5950X + RX 7900 XTX, dual 1440p, 2x NVMe (system + games) |
| `samuels-terra` | Desktop workstation | Ryzen 9 9950X3D + RX 9070 XT, dual 1440p, ASUS ROG Strix X870-I |
| `samuels-razer` | Razer Blade Stealth 13 (2018) | Intel i7-8550U + UHD 620, 3200×1800 HiDPI, KDE, no Secure Boot |

## Installation

See [docs/INSTALL.md](../docs/INSTALL.md) for full installation guide.

Quick install (from NixOS ISO):

```bash
curl -sL https://raw.githubusercontent.com/oechsler/nix/main/quickstart.sh | sudo bash
```

## Adding a New Host

1. Create `hosts/new-host/` with:
   - `configuration.nix` — host-specific config
   - `disko.nix` — disk layout (copy from existing, update device ID)
   - `hardware-configuration.nix` — wrapper for generated config
   - `luks.nix` — LUKS device declaration
   - `home.nix` — optional host-specific home-manager overrides (e.g. idle timeouts)

2. Add to `flake.nix`:
   ```nix
   nixosConfigurations.new-host = mkHost "new-host";
   ```

3. Find disk ID:
   ```bash
   ls -l /dev/disk/by-id/nvme-*
   ```
