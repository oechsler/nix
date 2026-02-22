# Quickstart: Using this Config in External Repos

This guide shows how to use this NixOS configuration as a base for your own systems (servers, laptops, VMs, etc.).

## 1. Create Your Flake

```nix
# flake.nix
{
  description = "My NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # This config as base
    base-config = {
      url = "github:user/nix";  # Replace with actual repo
      # url = "path:/path/to/nix";  # Or use local path during development
    };
  };

  outputs = { nixpkgs, base-config, ... }:
    let
      # Wrapper functions for convenience
      mkHost = hostName: base-config.lib.mkHost {
        inherit hostName;
        hostPath = ./hosts/${hostName};
        serverMode = true;  # Change to false for desktop systems
      };

      mkDisko = hostName: base-config.lib.mkDisko ./hosts/${hostName};
    in {
      nixosConfigurations = {
        my-server = mkHost "my-server";
        # Add more hosts here
      };

      # Optional: Only if using declarative disk partitioning
      diskoConfigurations = {
        my-server = mkDisko "my-server";
      };
    };
}
```

## 2. Create Host Directory Structure

```bash
mkdir -p hosts/my-server
```

**Note:** You can optionally create `hosts/my-server/home.nix` for host-specific Home Manager configuration (e.g., different idle timeouts per machine). Basic values like username and stateVersion are set automatically.

## 3. Create Host Configuration

```nix
# hosts/my-server/configuration.nix
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    # ./disko.nix  # Optional: only if using declarative partitioning
  ];

  # System version (adjust to your NixOS version)
  system.stateVersion = "24.11";

  # User configuration (REQUIRED - adjust these!)
  user = {
    name = "your-username";
    fullName = "Your Full Name";
    email = "your@email.com";
    github = "your-github-username";  # For SSH key import
  };

  # Feature toggles (optional)
  features = {
    ssh.enable = true;        # SSH server with GitHub key sync
    tailscale.enable = true;  # Tailscale VPN
    # kernel = "cachyos-server";  # Already set by serverMode = true
  };

  # Home-Manager user configuration (optional)
  # Basic values (username, homeDirectory, stateVersion) are set automatically.
  # Only needed for user-specific overrides like Git config, packages, etc.
  home-manager.users.your-username = {
    # Git config
    programs.git = {
      userName = "Your Name";
      userEmail = "your@email.com";
    };
  };

  # Add your custom configuration here
  # services.nginx.enable = true;
  # ...
}
```

## 4. Generate Hardware Configuration

On the target machine:

```bash
# Generate hardware-configuration.nix
nixos-generate-config --show-hardware-config > hardware-configuration.nix
```

Copy this file to `hosts/my-server/hardware-configuration.nix`.

## 5. Optional: Create Disko Configuration

Only if you want declarative disk partitioning:

```nix
# hosts/my-server/disko.nix
{
  disko.devices = {
    disk.main = {
      device = "/dev/sda";  # Adjust to your disk
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
```

## 6. Build and Deploy

### Local build (testing):

```bash
nix build .#nixosConfigurations.my-server.config.system.build.toplevel
```

### Deploy to remote host:

```bash
nixos-rebuild switch --flake .#my-server --target-host my-server --use-remote-sudo
```

### Deploy with disko (fresh install):

```bash
# Partition disks
nix run github:nix-community/disko -- --mode disko --flake .#my-server

# Install NixOS
nixos-install --flake .#my-server
```

## What You Get

### Server Mode (`serverMode = true`)

**Installed:**
- Fish shell, Git, GitHub CLI, Neovim, Tmux
- Basic CLI tools: fd, jq, ripgrep, htop
- NetworkManager (Ethernet only)
- SSH (optional, via `features.ssh.enable`)
- Tailscale VPN (optional, via `features.tailscale.enable`)
- CachyOS server-optimized kernel
- SOPS secrets management
- Catppuccin theming (base)

**NOT installed:**
- Desktop environment (Hyprland/KDE)
- Audio, Bluetooth, WiFi
- Development tools (languages, kubectl, etc.)
- GUI apps
- Gaming

### Desktop Mode (`serverMode = false`)

Everything from server mode plus:
- Hyprland or KDE desktop environment
- Audio (PipeWire), Bluetooth, WiFi
- Firefox, GUI file manager
- Development tools (optional, via `features.development.enable`)
- GUI apps (optional, via `features.apps.enable`)

## Customization

### Override Features

```nix
# In hosts/my-server/configuration.nix
features = {
  server = true;              # Base: minimal server
  development.enable = true;  # Add: dev tools (languages, kubectl)
  wifi.enable = true;         # Add: WiFi support
};
```

### Add Custom Modules

```nix
# In flake.nix
mkHost = hostName: base-config.lib.mkHost {
  inherit hostName;
  hostPath = ./hosts/${hostName};
  serverMode = true;
  extraModules = [
    ./modules/my-custom-module.nix
  ];
};
```

### Override Packages

```nix
# In hosts/my-server/configuration.nix
home-manager.users.your-username = {
  home.packages = with pkgs; [
    htop
    ncdu
    # ... your packages
  ];
};
```

## Next Steps

- Read [CONFIG.md](CONFIG.md) for all available options
- Check [INSTALL.md](INSTALL.md) for detailed installation instructions
- Explore the [modules/](../modules/) directory to see what's available

## Troubleshooting

### Build fails with "hypr-dock not found"

This is expected - `hypr-dock` is only available in the base repo. External repos don't get this package.

### SSH keys not syncing

Make sure:
- `features.ssh.enable = true`
- `user.github = "your-github-username"` is correct
- Your GitHub account has SSH keys added

### Secrets not working

This config uses SOPS for secrets. You'll need to:
1. Set up your own SOPS secrets (see base repo's `sops/` directory for examples)
2. Or remove SOPS-dependent features (WiFi profiles, etc.)
