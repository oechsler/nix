# NixOS Config

My personal NixOS configurations using Flakes and Home-Manager.

![Preview](.github/assets/preview.png)

## Structure

```
hosts/          # Per-host configs
modules/
  system/       # Boot, networking, impermanence, snapshots
  desktop/      # Hyprland, KDE, SDDM
  home-manager/ # User programs, dotfiles, theming
sops/           # Encrypted secrets
```

## Quick Start

- **Fresh install:** [docs/INSTALL.md](docs/INSTALL.md)
- **Use as base for your config:** [docs/QUICKSTART.md](docs/QUICKSTART.md)
- **Configuration reference:** [docs/CONFIG.md](docs/CONFIG.md)
- **Security overview:** [docs/SECURITY.md](docs/SECURITY.md)

## Features

All features are toggleable per host:

```nix
features.server = true;               # Minimal server (no desktop, optimized kernel)
features.impermanence.enable = false; # Disable root wipe on boot
features.gaming.enable = false;       # No Steam/gaming
features.desktop.wm = "kde";          # Hyprland or KDE
```

## Using as Flake Input

This flake exports `lib.mkHost` for building NixOS systems. See [docs/QUICKSTART.md](docs/QUICKSTART.md) for setup guide.
