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
