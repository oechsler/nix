# Hosts

Host-specific configurations.

| Host | Device | Notes |
|------|--------|-------|
| `samuels-pc` | Desktop | 2x NVMe (system + games), NVIDIA GPU |
| `samuels-razer` | Razer Blade 14 | Laptop, single NVMe |

## Installation

See [docs/INSTALL.md](../docs/INSTALL.md) for full installation guide.

Quick install:
```bash
echo "your-password" > /tmp/luks-password
./install.sh -h HOST -s /path/to/ssh-key -y
```

## Adding a New Host

1. Create `hosts/new-host/` with:
   - `configuration.nix` - host-specific config
   - `disko.nix` - disk layout (copy from existing, update device ID)
   - `home.nix` - home-manager config
   - `hardware-configuration.nix` - wrapper for generated config

2. Add to `flake.nix`:
   ```nix
   nixosConfigurations.new-host = mkHost "new-host";
   ```

3. Find disk ID:
   ```bash
   ls -l /dev/disk/by-id/nvme-*
   ```
