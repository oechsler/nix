# Configuration Reference
This document describes the commonly used public configuration interface. It
focuses on reusable options and defaults; host-specific values belong in host
modules.

## Feature Toggles

Most desktop-oriented features default to enabled. Child features usually
inherit their parent switch and can be overridden independently. Group related
overrides in `configuration.nix`:

```nix
features = {
  hardware = {
    formFactor = "laptop";
    cpu = "intel";
    gpu = "intel";
  };

  desktop = {
    wm = "kde";
    login = "greeter";
    browser = {
      type = "firefox";
      newTabPage = "https://dash.example.com";
      searchEngine = "ddg";
      cookieAllowlist = [ "https://example.org" ];
    };
  };

  encryption.unlockMethod = "tpm2";
  gaming.enable = false;
  dev.enable = true;
  virtualisation.vm.enable = false;
};
```

### Hardware & Boot

These options describe the machine and the guarantees required before
userspace configuration starts. Hardware values are normally host-specific;
the remaining options control boot-time storage and persistence.

| Option | Default | Description |
|--------|---------|-------------|
| `features.hardware.formFactor` | `"desktop"` | Machine form factor: `"desktop"` or `"laptop"`. |
| `features.hardware.cpu` | `null` | CPU vendor: `"amd"` or `"intel"`; selects microcode. |
| `features.hardware.gpu` | `null` | GPU vendor: `"amd"` or `"intel"`; selects graphics and VA-API support. |
| `features.kernel` | `"cachyos"` | Kernel variant, such as `"cachyos-v3"`, `"cachyos-v4"`, `"cachyos-lts"`, `"default"`, or `"default-lts"`. |
| `features.encryption.enable` | `true` | LUKS full disk encryption. |
| `features.encryption.unlockMethod` | `"tpm2"` | LUKS unlock method: `"tpm2"`, `"yubikey"`, or `"password"`. |
| `features.secureBoot.enable` | `false` | UEFI Secure Boot via lanzaboote. |
| `features.impermanence.enable` | `true` | Impermanent root with btrfs rollback on boot. |
| `features.impermanence.extraPaths` | `[]` | Additional paths to persist. |
| `features.snapshots.enable` | `true` | Automatic btrfs snapshots. |

Example for a laptop with encrypted storage:

```nix
features = {
  hardware = {
    formFactor = "laptop";
    cpu = "intel";
    gpu = "intel";
  };
  encryption = {
    unlockMethod = "yubikey";
  };
};
```

### Networking

Networking options describe connectivity rather than individual applications.
WiFi and SMB credentials are kept in SOPS; the host configuration only names
the networks and shares.

| Option | Default | Description |
|--------|---------|-------------|
| `features.wifi.enable` | `true` | WiFi profiles via SOPS secrets. |
| `features.wifi.networks` | `[]` | WPA2-PSK networks: `{ name, ssid }`. |
| `features.wifi.enterpriseNetworks` | `[]` | WPA2 Enterprise networks: `{ name, ssid, identity }`. |
| `features.wifi.preferEthernet.enable` | `true` | Prefer Ethernet and disable WiFi while a wired connection is active. |
| `features.ipv6PrivacyExtensions.enable` | `true` | IPv6 privacy extensions for NetworkManager. |
| `features.tailscale.enable` | `true` | Tailscale VPN and desktop tray integration. |
| `features.smb.enable` | `true` | Automatic SMB network share mounts. |
| `features.smb.shares` | `[]` | Shares to mount: `{ name, label, path, username? }`. |

```nix
features = {
  wifi = {
    enable = true;
    networks = [
      {
        name = "home";
        ssid = "Example WiFi";
      }
    ];
  };
  smb = {
    shares = [
      {
        name = "documents";
        label = "Documents";
        path = "//nas.example.org/Documents";
      }
    ];
  };
};
```

### Desktop & Security

This layer selects the interactive session and its security integrations. The
browser uses `about:newtab` as its startup page and replaces the new-tab content
with the configured dashboard. System-level power policy is supplemented by
the selected desktop session.

