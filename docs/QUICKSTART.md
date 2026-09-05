# Quickstart

Use this guide to create a small host configuration based on the reusable NixOS
flake. It is for users who already have a NixOS environment and want to define
a new host. For a fresh machine, use the [installation guide](INSTALL.md).

## Before You Start

- A working Nix installation with flakes enabled
- This repository or a repository that imports it as a flake input
- A host directory containing the generated hardware configuration
- An encrypted SOPS file when WiFi, SMB, or authentication secrets are enabled

Read [CONFIG.md](CONFIG.md) when you need to change defaults or select optional
features.

## Create Flake

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

## Create Host Config

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

## Generate Hardware Config

```bash
nixos-generate-config --show-hardware-config > hosts/my-host/hardware-configuration.nix
```

## Build and Apply

```bash
nix build .#nixosConfigurations.my-host.config.system.build.toplevel

# Apply the evaluated configuration
sudo nixos-rebuild switch --flake .#my-host
```

## Host Modes

- Desktop: Hyprland/KDE, LibreWolf, audio, development tools, Podman, and QEMU/KVM VMs.
- Laptop: Desktop features with laptop-specific lid and power behavior.

## Secrets

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

## Important Defaults

- Impermanence: `features.impermanence.enable = true`
- LUKS encryption: `features.encryption.enable = true`
- The main-disk layout is generated from the selected feature settings.

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
