# Quickstart: Using this Config as Base

Use this NixOS configuration as foundation for your own systems.

## 1. Create Flake

```nix
# flake.nix
{
  inputs.base-config.url = "github:oechsler/nix";

  outputs = { base-config, ... }: {
    nixosConfigurations.my-host = base-config.lib.mkHost {
      hostName = "my-host";
      hostPath = ./hosts/my-host;
      serverMode = true;  # false for desktop
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
    hashedPassword = "your-hashed-password";  # Generate: mkpasswd -m sha-512
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

## What You Get

**Server mode:** Fish, Git, Neovim, Docker, SSH (optional), Tailscale (optional)

**Desktop mode:** Everything from server + Hyprland/KDE, Firefox, Audio, Development tools

## Next Steps

- [CONFIG.md](CONFIG.md) - All available options
- [INSTALL.md](INSTALL.md) - Full installation guide