| Option | Default | Description |
|--------|---------|-------------|
| `features.desktop.enable` | `true` | Desktop environment and login manager. |
| `features.desktop.wm` | `"hyprland"` | Desktop: `"hyprland"` or `"kde"`. |
| `features.desktop.login` | `"greeter"` | `"greeter"` or `"autologin"`. |
| `features.desktop.fileManager` | `"default"` | `"default"` or terminal-based Yazi integration. |
| `features.desktop.browser.enable` | `true` | Managed default browser. |
| `features.desktop.browser.type` | `"librewolf"` | `"librewolf"` or `"firefox"`. |
| `features.desktop.browser.newTabPage` | `https://dash.at.oechsler.it` | Dashboard URL used by the managed new-tab page. |
| `features.desktop.browser.searchEngine` | `"ddg"` | Default search engine identifier. |
| `features.desktop.browser.cookieAllowlist` | `[]` | Additional sites allowed to keep first-party cookies and sessions. |
| `features.audio.enable` | `true` | PipeWire audio with PulseAudio compatibility. |
| `features.bluetooth.enable` | `true` | Bluetooth support. |
| `features.compat.enable` | `true` | `nix-ld` and glibc compatibility libraries. |
| `features.auth.totp.enable` | `true` | TOTP for sudo and SSH. |
| `features.auth.yubikey.enable` | `unlockMethod == "yubikey"` | YubiKey authentication. |
| `features.auth.ldap.enable` | `false` | LLDAP authentication. |
| `features.ssh.enable` | `false` | OpenSSH server and GitHub key sync. |

```nix
features = {
  desktop = {
    wm = "kde";
    login = "greeter";
    browser = {
      enable = true;
      type = "librewolf";
      newTabPage = "https://dashboard.example.org";
    };
  };
  auth = {
    totp.enable = true;
  };
};
```

### Virtualisation

Virtualisation is split into a master switch and two independent child
features. The master switch disables the resulting container and VM
configuration; child options can still be selected independently.

| Option | Default | Description |
|--------|---------|-------------|
| `features.virtualisation.enable` | `true` | Master switch for container and VM support. |
| `features.virtualisation.container.enable` | `true` | Podman with Docker-compatible CLI. |
| `features.virtualisation.vm.enable` | `true` | QEMU/KVM, libvirt, and virt-manager. |

```nix
features = {
  virtualisation = {
    enable = true;
    container.enable = true;
    vm.enable = false;
  };
};
```

### Gaming

Gaming enables the shared Steam/Proton toolchain. The Steam Machine option is
separate because it adds a login session rather than changing the desktop
session itself.

| Option | Default | Description |
|--------|---------|-------------|
| `features.gaming.enable` | `true` | Steam, Proton-GE, Gamescope, GameMode, and MangoHud. |
| `features.gaming.steamMachine.enable` | `false` | Steam Gamescope session in SDDM. |

```nix
features = {
  gaming = {
    enable = true;
    steamMachine.enable = false;
  };
};
```

### Development

Development tools inherit from `features.dev.enable` by default. Individual
IDE integrations can be disabled without removing the command-line toolchain.

| Option | Default | Description |
|--------|---------|-------------|
| `features.dev.enable` | `true` | Development languages, tools, and IDEs. |
| `features.dev.opencode.enable` | `dev.enable` | OpenCode AI coding agent. |
| `features.dev.jetbrains.enable` | `dev.enable` | JetBrains IDEs. |
| `features.dev.dbeaver.enable` | `dev.enable` | DBeaver database GUI. |

```nix
features = {
  dev = {
    enable = true;
    jetbrains.enable = false;
    dbeaver.enable = true;
  };
};
```

### Operations

Operations features provide declarative access to infrastructure. Profiles,
clusters, and credentials are separate so the same module can be reused across
hosts.

| Option | Default | Description |
|--------|---------|-------------|
| `features.ops.enable` | `true` | Infrastructure and operations tools. |
| `features.ops.pvetui.enable` | `ops.enable` | Proxmox VE terminal UI. |
| `features.ops.pvetui.profiles` | `[]` | Proxmox server profiles. |
| `features.ops.pvetui.defaultProfile` | `""` | Default Proxmox profile or group. |
| `features.ops.pvetui.groups` | `{}` | Proxmox profile groups. |
| `features.ops.kubernetes.enable` | `ops.enable` | Kubernetes tools with OIDC support. |
| `features.ops.kubernetes.clusters` | `[]` | Kubernetes cluster definitions. |
| `features.ops.kubernetes.defaultContext` | `""` | Default Kubernetes context. |

