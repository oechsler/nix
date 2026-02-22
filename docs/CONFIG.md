# Configuration Reference

## Feature Toggles

All features default to `true` (except Secure Boot, SSH, and server mode). Override per host in `configuration.nix`:

```nix
features.server = true;          # Disables all desktop-related features at once
features.gaming.enable = false;
features.desktop.wm = "kde";
features.ssh.enable = true;
```

| Toggle | Default | Description |
|--------|---------|-------------|
| `features.server` | `false` | Server mode — disables desktop, apps, audio, bluetooth, gaming, flatpak, appimage, wifi, development, virtualisation; enables cachyos-server kernel |
| `features.impermanence.enable` | `true` | Impermanent root with btrfs rollback on boot — see [System Requirements](#system-requirements) |
| `features.encryption.enable` | `true` | LUKS full disk encryption |
| `features.desktop.enable` | `true` | Desktop environment (SDDM, Firefox, theming) |
| `features.desktop.wm` | `"hyprland"` | Window manager (`"hyprland"` / `"kde"`) |
| `features.desktop.dock.enable` | `true` | Application dock for Hyprland (hypr-dock) |
| `features.audio.enable` | `true` | PipeWire audio (ALSA, PulseAudio compat) |
| `features.bluetooth.enable` | `true` | Bluetooth support (power on boot) |
| `features.gaming.enable` | `true` | Steam, GameMode, Gamescope |
| `features.virtualisation.enable` | `true` | Docker daemon + user group |
| `features.virtualisation.waydroid.enable` | `false` | Waydroid Android container |
| `features.smb.enable` | `true` | SMB network share mounts (auto-mount with retry) |
| `features.smb.shares` | `["personal-drive"]` | SMB share names (via SOPS secrets) |
| `features.flatpak.enable` | `true` | Flatpak + Flathub (Flatseal, Flatsweep) |
| `features.appimage.enable` | `true` | AppImage support + auto-watcher in ~/Applications |
| `features.tailscale.enable` | `true` | Tailscale VPN (+ trayscale tray icon on desktop) |
| `features.wifi.enable` | `true` | WiFi profiles via SOPS secrets |
| `features.wifi.networks` | `["home"]` | WiFi network names to manage — each needs `wifi/<name>/ssid` + `wifi/<name>/psk` SOPS secrets |
| `features.development.enable` | `true` | IDEs, languages (Go, Rust, Node, Java) |
| `features.development.gui.enable` | `true` | GUI dev tools (VS Code, JetBrains, DBeaver) |
| `features.development.kubernetes.enable` | `true` | Kubernetes tools (kubectl, k9s) with kubeconfig via SOPS |
| `features.apps.enable` | `true` | Desktop apps (Discord, Spotify, Obsidian, LibreOffice, ...) |
| `features.apps.winboat.enable` | `false` | WinBoat Windows VM (seamless integration) |
| `features.secureBoot.enable` | `false` | UEFI Secure Boot via lanzaboote |
| `features.ssh.enable` | `false` | OpenSSH server + GitHub key sync (every 15 min) |
| `features.snapshots.enable` | `true` | Automatic btrfs snapshots (hourly, see [SNAPSHOTS.md](SNAPSHOTS.md)) |
| `features.kernel` | `"cachyos"` | Kernel variant (`"cachyos"` / `"cachyos-lts"` / `"cachyos-server"` / `"default"`) |

## SOPS Options

Set in `configuration.nix`:

| Option | Default | Description |
|--------|---------|-------------|
| `sops.secretsFile` | `../../sops/sops.encrypted.yaml` | Path to encrypted SOPS secrets file (override for external repos) |

## User Options

Set in `configuration.nix`:

| Option | Default | Description |
|--------|---------|-------------|
| `user.name` | `"samuel"` | Primary username |
| `user.fullName` | `"Samuel Oechsler"` | Full name |
| `user.email` | `"samuel@oechsler.it"` | Email address |
| `user.github` | `"oechsler"` | GitHub username (for SSH key import) |
| `user.icon` | `pictures/sam-memoji.png` | Profile picture (SDDM) |
| `user.directories` | `[]` | Extra directories to create in `~` |

## Theme Options

Set in `configuration.nix`:

| Option | Default | Description |
|--------|---------|-------------|
| `theme.catppuccin.flavor` | `"mocha"` | `"latte"` / `"frappe"` / `"macchiato"` / `"mocha"` |
| `theme.catppuccin.accent` | `"mauve"` | Accent color (14 options: blue, flamingo, green, lavender, maroon, mauve, peach, pink, red, rosewater, sapphire, sky, teal, yellow) |
| `theme.scale` | `1.0` | DPI / monitor scale factor |
| `theme.wallpaper` | `"nix-black-4k.png"` | Wallpaper filename in archive, or path if `backgrounds.enable = false` |
| `backgrounds.enable` | `true` | Extract wallpapers from encrypted archive at boot |
| `theme.radius.small` | `6` | Border radius for small elements (progress bars) |
| `theme.radius.default` | `16` | Border radius for windows/panels/notifications |
| `theme.gaps.inner` | `8` | Gaps between windows |
| `theme.gaps.outer` | `16` | Gaps at screen edges |
| `theme.border.width` | `2` | Window border width |
| `theme.cursor.name` | auto | Cursor theme (`"Breeze_Light"` on latte, `"breeze_cursors"` otherwise) |
| `theme.cursor.package` | `kdePackages.breeze` | Cursor theme package |
| `theme.cursor.size` | `24` | Cursor size |
| `theme.icons.name` | auto | Icon theme (`"Papirus-Light"` on latte, `"Papirus-Dark"` otherwise) |
| `theme.icons.package` | Catppuccin Papirus | Icon theme package (auto-colored by flavor + accent) |

## Font Options

Set in `configuration.nix`:

| Option | Default | Description |
|--------|---------|-------------|
| `fonts.defaults.monospace` | `"JetBrainsMono Nerd Font"` | Monospace font (terminal, code editors, UI when `uiStyle = "monospace"`) |
| `fonts.defaults.sansSerif` | `"Noto Sans"` | Sans-serif font (UI when `uiStyle = "sans-serif"`) |
| `fonts.defaults.serif` | `"Noto Serif"` | Serif font (fontconfig default) |
| `fonts.defaults.uiStyle` | `"monospace"` | Font style for UI elements: `"monospace"` or `"sans-serif"` |
| `fonts.defaults.ui` | *(read-only)* | Resolved font name based on `uiStyle` — used by waybar, dunst, rofi, hyprlock, SDDM, GTK, Qt |
| `fonts.defaults.size` | `11` | Default font size for UI elements |
| `fonts.defaults.terminalSize` | `fonts.defaults.size` | Terminal (kitty) font size |

## Locale Options

Set in `configuration.nix`:

| Option | Default | Description |
|--------|---------|-------------|
| `locale.timezone` | `"Europe/Berlin"` | Timezone |
| `locale.language` | `"de_DE.UTF-8"` | System locale |
| `locale.keyboard` | `"de"` | Keyboard layout |

## Display Options

Set in `configuration.nix`. Works on both Hyprland and KDE. When `displays.monitors` is empty (the default), the system falls back to `theme.scale`.

To find your connector names, resolution and refresh rate:

```bash
# Hyprland
hyprctl monitors

# KDE / generic
kscreen-doctor -o
```

```nix
displays.monitors = [
  { name = "DP-1"; width = 2560; height = 1440; refreshRate = 165; x = 0; y = 0; }
  { name = "DP-2"; width = 2560; height = 1440; refreshRate = 165; x = 2560; y = 0; }
];
```

| Option | Default | Description |
|--------|---------|-------------|
| `displays.monitors` | `[]` | List of monitor configurations |
| `monitors.*.name` | — | Connector name (`"DP-1"`, `"HDMI-A-1"`, `"eDP-1"`) |
| `monitors.*.width` | `1920` | Horizontal resolution |
| `monitors.*.height` | `1080` | Vertical resolution |
| `monitors.*.refreshRate` | `60` | Refresh rate in Hz |
| `monitors.*.x` | `0` | Horizontal position offset |
| `monitors.*.y` | `0` | Vertical position offset |
| `monitors.*.scale` | `theme.scale` | Scale factor (defaults to `theme.scale`) |
| `monitors.*.rotation` | `"normal"` | Rotation (`"normal"` / `"90"` / `"180"` / `"270"`) |
| `monitors.*.wallpaper` | `null` | Per-monitor wallpaper (`null` = use `theme.wallpaper`) |
| `monitors.*.workspaces` | `[]` | Workspace IDs to bind to this monitor (Hyprland only, e.g. `[1 2 3 4 5]`) |

On Hyprland, a catch-all fallback rule (`preferred, auto, theme.scale`) is always added for hotplugged/unlisted monitors. On KDE, `kscreen-doctor` is run at login via an XDG autostart entry to apply the monitor layout.

## Input Options

Set in `configuration.nix`. Applied to both Hyprland and KDE.

| Option | Default | Description |
|--------|---------|-------------|
| `input.mouse.naturalScroll` | `true` | Natural (reverse) scroll direction for mice |
| `input.touchpad.naturalScroll` | `true` | Natural (reverse) scroll direction for touchpads |

On KDE, touchpad settings are detected and configured per-device at activation time.

## Autostart Apps

Set in `home.nix`:

| Option | Default | Description |
|--------|---------|-------------|
| `autostart.apps` | Bitwarden, Vesktop, CoolerControl, Beeper (+ conditional) | Apps to start on login (works on Hyprland + KDE) |

Default autostart apps are extended based on feature toggles:
- Nextcloud is added on Hyprland (KDE manages its own autostart)
- `features.apps.enable` adds Pika Backup Monitor, Spotify (Hyprland only)
- `features.development.enable` adds JetBrains Toolbox
- `features.tailscale.enable` adds Trayscale
- `features.gaming.enable` adds Steam

Each entry is `{ name = "..."; exec = "..."; }` — on KDE these generate XDG autostart `.desktop` files, on Hyprland they're launched via `exec-once`.

## File Manager Bookmarks

Set in `home.nix`:

| Option | Default | Description |
|--------|---------|-------------|
| `fileManager.bookmarks` | Downloads, Schreibtisch, Repos, Dokumente, Bilder | Sidebar bookmarks for Nautilus (Hyprland) and Dolphin (KDE) |

Each entry is `{ name = "..."; path = "/absolute/path"; icon = "folder-..."; }`. The `icon` field defaults to `"folder"`.

Bookmarks are managed declaratively — on Nautilus via GTK bookmarks (force-overwritten to prevent Nextcloud pollution), on Dolphin via `user-places.xbel`.

## Pinned Dock/Taskbar Apps

Set in `home.nix`:

| Option | Default | Description |
|--------|---------|-------------|
| `desktop.pinnedApps` | Firefox, Dolphin/Nautilus, Kitty (+ conditional) | Pinned dock/taskbar apps (works on Hyprland + KDE) |

Default pinned apps are extended based on feature toggles:
- `features.development.enable` adds VS Code
- `features.apps.enable` adds Obsidian, Vesktop, Spotify
- `features.gaming.enable` adds Steam

Each entry is a desktop file name without `.desktop` suffix (e.g. `"firefox"`).

## Idle / Power Management

Set in `home.nix`. Works on both Hyprland (via hypridle) and KDE (via PowerDevil).

| Option | Default | Description |
|--------|---------|-------------|
| `idle.timeouts.dimBattery` | `120` | Seconds until dim on battery |
| `idle.timeouts.dimAcLockBattery` | `300` | Seconds until dim on AC / lock on battery |
| `idle.timeouts.suspendBattery` | `300` | Seconds until suspend on battery |
| `idle.timeouts.lockSuspendAc` | `1800` | Seconds until lock + suspend on AC |

### Hyprland Dim Settings

| Option | Default | Description |
|--------|---------|-------------|
| `hypridle.dim.percent` | `10` | Target brightness when dimmed (%) |
| `hypridle.dim.stepPercent` | `5` | Brightness step size for smooth dimming (%) |
| `hypridle.dim.stepDelay` | `"0.05"` | Delay between dim steps in seconds |

## Impermanence

> **⚠️ Optional Feature**: Impermanence is enabled by default but can be disabled with `features.impermanence.enable = false;`.

Root filesystem (`/`) is wiped on every boot. Only explicitly declared paths in `/persist` survive. See [INSTALL.md](INSTALL.md#impermanence) for details.

## Snapshots

See [SNAPSHOTS.md](SNAPSHOTS.md) for snapshot management (restore, browse, cleanup).

## System Requirements

### Default Configuration (Opinionated)

This config is opinionated and assumes:
- **Filesystem**: BTRFS with subvolume layout (`@`, `@home`, `@nix`, `@persist`, `@snapshots`)
- **Encryption**: LUKS2 full disk encryption
- **Impermanence**: Root filesystem wiped on boot

### Disabling Features

Both impermanence and encryption can be disabled:

```nix
# Traditional persistent root (no rollback)
features.impermanence.enable = false;

# Unencrypted disk (not recommended for laptops)
features.encryption.enable = false;
```

**Note**: Disabling impermanence keeps your root filesystem persistent — state accumulates normally. Disabling encryption requires manually removing LUKS from your `disko.nix` or creating a new disk layout.

### Partition Layout Requirements

See [INSTALL.md](INSTALL.md#disk-layout) for the required partition and subvolume structure.
