# Quickstart

Use this flake as a reusable NixOS configuration base. Start with the
configuration reference, then override only the features that differ for your
host.

## 1. Create Flake

```nix
# flake.nix
{
  inputs.base-config.url = "github:oechsler/nix";

  outputs = { base-config, ... }: {
    nixosConfigurations.my-host = base-config.lib.mkHost {
      hostName = "my-host";
      hostPath = ./hosts/my-host;
      extraModules = [ ];   # optional additional NixOS modules
    };
  };
}
```

## 2. Create Host Config

```bash
mkdir -p hosts/my-host
```

```nix
# hosts/my-host/configuration.nix
{
  imports = [ ./hardware-configuration.nix ];

  # Use the release matching the NixOS version used for installation.
  system.stateVersion = "25.11";

  user = {
    name = "your-username";
    fullName = "Your Name";
    email = "your@email.com";
    github = "your-github";
    # password is set from sops (user/password) — no hashedPassword needed
  };
}
```

## 3. Generate Hardware Config

```bash
nixos-generate-config --show-hardware-config > hosts/my-host/hardware-configuration.nix
```

## 4. Build

```bash
nix build .#nixosConfigurations.my-host.config.system.build.toplevel
```

## Modes

- Desktop: Hyprland/KDE, LibreWolf, audio, development tools, Podman, and QEMU/KVM VMs.
- Laptop: Desktop features with laptop-specific lid and power behavior.

## SOPS Secrets

WiFi and SMB need SOPS secrets. Point the host at your encrypted file:

```nix
sops.secretsFile = ./sops/sops.encrypted.yaml;
```

Install the SSH-derived Age identity used by this repository:

```bash
sudo ./sops/setup.sh
```

Or disable features that need secrets:

```nix
features = {
  wifi.enable = false;
  smb.enable = false;
};
```

## Defaults To Review

- Impermanence: `features.impermanence.enable = true`
- LUKS encryption: `features.encryption.enable = true`
- The Btrfs subvolume layout must match the selected installation mode.

To disable:

```nix
# hosts/my-host/configuration.nix
{
  features = {
    impermanence.enable = false;
    encryption.enable = false;
  };
}
```

## Next Steps

- [CONFIG.md](CONFIG.md) - All available options
- [INSTALL.md](INSTALL.md) - Full installation guide