```nix
features = {
  ops = {
    enable = true;
    kubernetes = {
      enable = true;
      defaultContext = "cluster.example.org";
    };
  };
};
```

### Applications

Applications are the highest-level user-facing features. The general switch
controls the desktop application set; application-specific options are grouped
under their respective feature.

| Option | Default | Description |
|--------|---------|-------------|
| `features.apps.enable` | `true` | General desktop applications. |
| `features.apps.mumble.enable` | `true` | Install and configure Mumble when `features.apps.enable` is enabled. |
| `features.apps.mumble.username` | `user.name` | Default Mumble username. |
| `features.apps.mumble.servers` | `[]` | Favorite servers; `name` defaults to `host`, `port` to `64738`. |
| `features.apps.mumble.certificate.enable` | `false` | Import the optional SOPS-managed client certificate. |
| `features.apps.mumble.disablePublicServerList` | `true` | Disable Mumble's public server list. |
| `features.apps.mumble.autoConnectToLastServer` | `true` | Connect to the last server automatically. |
| `features.apps.mumble.reconnectAutomatically` | `true` | Reconnect after a lost connection. |
| `features.apps.mumble.hideInTray` | `true` | Keep Mumble in the system tray. |
| `features.apps.mumble.quitBehavior` | `"AlwaysMinimize"` | Close behavior. |
| `features.apps.mumble.serverFilterMode` | `"ShowAll"` | Favorite-list filter. |
| `features.flatpak.enable` | `true` | Flatpak and Flathub. |
| `features.appimage.enable` | `true` | AppImage support and watcher. |

#### Mumble

Mumble favorites are stored in its SQLite database and synchronized during
Home-Manager activation. The server `name` is optional and defaults to `host`;
the default port is `64738`. A minimal configuration is:

```nix
features = {
  apps = {
    mumble = {
      servers = [
        { host = "mumble.at.oechsler.it"; }
      ];
    };
  };
};
```

The default username is `user.name`; hosts can override it. Client
certificates are optional and are imported from SOPS only when enabled.

Set `features.apps.mumble.disablePublicServerList = false` to show the public server list again.

## SOPS Options

SOPS provides encrypted values to system and Home-Manager modules. Keep secret
values in the encrypted SOPS file and configure only paths and feature switches
in Nix.

| Option | Default | Description |
|--------|---------|-------------|
| `sops.secretsFile` | `../../sops/sops.encrypted.yaml` | Path to encrypted SOPS secrets file (override for external repos) |

```nix
sops = {
  secretsFile = ./sops/sops.encrypted.yaml;
};
```

## Networking Policy

The following implementation choices apply to the managed networking stack and
normally do not need per-host overrides:

- NetworkManager owns connection profiles, IP configuration, and routing.
- `iwd` is used as NetworkManager's WiFi backend.
- Docker/Tailscale interfaces are unmanaged in NetworkManager: `docker0`, `br-*`, `veth*`, `tailscale0`.
- Desktop hosts disable IPv6 only on Docker bridge/veth interfaces to reduce local development link churn.
- LLMNR is disabled in `systemd-resolved` to avoid resolver scopes on Docker/veth links.
- Desktop Ethernet disables WiFi autoconnect while active.

## User Options

These options describe the primary local user. Passwords and other sensitive
values are supplied through SOPS.

| Option | Default | Description |
|--------|---------|-------------|
| `user.name` | `flake.primaryUser` | Primary username; the flake value is shared with Disko and home paths. |
| `user.fullName` | `"Samuel Oechsler"` | Full name |
| `user.email` | `"samuel@oechsler.it"` | Email address |
| `user.github` | `"oechsler"` | GitHub username (for SSH key import) |
| `user.icon` | `.assets/sam-memoji.png` | Profile picture (SDDM) |
| `user.hashedPassword` | `"!"` (locked) | Local shadow password fallback; the runtime password is set from SOPS (`user/password`) when local password authentication is enabled. Can be overridden per-host with a hash (`mkpasswd -m yescrypt`). |
| `user.directories` | `[ "repos" ]` | Extra directories to create in `~` |

