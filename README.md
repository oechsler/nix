# NixOS Config

My personal NixOS configurations using Flakes and Home-Manager.

![Preview](.github/assets/preview.png)

## Structure

```
hosts/                          # Host-specific configurations
modules/
  desktop/                      # Desktop environments (Hyprland, KDE, SDDM)
  home-manager/
    desktop/
      common/                   # Cross-WM (GTK, bookmarks, autostart, idle)
      hyprland/                 # Hyprland-specific (waybar, rofi, hyprlock, etc.)
      kde/                      # KDE-specific (Plasma, Dolphin, displays)
    programs/                   # Terminal, browsers, dev tools, apps
  programs/                     # System-level program configs
  system/                       # System modules (audio, networking, boot, ...)
sops/                           # Encrypted secrets (age)
backgrounds/                    # Wallpaper images
pictures/                       # User profile pictures
```

## Quick Start

See [docs/INSTALL.md](docs/INSTALL.md) for installation instructions.

## Configuration

All features are toggleable per host. Example:

```nix
features.server = true;          # Disables all desktop features
features.gaming.enable = false;
features.desktop.wm = "kde";     # or "hyprland"
```

See [docs/CONFIG.md](docs/CONFIG.md) for the full configuration reference including:
- Feature toggles (desktop, gaming, development, server mode, ...)
- Theme options (Catppuccin flavors, wallpapers, gaps, borders)
- Display configuration (multi-monitor, scaling, rotation)
- Font, locale, input, autostart, and more

## Usage as Flake Dependency

**Quick Start:** See [docs/QUICKSTART.md](docs/QUICKSTART.md) for a complete tutorial.

This flake exports `lib.mkHost` and `lib.mkDisko` for building NixOS systems:

```nix
# your-repo/flake.nix
{
  inputs.samuels-config.url = "github:user/nix";  # or path:/path/to/nix

  outputs = { samuels-config, ... }: {
    nixosConfigurations.my-host = samuels-config.lib.mkHost {
      hostName = "my-host";
      hostPath = ./hosts/my-host;
      serverMode = true;              # Optional: minimal server (no desktop, optimized kernel)
      extraModules = [ /* ... */ ];   # Optional: additional modules
    };

    # Optional: Declarative disk partitioning
    diskoConfigurations.my-host = samuels-config.lib.mkDisko ./hosts/my-host;
  };
}
```

**What's included:**
- Base modules (system, desktop, programs)
- Home-Manager + Catppuccin theming
- SOPS secrets, Disko, Impermanence
- CachyOS optimized kernel (server variant when `serverMode = true`)
- nix-flatpak support

**Server mode** (`serverMode = true`) automatically:
- Disables: Desktop, audio, bluetooth, WiFi, development tools, gaming
- Enables: CachyOS server-optimized kernel
- Keeps: SSH, Tailscale, basic CLI tools (git, htop, neovim, etc.)

**Disko** (`lib.mkDisko`) is optional for declarative disk partitioning:
- Include `diskoConfigurations` if you want reproducible disk layouts
- Omit it if you have existing partitions and use `hardware-configuration.nix` only
