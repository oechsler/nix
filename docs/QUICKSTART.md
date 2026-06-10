# Quickstart

Use this flake as a base NixOS configuration.

## 1. Create Flake

```nix
# flake.nix
{
  inputs.base-config.url = "github:oechsler/nix";

  outputs = { base-config, ... }: {
    nixosConfigurations.my-host = base-config.lib.mkHost {
      hostName = "my-host";
      hostPath = ./hosts/my-host;
      serverMode = true;    # false for desktop
      extraModules = [ ];   # optional: additional NixOS modules
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

- Server: Fish, Git, Neovim, optional SSH/Tailscale.
- Desktop: server base plus Hyprland/KDE, Firefox, audio, development tools, Docker.

## SOPS Secrets

WiFi and SMB need SOPS secrets. Point the host at your encrypted file:

```nix
sops.secretsFile = ./sops/sops.encrypted.yaml;
```

Create the age key and install it on the target machine:

```bash
age-keygen -o sops/age.key
sudo mkdir -p /var/lib/sops/age
sudo cp sops/age.key /var/lib/sops/age/keys.txt
```

Or disable features that need secrets:

```nix
features.wifi.enable = false;
features.smb.enable = false;
features.development.kubernetes.enable = false;
```

## Defaults To Review

- Impermanence: `features.impermanence.enable = true`
- LUKS encryption: `features.encryption.enable = true`
- BTRFS subvolumes: `@`, `@home`, `@nix`, `@persist`, `@snapshots`

To disable:

```nix
# hosts/my-host/configuration.nix
{
  features.impermanence.enable = false;
  features.encryption.enable = false;
}
```

## Next Steps

- [CONFIG.md](CONFIG.md) - All available options
- [INSTALL.md](INSTALL.md) - Full installation guide