```nix
user = {
  fullName = "Example User";
  email = "user@example.org";
  directories = [ "Projects" "Documents" ];
};
```

## Theme Options

Theme options provide shared visual defaults for both supported desktop
sessions.

| Option | Default | Description |
|--------|---------|-------------|
| `theme.catppuccin.flavor` | `"mocha"` | `"latte"` / `"frappe"` / `"macchiato"` / `"mocha"` |
| `theme.catppuccin.accent` | `"mauve"` | Accent color (14 options: blue, flamingo, green, lavender, maroon, mauve, peach, pink, red, rosewater, sapphire, sky, teal, yellow) |
| `theme.scale` | `1.0` | DPI / monitor scale factor |
| `theme.backgrounds.path` | `"nix-black-4k.png"` | Wallpaper filename in archive, or path if `theme.backgrounds.enable = false` |
| `theme.backgrounds.enable` | `true` | Extract wallpapers from encrypted archive at boot |
| `theme.backgrounds.catppuccinize.enable` | `true` | Apply Catppuccin color grading to wallpapers via gowall |
| `theme.backgrounds.catppuccinize.invert` | `false` | Invert wallpaper colors before Catppuccin color mapping |
| `theme.backgrounds.catppuccinize.accent` | `[<system accent>]` | Wallpaper accent colors for gowall LUT mapping. `null` = all 14 flavour accents; `["lavender"]` = single accent shaded 14 ways; `["blue" "lavender"]` = cycled accents, each shaded. |
| `theme.radius.small` | `6` | Border radius for small elements (progress bars) |
| `theme.radius.default` | `16` | Border radius for windows/panels/notifications |
| `theme.gaps.inner` | `8` | Gaps between windows |
| `theme.gaps.outer` | `16` | Gaps at screen edges |
| `theme.border.width` | `2` | Window border width |
| `theme.cursor.name` | auto | Cursor theme (`"Breeze_Light"` on latte, `"breeze_cursors"` otherwise) |
| `theme.cursor.package` | `kdePackages.breeze` | Cursor theme package |
| `theme.cursor.size` | `24` | Cursor size |
| `theme.icons.name` | auto | Icon theme (`"Papirus-Light"` on latte, `"Papirus-Dark"` otherwise) |
| `theme.icons.package` | Catppuccin Papirus | Icon theme package (always Catppuccin Papirus) |

```nix
theme = {
  catppuccin = {
    flavor = "mocha";
    accent = "lavender";
  };
  scale = 1.0;
};
```

## Waybar Tray Icons

Waybar's system tray uses Papirus-Dark icon names for common applications.
This section applies to Hyprland; KDE manages tray icons through Plasma.

| Option | Default | Description |
|--------|---------|-------------|
| `waybar.tray.icons` | `{}` | Custom StatusNotifierItem Id → Papirus icon name mappings |

Default mappings are feature-gated and automatically applied:

| Feature Flag | App | StatusNotifierItem Id | Papirus Icon |
|--------------|-----|----------------------|--------------|
| `features.gaming.enable` | Steam | `steam` | `steam_tray_mono` |
| `features.apps.enable` | Nextcloud | `Nextcloud` | `state-ok` |
| `features.apps.enable` | Mumble | `Mumble` | `mumble-indicator` |
| `features.apps.enable` | Proton Pass | `Proton Pass_status_icon_1` | `dialog-password-panel` |
| `features.apps.enable` | Vesktop | `vesktop_status_icon_1` | `discord-tray` |
| `features.tailscale.enable` | Trayscale | `dev.deedles.Trayscale` | `network-vpn` |

### Customizing Tray Icons

Add or override mappings in `home.nix`:

```nix
waybar = {
  tray = {
    icons = {
      "MyApp" = "my-app-icon";
      steam = "custom_steam_icon";  # override default
    };
  };
};
```

To find the StatusNotifierItem Id for an application:

```bash
busctl --user introspect org.kde.StatusNotifierWatcher /StatusNotifierWatcher \
  org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems
```

The Id is the last path component (e.g., `steam` from `:1.107/org/ayatana/NotificationItem/steam`).

## Font Options

Font options are set in `configuration.nix` and shared with Home Manager.

