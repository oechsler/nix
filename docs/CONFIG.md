# Configuration Reference

## Feature Toggles

Most desktop-oriented features default to enabled. Some toggles inherit their parent feature, and opt-in features default to disabled. Override per host in `configuration.nix`:

```nix
features.server = true;          # Disables all desktop-related features at once
features.gaming.enable = false;
features.gaming.steamMachine.enable = true;
features.desktop.wm = "kde";
features.desktop.fileManager = "terminal";
features.ssh.enable = true;
```

| Toggle | Default | Description |
|--------|---------|-------------|
| `features.server` | `false` | Server mode — disables desktop, apps, audio, bluetooth, gaming, flatpak, appimage, wifi, development, virtualisation; enables cachyos-server kernel |
| `features.impermanence.enable` | `true` | Impermanent root with btrfs rollback on boot — see [System Requirements](#system-requirements) |
| `features.impermanence.extraPaths` | `[]` | Additional paths to persist (beyond feature-based defaults) |
| `features.encryption.enable` | `true` | LUKS full disk encryption |
| `features.encryption.unlockMethod` | `"tpm2"` | How LUKS is unlocked at boot: `"tpm2"`, `"yubikey"`, `"password"`. `"yubikey"` auto-enables `auth.yubikey.enable`. |
| `features.desktop.enable` | `true` | Desktop environment (SDDM, Firefox, theming) |
| `features.desktop.wm` | `"hyprland"` | Window manager (`"hyprland"` / `"kde"`) |
| `features.desktop.login` | `"greeter"` | How the desktop session is entered: `"greeter"` (SDDM login) or `"autologin"`. Autologin only auto-unlocks the keyring with `unlockMethod = "password"`. |
| `features.desktop.fileManager` | `"default"` | Primary file manager: `"default"` uses Nautilus (Hyprland) or Dolphin (KDE); `"terminal"` uses Yazi in Kitty and removes the GUI file manager from pinned apps. |
| `features.audio.enable` | `true` | PipeWire audio (ALSA, PulseAudio compat) |
| `features.bluetooth.enable` | `true` | Bluetooth support (power on boot) |
| `features.gaming.enable` | `true` | Steam + Proton-GE, GameMode, Gamescope, MangoHud, ProtonUp-Qt |
| `features.gaming.steamMachine.enable` | `false` | Adds a Steam Gamescope session to SDDM for hybrid desktop/Steam Machine use. |
| `features.hardware.cpu` | `null` | CPU vendor (`"amd"` / `"intel"`) — enables the correct microcode update package loaded at early boot (security patches from AMD/Intel). |
| `features.hardware.gpu` | `null` | GPU vendor (`"amd"` / `"intel"`) — enables graphics support and VA-API hardware decoding for all contexts (browser, video players). AMD also gets 32-bit libs when `gaming.enable = true`. **NVIDIA is not supported** — the enum only accepts `"amd"` and `"intel"`. |
| `features.ipv6PrivacyExtensions.enable` | `!server` | IPv6 privacy extensions for NetworkManager profiles |
| `features.virtualisation.enable` | `true` | Docker daemon + user group |
| `features.smb.enable` | `true` | SMB network share mounts (auto-mount with retry) |
| `features.smb.shares` | `[]` | SMB shares to mount — list of `{ name, label, path, username? }`. `username` defaults to `config.user.name`. Only `smb/<name>/password` needs a SOPS secret. |
| `features.flatpak.enable` | `true` | Flatpak + Flathub (Flatseal, Flatsweep) |
| `features.appimage.enable` | `true` | AppImage support + auto-watcher in ~/Applications |
| `features.tailscale.enable` | `true` | Tailscale VPN (+ trayscale tray icon on desktop) |
| `features.wifi.enable` | `true` | WiFi profiles via SOPS secrets |
| `features.wifi.networks` | `[]` | WPA2-PSK networks — list of `{ name, ssid }`. Only `wifi/<name>/psk` needs a SOPS secret. |
| `features.wifi.enterpriseNetworks` | `[]` | WPA2 Enterprise (EAP-PEAP) networks — list of `{ name, ssid, identity }`. Only `wifi/<name>/password` needs a SOPS secret. |
| `features.development.enable` | `true` | Languages, CLI dev tools, Kubernetes tools, desktop IDEs on desktop hosts |
| `features.apps.enable` | `true` | Desktop apps (Discord, Spotify, Obsidian, LibreOffice, ...) |
| `features.apps.winboat.enable` | `false` | WinBoat Windows VM (seamless integration) |
| `features.auth.totp.enable` | `true` | TOTP for sudo, SSH (see [AUTH.md](AUTH.md)) |
| `features.auth.yubikey.enable` | `unlockMethod == "yubikey"` | YubiKey for sudo, SSH (see [AUTH.md](AUTH.md)). Auto-enabled when `encryption.unlockMethod = "yubikey"`. |
| `features.secureBoot.enable` | `false` | UEFI Secure Boot via lanzaboote |
| `features.ssh.enable` | `false` | OpenSSH server + GitHub key sync (every 15 min) |
| `features.snapshots.enable` | `true` | Automatic btrfs snapshots (hourly, see [SNAPSHOTS.md](SNAPSHOTS.md)) |
| `features.kernel` | `"cachyos"` | Kernel variant: `"cachyos"` (x86_64-v3, latest) / `"cachyos-v3"` (explicit x86_64-v3) / `"cachyos-v4"` (x86_64-v4, Zen 4+) / `"cachyos-lts"` / `"cachyos-server"` / `"default"` (NixOS stock) |

## SOPS Options

Set in `configuration.nix`:

| Option | Default | Description |
|--------|---------|-------------|
| `sops.secretsFile` | `../../sops/sops.encrypted.yaml` | Path to encrypted SOPS secrets file (override for external repos) |

## Networking Policy

- NetworkManager owns IP configuration and routing.
- `iwd` handles WiFi authentication only.
- Docker/Tailscale interfaces are unmanaged in NetworkManager: `docker0`, `br-*`, `veth*`, `tailscale0`.
- Desktop hosts disable IPv6 only on Docker bridge/veth interfaces to reduce local development link churn; server hosts leave Docker untouched.
- LLMNR is disabled in `systemd-resolved` to avoid resolver scopes on Docker/veth links.
- Desktop Ethernet disables WiFi autoconnect while active.
- IPv6 privacy extensions default to enabled, except in server mode.

## User Options

Set in `configuration.nix`:

| Option | Default | Description |
|--------|---------|-------------|
| `user.name` | `"samuel"` | Primary username |
| `user.fullName` | `"Samuel Oechsler"` | Full name |
| `user.email` | `"samuel@oechsler.it"` | Email address |
| `user.github` | `"oechsler"` | GitHub username (for SSH key import) |
| `user.icon` | `pictures/sam-memoji.png` | Profile picture (SDDM) |
| `user.hashedPassword` | `"!"` (locked) | Password is set at boot from sops (`user/password`). Can be overridden per-host with a hash (`mkpasswd -m yescrypt`). |
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

Set in `configuration.nix`. Works on both Hyprland and KDE. When `displays.monitors` is empty, the system falls back to automatic layout detection and `theme.scale`.

To find your connector names, resolution and refresh rate:

```bash
# Hyprland
hyprctl monitors

# KDE / generic
kscreen-doctor -o
```

```nix
displays.defaults = {
  vrr = 2;                     # Hotplug/unlisted default: 0=off, 1=always, 2=fullscreen/automatic
  hdr = true;                  # Treat hotplug/unlisted outputs as HDR-capable where supported
};

displays.monitors = [
  { name = "DP-1"; width = 2560; height = 1440; refreshRate = 165; x = 0; y = 0; vrr = 2; hdr = true; }
  { name = "DP-2"; width = 2560; height = 1440; refreshRate = 165; x = 2560; y = 0; vrr = 2; hdr = true; }
];
```

| Option | Default | Description |
|--------|---------|-------------|
| `displays.defaults.vrr` | `2` | Default VRR mode for hotplugged/unlisted monitors where output-independent defaults are supported: `0` off, `1` always, `2` fullscreen/automatic |
| `displays.defaults.hdr` | `true` | Default HDR capability for hotplugged/unlisted monitors where output-independent defaults are supported |
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
| `monitors.*.vrr` | `0` | Explicit VRR mode for this monitor: `0` off, `1` always, `2` fullscreen/automatic |
| `monitors.*.hdr` | `false` | Explicit HDR capability for this monitor |
| `monitors.*.hdrSdrMaxLuminance` | `450` | SDR white level in nits for HDR conversion on this monitor |

Default behavior and limitations:

- Steam Machine/Gamescope uses `displays.defaults.vrr` and `displays.defaults.hdr` as session-wide fallbacks, so a Steam session can enable adaptive sync and HDR even when the connected output is not listed in `displays.monitors`. It does not override Gamescope color management, virtual white, SDR brightness, or gamut behavior.
- Hyprland uses `displays.defaults.vrr` for its global VRR mode, so hotplugged/unlisted monitors get VRR behavior by default.
- Hyprland enables color management when either a listed monitor has HDR or `displays.defaults.hdr = true`; full per-output HDR metadata (`bitdepth`, `cm`, SDR luminance) still requires a listed monitor because Hyprland's `monitorv2` configuration is output-specific.
- KDE applies HDR/VRR through `kscreen-doctor`, which needs concrete output names. HDR is enabled with the configured SDR brightness, but without overriding color profile or wide-gamut behavior.
- SDDM applies layout and VRR only; HDR is intentionally left off in the greeter so Game Mode and desktop sessions initialize HDR themselves.
- Set `displays.defaults.hdr = false` on hosts that commonly connect SDR-only projectors/TVs and should not advertise HDR by default.

On Hyprland, a catch-all fallback rule (`preferred, auto, theme.scale`) is always added for hotplugged/unlisted monitors. On KDE, `kscreen-doctor` is run at login via an XDG autostart entry to apply the monitor layout for known outputs.

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
| `autostart.apps` | Proton Pass, Vesktop, CoolerControl (+ conditional) | Apps to start on login (works on Hyprland + KDE) |

Default autostart apps are extended based on feature toggles:
- Nextcloud is always added (via XDG autostart `.desktop` — works on both Hyprland and KDE)
- `features.apps.enable` adds Proton Pass, Vesktop, Nheko, Mumble
- `features.gaming.enable` adds Steam
- `features.tailscale.enable` adds Trayscale

Each entry is `{ name = "..."; exec = "..."; }` — on KDE these generate XDG autostart `.desktop` files, on Hyprland they're launched via `exec-once`.

## File Manager

`features.desktop.fileManager` controls the primary file manager integration:

| Value | Behavior |
|-------|----------|
| `"default"` | Use the desktop's GUI file manager: Nautilus on Hyprland, Dolphin on KDE. |
| `"terminal"` | Use Yazi as the primary file manager. Hyprland `Super+E` and KDE `Meta+E` open `kitty yazi`; directory MIME defaults point to `yazi.desktop`; the GUI file manager is omitted from dock/taskbar pins. |

Yazi integrations follow existing feature toggles instead of adding yazi-specific toggles. Heavy preview integrations are only enabled when the corresponding app/development feature is enabled.

## File Manager Bookmarks

Set in `home.nix`:

| Option | Default | Description |
|--------|---------|-------------|
| `fileManager.bookmarks` | Downloads, Schreibtisch, Repos, Dokumente, Bilder | Sidebar bookmarks for Nautilus (Hyprland), Dolphin (KDE), and Yazi shortcuts |

Each entry is `{ name = "..."; path = "/absolute/path"; icon = "folder-..."; }`. The `icon` field defaults to `"folder"`.

Bookmarks are managed declaratively — on Nautilus via GTK bookmarks, on Dolphin via `user-places.xbel`, and on Yazi as `g1`, `g2`, ... shortcuts.

## Pinned Dock/Taskbar Apps

Set in `home.nix`:

| Option | Default | Description |
|--------|---------|-------------|
| `desktop.pinnedApps` | Firefox, Kitty, Dolphin/Nautilus or Yazi (+ conditional) | Pinned dock/taskbar apps (works on Hyprland + KDE). Yazi replaces Dolphin/Nautilus when `features.desktop.fileManager = "terminal"`. |

Default pinned apps are extended based on feature toggles:
- `features.development.enable` adds Neovim
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

Root (`/`) is wiped on every boot when `features.impermanence.enable = true`. Only declared `/persist` paths survive. See [INSTALL.md](INSTALL.md#impermanence).

## Snapshots

See [SNAPSHOTS.md](SNAPSHOTS.md) for snapshot management (restore, browse, cleanup).

## System Requirements

### Defaults

- BTRFS subvolumes: `@` (root), `@home` (/home), `@nix` (/nix), `@snapshots` (snapshot target)
- `@persist` (/persist) — required when `features.impermanence.enable = true` (the default)
- LUKS2 full disk encryption
- Impermanent root filesystem

### Disabling Features

Both impermanence and encryption can be disabled:

```nix
# Traditional persistent root (no rollback)
features.impermanence.enable = false;

# Unencrypted disk (not recommended for laptops)
features.encryption.enable = false;
```

Disabling encryption requires a matching non-LUKS disk layout.

### Partition Layout Requirements

See [INSTALL.md](INSTALL.md#disk-layout) for the required partition and subvolume structure.