| Option | Default | Description |
|--------|---------|-------------|
| `fonts.defaults.monospace` | `"JetBrainsMono Nerd Font"` | Monospace font (terminal, code editors, UI when `uiStyle = "monospace"`) |
| `fonts.defaults.sansSerif` | `"Noto Sans"` | Sans-serif font (UI when `uiStyle = "sans-serif"`) |
| `fonts.defaults.serif` | `"Noto Serif"` | Serif font (fontconfig default) |
| `fonts.defaults.uiStyle` | `"monospace"` | Font style for UI elements: `"monospace"` or `"sans-serif"` |
| `fonts.defaults.ui` | *(read-only)* | Resolved font name based on `uiStyle` — used by waybar, dunst, rofi, hyprlock, SDDM, GTK, Qt |
| `fonts.defaults.size` | `11` | Default font size for UI elements |
| `fonts.defaults.terminalSize` | `fonts.defaults.size` | Terminal (kitty) font size |
| `fonts.defaults.uiPixelSize` | `floor(size * 4 / 3)` | Resolved pixel size used by Waybar and other UI components (read-only). |

## Locale Options

Locale options are set in `configuration.nix` and apply system-wide.

| Option | Default | Description |
|--------|---------|-------------|
| `locale.timezone` | `"Europe/Berlin"` | Timezone |
| `locale.language` | `"de_DE.UTF-8"` | System locale; German is the default |
| `locale.keyboard` | `"de"` | Keyboard layout |

```nix
locale = {
  timezone = "Europe/Berlin";
  language = "de_DE.UTF-8";
  keyboard = "de";
};
```

## Display Options

Display options work on both Hyprland and KDE. When `displays.monitors` is
empty, the system uses automatic layout detection and `theme.scale`.

To find your connector names, resolution and refresh rate:

```bash
# Hyprland
hyprctl monitors

# KDE / generic
kscreen-doctor -o
```

```nix
displays = {
  defaults = {
    vrr = 2;
    hdr = 1;
  };
  monitors = [
    {
      name = "DP-1";
      width = 2560;
      height = 1440;
      refreshRate = 165;
      x = 0;
      y = 0;
      vrr = 2;
      hdr = 1;
    }
    {
      name = "DP-2";
      width = 2560;
      height = 1440;
      refreshRate = 165;
      x = 2560;
      y = 0;
      vrr = 2;
      hdr = 1;
    }
  ];
};
```

| Option | Default | Description |
|--------|---------|-------------|
| `displays.defaults.vrr` | `2` | Default VRR mode for hotplugged/unlisted monitors where output-independent defaults are supported: `0` off, `1` always, `2` fullscreen/automatic |
| `displays.defaults.hdr` | `1` | Default HDR mode for hotplugged/unlisted monitors where supported: `0` off, `1` Steam/Gamescope HDR, `2` full desktop HDR |
| `displays.defaultWorkspaceCount` | `4` | Number of workspaces created by default. |
| `displays.monitors` | `[]` | List of monitor configurations |
| `displays.monitors.*.name` | — | Connector name (`"DP-1"`, `"HDMI-A-1"`, `"eDP-1"`) |
| `displays.monitors.*.edidHash` | `null` | Optional stable EDID identifier for display matching. |
| `displays.monitors.*.make` | `null` | Optional monitor manufacturer for display matching. |
| `displays.monitors.*.model` | `null` | Optional monitor model for display matching. |
| `displays.monitors.*.serial` | `null` | Optional monitor serial number for display matching. |
| `displays.monitors.*.width` | `1920` | Horizontal resolution |
| `displays.monitors.*.height` | `1080` | Vertical resolution |
| `displays.monitors.*.refreshRate` | `60` | Refresh rate in Hz |
| `displays.monitors.*.x` | `0` | Horizontal position offset |
| `displays.monitors.*.y` | `0` | Vertical position offset |
| `displays.monitors.*.scale` | `theme.scale` | Scale factor |
| `displays.monitors.*.rotation` | `"normal"` | Rotation (`"normal"`, `"90"`, `"180"`, or `"270"`) |
| `displays.monitors.*.wallpaper` | `null` | Per-monitor wallpaper; `null` uses the processed default |
| `displays.monitors.*.workspaces` | `[]` | Workspace IDs to bind to this monitor (Hyprland only) |
| `displays.monitors.*.vrr` | `0` | VRR mode: `0` off, `1` always, `2` fullscreen/automatic |
| `displays.monitors.*.hdr` | `0` | HDR mode: `0` off, `1` Steam/Gamescope, `2` full desktop HDR |
| `displays.monitors.*.hdrSdrMaxLuminance` | `450` | SDR white level in nits for HDR conversion |

Default behavior and limitations:

- Steam Machine/Gamescope uses `displays.defaults.vrr` and `displays.defaults.hdr != 0` as session-wide fallbacks, so a Steam session can enable adaptive sync and HDR even when the connected output is not listed in `displays.monitors`. It does not override Gamescope color management, virtual white, SDR brightness, or gamut behavior.
- Hyprland uses `displays.defaults.vrr` for its global VRR mode, so hotplugged/unlisted monitors get VRR behavior by default.
- Hyprland applies full desktop HDR only for monitors with `hdr = 2` or unknown outputs when `displays.defaults.hdr = 2`. `hdr = 1` keeps desktop HDR off to avoid flicker while still allowing Steam/Gamescope HDR.
- KDE applies HDR/VRR through `kscreen-doctor`, which needs concrete output names. HDR is enabled only for monitors with `hdr = 2`, with the configured SDR brightness but without overriding color profile or wide-gamut behavior.
- SDDM applies layout and VRR only; HDR is intentionally left off in the greeter so Game Mode and desktop sessions initialize HDR themselves.
- Set `displays.defaults.hdr = 0` on hosts that commonly connect SDR-only projectors/TVs and should not advertise HDR by default.

On Hyprland, a catch-all fallback rule (`preferred, auto, theme.scale`) is always added for hotplugged/unlisted monitors. On KDE, `kscreen-doctor` is run at login via an XDG autostart entry to apply the monitor layout for known outputs.

## Input Options

Input settings define the default pointer and touchpad behavior shared by
Hyprland and KDE. They are intentionally small; device-specific settings are
handled by the desktop session when it starts.

| Option | Default | Description |
|--------|---------|-------------|
| `input.mouse.naturalScroll` | `true` | Use natural (reversed) scrolling for mice. |
| `input.touchpad.naturalScroll` | `true` | Use natural (reversed) scrolling for touchpads. |

```nix
input = {
  mouse = {
    naturalScroll = true;
  };
  touchpad = {
    naturalScroll = true;
  };
};
```

On KDE, touchpad settings are detected and applied per device during session
startup.

## Autostart Apps

Autostart entries are managed by Home Manager and translated to the selected
desktop's session mechanism. Feature modules add their own entries when enabled;
custom entries can be added to the same list.

| Option | Default | Description |
|--------|---------|-------------|
| `autostart.apps` | Feature-dependent | Applications started when the graphical session begins. |

```nix
autostart = {
  apps = [
    {
      name = "Example App";
      exec = "example-app";
    }
  ];
};
```

The default list is extended by feature toggles:
- `features.apps.enable` adds Nextcloud, Proton Pass, and Vesktop
- `features.apps.enable` plus `features.apps.mumble.enable` adds Mumble
- `features.gaming.enable` adds Steam
- `features.tailscale.enable` adds Trayscale

Each entry contains a display `name` and an `exec` command. KDE writes XDG
autostart entries; Hyprland starts the commands with `exec-once`.

## File Manager

`features.desktop.fileManager` selects the primary file manager and keeps the
desktop shortcuts, MIME associations, and pinned applications consistent.

| Value | Behavior |
|-------|----------|
| `"default"` | Use Nautilus on Hyprland or Dolphin on KDE. |
| `"terminal"` | Use Yazi from Kitty and remove the GUI file manager from the pins. |

```nix
features = {
  desktop = {
    fileManager = "terminal";
  };
};
```

Yazi integrations follow the existing feature toggles. Heavy preview
integrations are enabled only when their corresponding application or
development feature is enabled.

## File Manager Bookmarks

Bookmarks are shared across the supported file managers. The same declarative
list is rendered as GTK bookmarks, KDE places, or Yazi shortcuts depending on
the active desktop.

| Option | Default | Description |
|--------|---------|-------------|
| `fileManager.bookmarks` | Feature-dependent | Sidebar bookmarks and Yazi shortcuts. |

```nix
fileManager = {
  bookmarks = [
    {
      name = "Projects";
      path = "/home/user/Projects";
      icon = "folder-development";
    }
  ];
};
```

Each entry has a display `name`, an absolute `path`, and an optional icon. The
`icon` field defaults to `"folder"`.

Bookmarks are managed declaratively for Nautilus, Dolphin, and Yazi.

## Pinned Dock/Taskbar Apps

Pinned applications control desktop presentation, not package installation.
The default list follows the enabled feature groups and the selected file
manager.

| Option | Default | Description |
|--------|---------|-------------|
| `desktop.pinnedApps` | Feature-dependent | Desktop files pinned to the dock or taskbar. |

```nix
desktop = {
  pinnedApps = [
    "firefox"
    "kitty"
  ];
};
```

The default list is extended by feature toggles:
- `features.dev.enable` adds Neovim
- `features.apps.enable` adds Obsidian, Vesktop, Spotify
- `features.gaming.enable` adds Steam

Each entry is a desktop file name without the `.desktop` suffix, such as
`"firefox"`.

## Idle / Power Management

These values define the shared idle policy. Hyprland implements it with
`hypridle`; KDE translates it to PowerDevil. The session-specific implementation
keeps the resulting lock, display, and suspend behavior aligned.

| Option | Default | Description |
|--------|---------|-------------|
| `idle.timeouts.dimBattery` | `120` | Seconds before dimming on battery. |
| `idle.timeouts.suspendBattery` | `300` | Seconds before locking and suspending on battery. |
| `idle.timeouts.dimAc` | `300` | Seconds before dimming on AC. |
| `idle.timeouts.suspendAc` | `1800` | Seconds before locking and suspending on AC. |

```nix
idle = {
  timeouts = {
    dimBattery = 120;
    suspendBattery = 300;
    dimAc = 300;
    suspendAc = 1800;
  };
};
```

### Hyprland Dim Settings

Hyprland uses a custom gradual dimming sequence: the configured idle timeout
starts the sequence, `stepPercent` controls each brightness step, and
`stepDelay` controls the transition speed. KDE does not use these options;
PowerDevil provides its own built-in display dimming and uses the shared idle
timeouts above.

| Option | Default | Description |
|--------|---------|-------------|
| `hypridle.dim.percent` | `10` | Target brightness when dimmed (%) |
| `hypridle.dim.stepPercent` | `5` | Brightness step size for smooth dimming (%) |
| `hypridle.dim.stepDelay` | `"0.05"` | Delay between dim steps in seconds |

```nix
hypridle = {
  dim = {
    percent = 10;
    stepPercent = 5;
    stepDelay = "0.05";
  };
};
```

## Impermanence

Impermanence recreates the root filesystem on every boot. Persistent state is
kept under `/persist` and is declared by feature modules or
`features.impermanence.extraPaths`. This makes the base system reproducible,
but it also means that undeclared state is intentionally discarded.

Use `extraPaths` only for state that is not already covered by a feature module.
The installation must provide the `/persist` Btrfs subvolume when this feature
is enabled. See [INSTALL.md](INSTALL.md#impermanence) for the installation
layout.

```nix
features = {
  impermanence = {
    enable = true;
    extraPaths = [ "/var/lib/example" ];
  };
};
```

## Snapshots

Snapshots are separate from impermanence. Impermanence controls what survives a
reboot; snapshots provide historical restore points for persistent Btrfs state.
Snapshots do not make undeclared root state persistent and are not a substitute
for backups. See [SNAPSHOTS.md](SNAPSHOTS.md) for restore, browse, and cleanup.

```nix
features = {
  snapshots.enable = false;
};
```

## System Requirements

The default installation expects a Btrfs layout with `@` for `/`, `@home` for
`/home`, `@nix` for `/nix`, `@persist` for persistent state, and `@snapshots`
for snapshot targets. Full-disk encryption is also enabled by default.

These requirements are installation constraints rather than runtime feature
settings. Changing the impermanence or encryption defaults requires a matching
disk layout:

```nix
features = {
  # Traditional persistent root (no rollback)
  impermanence.enable = false;

  # Unencrypted disk (not recommended for laptops)
  encryption.enable = false;
};
```

See [INSTALL.md](INSTALL.md#disk-layout) for the required partition and subvolume structure.
