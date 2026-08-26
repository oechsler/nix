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
  desktop = {
    enable = true;
  };

  encryption.enable = true;
  gaming = {
    enable = false;
  };
  dev.enable = true;
  virtualisation.enable = true;
};
```

### Hardware & Boot

These options describe the machine and the guarantees required before
userspace configuration starts. Hardware values are normally host-specific;
the remaining options control boot-time storage and persistence.

| Option                                | Default     | Description                                                                                               |
| ------------------------------------- | ----------- | --------------------------------------------------------------------------------------------------------- |
| `features.hardware.formFactor`        | `"desktop"` | Machine form factor: `"desktop"` or `"laptop"`.                                                           |
| `features.hardware.cpu`               | `null`      | CPU vendor: `"amd"` or `"intel"`; selects microcode.                                                      |
| `features.hardware.gpu`               | `null`      | GPU vendor: `"amd"` or `"intel"`; selects graphics and VA-API support. NVIDIA is not supported.           |
| `features.kernel`                     | `"cachyos"` | Kernel variant, such as `"cachyos-v3"`, `"cachyos-v4"`, `"cachyos-lts"`, `"default"`, or `"default-lts"`. |
| `features.secureBoot.enable`          | `false`     | UEFI Secure Boot via lanzaboote.                                                                          |
| `features.impermanence.enable`        | `true`      | Impermanent root with btrfs rollback on boot.                                                             |
| `features.impermanence.persistPrefix` | read-only   | Resolved persistence prefix (`/persist` when enabled).                                                    |
| `features.impermanence.extraPaths`    | `[]`        | Additional paths to persist.                                                                              |
| `features.snapshots.enable`           | `true`      | Automatic btrfs snapshots.                                                                                |

Example for a laptop:

```nix
features = {
  hardware = {
    formFactor = "laptop";
    cpu = "intel";
    gpu = "intel";
  };
};
```

Impermanence recreates the root filesystem on every boot. Persistent state is
kept under `/persist` and is declared by feature modules or
`features.impermanence.extraPaths`. Use `extraPaths` only for state that is not
already covered by a feature module. The installation must provide the
`/persist` Btrfs subvolume when this feature is enabled. See
[INSTALL.md](INSTALL.md#impermanence) for the installation layout.

```nix
features = {
  impermanence = {
    enable = true;
    extraPaths = [ "/var/lib/example" ];
  };
};
```

Snapshots are separate from impermanence. Impermanence controls what survives a
reboot; snapshots provide historical restore points for persistent Btrfs state.
Snapshots do not make undeclared root state persistent and are not a substitute
for backups. See [SNAPSHOTS.md](SNAPSHOTS.md) for restore, browse, and cleanup.

```nix
features = {
  snapshots = {
    enable = false;
  };
};
```

### Authentication & Security

Authentication, encryption, and boot integrity are configured independently
from the desktop session.

| Option                             | Default                     | Description                                                 |
| ---------------------------------- | --------------------------- | ----------------------------------------------------------- |
| `features.encryption.enable`       | `true`                      | LUKS full disk encryption.                                  |
| `features.encryption.unlockMethod` | `"tpm2"`                    | LUKS unlock method: `"tpm2"`, `"yubikey"`, or `"password"`. |
| `features.auth.totp.enable`        | `true`                      | TOTP for sudo and SSH.                                      |
| `features.auth.yubikey.enable`     | `unlockMethod == "yubikey"` | YubiKey authentication.                                     |
| `features.auth.ldap.enable`        | `false`                     | LLDAP authentication.                                       |
| `features.auth.ldap.uri`           | `null`                      | LDAP URI; required when LDAP is enabled.                    |
| `features.auth.ldap.baseDn`        | `null`                      | LDAP base DN; required when LDAP is enabled.                |

```nix
features = {
  encryption = {
    enable = true;
    unlockMethod = "yubikey";
  };
  auth = {
    totp = {
      enable = true;
    };
    yubikey = {
      enable = true;
    };
  };
};
```

#### SSH

SSH server access can use a synchronized URL/local key file and, optionally,
keys currently loaded in the SSH agent.

| Option                          | Default                                  | Description                                    |
| ------------------------------- | ---------------------------------------- | ---------------------------------------------- |
| `features.ssh.enable`           | `false`                                  | Enable the OpenSSH server.                     |
| `features.ssh.localKeys.enable` | `true`                                   | Accept keys from `user.keys`.                  |
| `features.ssh.agentKeys.enable` | `true`                                   | Accept keys currently loaded in the SSH agent. |
| `user.keys`                     | `https://git.at.oechsler.it/samuel.keys` | URL or local file containing public SSH keys.  |

```nix
features = {
  ssh = {
    enable = true;
    localKeys = {
      enable = true;
    };
    agentKeys = {
      enable = true;
    };
  };
};

user.keys = "https://git.at.oechsler.it/samuel.keys";
```

Set `user.keys` to a local public-key file when the keys should not be fetched
over the network.

### Networking

Networking options describe connectivity rather than individual applications.
WiFi and SMB credentials are kept in SOPS; the host configuration only names
the networks and shares.

| Option                                  | Default | Description                                                          |
| --------------------------------------- | ------- | -------------------------------------------------------------------- |
| `features.wifi.enable`                  | `true`  | WiFi profiles via SOPS secrets.                                      |
| `features.wifi.networks`                | `[]`    | WPA2-PSK networks: `{ name, ssid }`.                                 |
| `features.wifi.enterpriseNetworks`      | `[]`    | WPA2 Enterprise networks: `{ name, ssid, identity }`.                |
| `features.wifi.preferEthernet.enable`   | `true`  | Prefer Ethernet and disable WiFi while a wired connection is active. |
| `features.ipv6PrivacyExtensions.enable` | `true`  | IPv6 privacy extensions for NetworkManager.                          |
| `features.tailscale.enable`             | `true`  | Tailscale VPN; Trayscale tray app on desktop systems.                |
| `features.smb.enable`                   | `true`  | Automatic SMB network share mounts.                                  |
| `features.smb.shares`                   | `[]`    | Shares to mount: `{ name, label, path, username? }`.                 |

PSK networks require `name` and `ssid`; enterprise networks additionally
require `identity`. SMB shares are mounted below `~/smb/<label>/`, and their
`username` defaults to `user.name`.

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

The following implementation choices apply to the managed networking stack and
normally do not need per-host overrides:

- NetworkManager owns connection profiles, IP configuration, and routing.
- `iwd` is used as NetworkManager's WiFi backend.
- Docker/Tailscale interfaces are unmanaged in NetworkManager: `docker0`, `br-*`, `veth*`, `tailscale0`.
- Desktop hosts disable IPv6 only on Docker bridge/veth interfaces to reduce local development link churn.
- LLMNR is disabled in `systemd-resolved` to avoid resolver scopes on Docker/veth links.
- Desktop Ethernet disables WiFi autoconnect while active.

### Desktop

This layer selects the interactive session and shared desktop integrations.
Desktop-specific settings are grouped below by the component they configure.

| Option                      | Default      | Description                                   |
| --------------------------- | ------------ | --------------------------------------------- |
| `features.desktop.enable`   | `true`       | Desktop environment and login manager.        |
| `features.desktop.wm`       | `"hyprland"` | Desktop: `"hyprland"` or `"kde"`.             |
| `features.desktop.login`    | `"greeter"`  | `"greeter"` or `"autologin"`.                 |
| `features.audio.enable`     | `true`       | PipeWire audio with PulseAudio compatibility. |
| `features.bluetooth.enable` | `true`       | Bluetooth support.                            |
| `features.compat.enable`    | `true`       | `nix-ld` and glibc compatibility libraries.   |

```nix
features = {
  desktop = {
    wm = "kde";
    login = "greeter";
  };
};
```

#### Browser

The selected browser is configured with a managed profile. The new-tab
extension opens the configured dashboard URL; this is separate from the
browser's normal startup behavior. The search engine and cookie allowlist are
also applied to the selected browser.

| Option                                     | Default                       | Description                                                        |
| ------------------------------------------ | ----------------------------- | ------------------------------------------------------------------ |
| `features.desktop.browser.enable`          | `true`                        | Enable the managed default browser.                                |
| `features.desktop.browser.type`            | `"librewolf"`                 | Select `"librewolf"` or `"firefox"`.                               |
| `features.desktop.browser.newTabPage`      | `https://dash.at.oechsler.it` | URL opened by the managed new-tab extension.                       |
| `features.desktop.browser.searchEngine`    | `"ddg"`                       | Default browser search engine identifier.                          |
| `features.desktop.browser.cookieAllowlist` | `[]`                          | Additional sites allowed to keep first-party cookies and sessions. |

```nix
features = {
  desktop = {
    browser = {
      enable = true;
      type = "librewolf";
      newTabPage = "https://dash.example.com";
      searchEngine = "ddg";
      cookieAllowlist = [ "https://example.org" ];
    };
  };
};
```

#### Pinned Dock/Taskbar Apps

Pinned applications control desktop presentation, not package installation.
The default list follows the enabled feature groups and the selected file
manager.

| Option                                    | Default           | Description                                         |
| ----------------------------------------- | ----------------- | --------------------------------------------------- |
| `features.desktop.pinnedApps.declarative` | `true`            | Enforce the pinned app list on every desktop start. |
| `features.desktop.pinnedApps.entries`     | Feature-dependent | Desktop files pinned to the dock or taskbar.        |

```nix
features = {
  desktop = {
    pinnedApps = {
      declarative = true;
      entries = [
        "firefox"
        "kitty"
      ];
    };
  };
};
```

The effective default starts with the selected browser, `yazi` or the GUI file
manager (`org.kde.dolphin` on KDE, `org.gnome.Nautilus` otherwise), and `kitty`.
It is extended by feature toggles:

- `features.dev.enable` adds Neovim
- `features.apps.enable` adds Obsidian, Vesktop, Spotify
- `features.apps.enable` plus `features.apps.mumble.enable` adds Mumble
- `features.gaming.enable` adds Steam

Mumble uses `info.mumble.Mumble`; each other entry is a desktop file name
without the `.desktop` suffix, such as `"firefox"`.

#### KDE Desktop Options

| Option                                       | Default | Description                                              |
| -------------------------------------------- | ------- | -------------------------------------------------------- |
| `features.desktop.kde.favorites.declarative` | `true`  | Enforce KDE Kickoff favorites on every KDE start.        |
| `features.desktop.kde.favorites.entries`     | `null`  | KDE Kickoff favorites; KDE supplies defaults when unset. |
| `features.desktop.kde.tray.shown`            | `null`  | KDE tray items displayed directly in the panel.          |
| `features.desktop.kde.tray.hidden`           | `null`  | KDE tray items kept behind the tray popup.               |

```nix
features = {
  desktop = {
    kde = {
      favorites = {
        declarative = true;
        entries = [ "librewolf" "org.kde.dolphin" "kitty" "systemsettings" ];
      };
      tray = {
        shown = [ "org.kde.plasma.networkmanagement" "org.kde.plasma.volume" ];
      };
    };
  };
};
```

#### File Manager

`features.desktop.fileManager` selects the primary file manager and keeps the
desktop shortcuts, MIME associations, and pinned applications consistent.

| Option                         | Default     | Description                                    |
| ------------------------------ | ----------- | ---------------------------------------------- |
| `features.desktop.fileManager` | `"default"` | Select the GUI or terminal-based file manager. |

| Value        | Behavior                                                           |
| ------------ | ------------------------------------------------------------------ |
| `"default"`  | Use Nautilus on Hyprland or Dolphin on KDE.                        |
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

Press `Space` followed by `.` in Yazi to toggle hidden files. The shortcut is
configured in the Yazi module and is available independently of the preview
feature toggles.

#### File Manager Bookmarks

Bookmarks are shared across the supported file managers. The same declarative
list is rendered as GTK bookmarks, KDE places, or Yazi shortcuts depending on
the active desktop.

| Option                           | Default           | Description                           |
| -------------------------------- | ----------------- | ------------------------------------- |
| `features.fileManager.bookmarks` | Feature-dependent | Sidebar bookmarks and Yazi shortcuts. |

By default, bookmarks are generated from the XDG user directories and add the
Nextcloud directory when `features.apps.enable` is enabled. Setting
`features.fileManager.bookmarks` replaces this generated list.

```nix
features = {
  fileManager = {
    bookmarks = [
      {
        name = "Projects";
        path = "/home/user/Projects";
        icon = "folder-development";
      }
    ];
  };
};
```

Each entry has a display `name`, an absolute `path`, and an optional icon. The
`icon` field defaults to `"folder"`. Bookmarks are managed declaratively for
Nautilus, Dolphin, and Yazi.

#### Waybar Tray Icons

Waybar's system tray uses Papirus-Dark icon names for common applications. This
option applies to Hyprland; KDE manages tray icons through Plasma.

| Option                        | Default | Description                                                |
| ----------------------------- | ------- | ---------------------------------------------------------- |
| `features.desktop.tray.icons` | `{}`    | Custom StatusNotifierItem ID to Papirus icon name mappings |

Default mappings are feature-gated and automatically applied. Custom mappings
override entries with the same StatusNotifierItem ID.

| Feature Flag                | App         | StatusNotifierItem ID       | Papirus Icon            |
| --------------------------- | ----------- | --------------------------- | ----------------------- |
| `features.gaming.enable`    | Steam       | `steam`                     | `steam_tray_mono`       |
| `features.apps.enable`      | Nextcloud   | `Nextcloud`                 | `state-ok`              |
| `features.apps.enable`      | Mumble      | `Mumble`                    | `mumble-indicator`      |
| `features.apps.enable`      | Proton Pass | `Proton Pass_status_icon_1` | `dialog-password-panel` |
| `features.apps.enable`      | Vesktop     | `vesktop_status_icon_1`     | `discord-tray`          |
| `features.tailscale.enable` | Trayscale   | `dev.deedles.Trayscale`     | `network-vpn`           |

```nix
features = {
  desktop = {
    tray = {
      icons = {
        "MyApp" = "my-app-icon";
        steam = "custom_steam_icon";
      };
    };
  };
};
```

### Virtualisation

Virtualisation is split into a master switch and two independent child
features. The master switch disables the resulting container and VM
configuration; child options can still be selected independently.

| Option                                     | Default | Description                                 |
| ------------------------------------------ | ------- | ------------------------------------------- |
| `features.virtualisation.enable`           | `true`  | Master switch for container and VM support. |
| `features.virtualisation.container.enable` | `true`  | Podman with Docker-compatible CLI.          |
| `features.virtualisation.vm.enable`        | `true`  | QEMU/KVM, libvirt, and virt-manager.        |

```nix
features = {
  virtualisation = {
    enable = true;
    container = {
      enable = true;
    };
    vm = {
      enable = false;
    };
  };
};
```

### Gaming

Gaming enables the shared Steam/Proton toolchain. The Steam Machine option is
separate because it adds a login session rather than changing the desktop
session itself.

| Option                                | Default | Description                                          |
| ------------------------------------- | ------- | ---------------------------------------------------- |
| `features.gaming.enable`              | `true`  | Steam, Proton-GE, Gamescope, GameMode, and MangoHud. |
| `features.gaming.steamMachine.enable` | `false` | Steam Gamescope session in SDDM.                     |

```nix
features = {
  gaming = {
    enable = true;
    steamMachine = {
      enable = false;
    };
  };
};
```

### Development

Development tools inherit from `features.dev.enable` by default. Individual
IDE integrations can be disabled without removing the command-line toolchain.

| Option                           | Default                    | Description                             |
| -------------------------------- | -------------------------- | --------------------------------------- |
| `features.dev.enable`            | `true`                     | Development languages, tools, and IDEs. |
| `features.dev.opencode.enable`   | `dev.enable`               | OpenCode AI coding agent.               |
| `features.dev.jetbrains.entries` | `[ "goland" "rustrover" ]` | JetBrains IDEs to install.              |
| `features.dev.dbeaver.enable`    | `dev.enable`               | DBeaver database GUI.                   |

Available values are `clion`, `datagrip`, `dataspell`, `gateway`, `goland`,
`idea-oss`, `idea-ultimate`, `mps`, `phpstorm`, `pycharm`, `rider`, `rubymine`,
`rustrover`, and `webstorm`.

```nix
features = {
  dev = {
    enable = true;
    jetbrains = {
      entries = [ "goland" "rustrover" ];
    };
    dbeaver = {
      enable = true;
    };
  };
};
```

### Operations

Operations features provide declarative access to infrastructure. Profiles,
clusters, and credentials are separate so the same module can be reused across
hosts.

| Option                                   | Default       | Description                                                                        |
| ---------------------------------------- | ------------- | ---------------------------------------------------------------------------------- |
| `features.ops.enable`                    | `true`        | Infrastructure and operations tools.                                               |
| `features.ops.pvetui.enable`             | `ops.enable`  | Proxmox VE terminal UI.                                                            |
| `features.ops.pvetui.profiles`           | `[]`          | Proxmox server profiles.                                                           |
| `features.ops.pvetui.defaultProfile`     | `""`          | Default Proxmox profile or group.                                                  |
| `features.ops.pvetui.groups`             | `{}`          | Proxmox profile groups.                                                            |
| `features.ops.pvetui.profiles.*`         | See module    | Profile fields: `name`, `addr`, `user`, `realm`, `tokenId`, SSH, and TLS settings. |
| `features.ops.pvetui.groups.*.mode`      | `"aggregate"` | Group mode: `"aggregate"` or `"cluster"`.                                          |
| `features.ops.kubernetes.enable`         | `ops.enable`  | Kubernetes tools with OIDC support.                                                |
| `features.ops.kubernetes.clusters`       | `[]`          | Kubernetes cluster definitions.                                                    |
| `features.ops.kubernetes.clusters.*`     | See module    | Cluster fields: `name`, `server`, `caData`, namespace, user, and OIDC settings.    |
| `features.ops.kubernetes.defaultContext` | `""`          | Default Kubernetes context.                                                        |

```nix
features = {
  ops = {
    enable = true;
    pvetui = {
      profiles = [
        {
          name = "home";
          addr = "https://proxmox.example.org:8006";
          groups = [ "home-lab" ];
        }
      ];
      defaultProfile = "home";
    };
    kubernetes = {
      enable = true;
      clusters = [
        {
          name = "home";
          server = "https://k3s.example.org:6443";
          caData = "<base64-ca-data>";
          oidc = {
            issuerUrl = "https://auth.example.org/realms/main";
            clientId = "kubernetes";
          };
        }
      ];
      defaultContext = "";
    };
  };
};
```

### Applications

Applications are the highest-level user-facing features. The general switch
controls the desktop application set; application-specific options are grouped
under their respective feature.

| Option                                         | Default            | Description                                                          |
| ---------------------------------------------- | ------------------ | -------------------------------------------------------------------- |
| `features.apps.enable`                         | `true`             | General desktop applications.                                        |
| `features.apps.nextcloud.enable`               | `apps.enable`      | Nextcloud desktop client and synchronization.                        |
| `features.apps.mumble.enable`                  | `true`             | Install and configure Mumble when `features.apps.enable` is enabled. |
| `features.apps.mumble.username`                | `user.name`        | Default Mumble username.                                             |
| `features.apps.mumble.servers`                 | `[]`               | Favorite servers; `name` defaults to `host`, `port` to `64738`.      |
| `features.apps.mumble.playMuteCue`             | `false`            | Play a cue when Mumble is muted or unmuted.                          |
| `features.apps.mumble.channelExpansionMode`    | `AllChannels`      | Channel expansion mode in the Mumble server tree.                    |
| `features.apps.mumble.disablePublicServerList` | `true`             | Disable Mumble's public server list.                                 |
| `features.apps.mumble.autoConnectToLastServer` | `true`             | Connect to the last server automatically.                            |
| `features.apps.mumble.reconnectAutomatically`  | `true`             | Reconnect after a lost connection.                                   |
| `features.apps.mumble.hideInTray`              | `true`             | Keep Mumble in the system tray.                                      |
| `features.apps.mumble.quitBehavior`            | `"AlwaysMinimize"` | Close behavior.                                                      |
| `features.apps.mumble.serverFilterMode`        | `"ShowAll"`        | Favorite-list filter.                                                |
| `features.flatpak.enable`                      | `true`             | Flatpak and Flathub.                                                 |
| `features.appimage.enable`                     | `true`             | AppImage support and watcher.                                        |

```nix
features = {
  apps = {
    enable = true;
    nextcloud = {
      enable = true;
    };
  };
  flatpak.enable = true;
  appimage.enable = true;
};
```

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

The default username is `user.name`; hosts can override it. If the optional
`mumble/certificate` secret exists in SOPS, it is imported automatically.

Set `features.apps.mumble.disablePublicServerList = false` to show the public server list again.

## Options

The options in this section configure shared system and userspace behavior after
the feature toggles have selected the system capabilities. They are ordered from
system-wide settings toward session and application integration. Feature
defaults remain under `features`; these options provide the lower-level values
consumed by those features.

### Idle / Power Management

Idle handling is session-facing, but closely tied to display power and suspend
behavior. Hyprland uses `hypridle`; KDE translates the same timeouts to
PowerDevil. The session-specific implementation keeps locking, display dimming,
and suspend behavior aligned.

| Option                         | Default | Description                                       |
| ------------------------------ | ------- | ------------------------------------------------- |
| `idle.timeouts.dimBattery`     | `120`   | Seconds before dimming on battery.                |
| `idle.timeouts.suspendBattery` | `300`   | Seconds before locking and suspending on battery. |
| `idle.timeouts.dimAc`          | `300`   | Seconds before dimming on AC.                     |
| `idle.timeouts.suspendAc`      | `1800`  | Seconds before locking and suspending on AC.      |

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

| Option                          | Default  | Description                                 |
| ------------------------------- | -------- | ------------------------------------------- |
| `idle.hypridle.dim.percent`     | `10`     | Target brightness when dimmed (%)           |
| `idle.hypridle.dim.stepPercent` | `5`      | Brightness step size for smooth dimming (%) |
| `idle.hypridle.dim.stepDelay`   | `"0.05"` | Delay between dim steps in seconds          |

```nix
idle = {
  hypridle = {
    dim = {
      percent = 10;
      stepPercent = 5;
      stepDelay = "0.05";
    };
  };
};
```

### SOPS Options

SOPS provides encrypted values to system and Home-Manager modules. Keep secret
values in the encrypted SOPS file and configure only paths and feature switches
in Nix.

| Option             | Default                          | Description                                                       |
| ------------------ | -------------------------------- | ----------------------------------------------------------------- |
| `sops.secretsFile` | `../../sops/sops.encrypted.yaml` | Path to encrypted SOPS secrets file (override for external repos) |

```nix
sops = {
  secretsFile = ./sops/sops.encrypted.yaml;
};
```

### User Options

These options describe the primary local user. Passwords and other sensitive
values are supplied through SOPS.

| Option                | Default                  | Description                                                                                                                                                                                             |
| --------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `user.name`           | `flake.primaryUser`      | Primary username; the flake value is shared with Disko and home paths.                                                                                                                                  |
| `user.fullName`       | `"Samuel Oechsler"`      | Full name                                                                                                                                                                                               |
| `user.email`          | `"samuel@oechsler.it"`   | Email address                                                                                                                                                                                           |
| `user.icon`           | `.assets/sam-memoji.png` | Profile picture (SDDM)                                                                                                                                                                                  |
| `user.hashedPassword` | `"!"` (locked)           | Local shadow password fallback; the runtime password is set from SOPS (`user/password`) when local password authentication is enabled. Can be overridden per-host with a hash (`mkpasswd -m yescrypt`). |
| `user.directories`    | `[ "repos" ]`            | Extra directories to create in `~`                                                                                                                                                                      |

```nix
user = {
  fullName = "Example User";
  email = "user@example.org";
  directories = [ "Projects" "Documents" ];
};
```

### Theme Options

Theme options provide shared visual defaults for both supported desktop
sessions.

| Option                                   | Default              | Description                                                                                                                                                                          |
| ---------------------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `theme.catppuccin.flavor`                | `"mocha"`            | `"latte"` / `"frappe"` / `"macchiato"` / `"mocha"`                                                                                                                                   |
| `theme.catppuccin.accent`                | `"mauve"`            | Accent color (14 options: blue, flamingo, green, lavender, maroon, mauve, peach, pink, red, rosewater, sapphire, sky, teal, yellow)                                                  |
| `theme.scale`                            | `1.0`                | DPI / monitor scale factor                                                                                                                                                           |
| `theme.backgrounds.path`                 | `"nix-black-4k.png"` | Wallpaper filename in archive, direct path, or URL                                                                                                                                   |
| `theme.backgrounds.catppuccinize.enable` | `true`               | Apply Catppuccin color grading to wallpapers via gowall                                                                                                                              |
| `theme.backgrounds.catppuccinize.invert` | `false`              | Invert wallpaper colors before Catppuccin color mapping                                                                                                                              |
| `theme.backgrounds.catppuccinize.accent` | `[<system accent>]`  | Wallpaper accent colors for gowall LUT mapping. `null` = all 14 flavour accents; `["lavender"]` = single accent shaded 14 ways; `["blue" "lavender"]` = cycled accents, each shaded. |
| `theme.radius.small`                     | `6`                  | Border radius for small elements (progress bars)                                                                                                                                     |
| `theme.radius.default`                   | `16`                 | Border radius for windows/panels/notifications                                                                                                                                       |
| `theme.gaps.inner`                       | `8`                  | Gaps between windows                                                                                                                                                                 |
| `theme.gaps.outer`                       | `16`                 | Gaps at screen edges                                                                                                                                                                 |
| `theme.spacing.vertical`                 | `3`                  | Compact vertical spacing for bars and controls.                                                                                                                                      |
| `theme.spacing.workspace`                | `1`                  | Vertical inset for compact workspace buttons.                                                                                                                                        |
| `theme.spacing.workspaceHorizontal`      | `1.5`                | Horizontal inset for compact workspace buttons.                                                                                                                                      |
| `theme.spacing.compact`                  | `4`                  | Compact spacing for icons and small controls.                                                                                                                                        |
| `theme.spacing.control`                  | `8`                  | Spacing inside controls and list elements.                                                                                                                                           |
| `theme.spacing.module`                   | `10`                 | Outer spacing for standalone bar modules.                                                                                                                                            |
| `theme.spacing.content`                  | `16`                 | Spacing between content groups.                                                                                                                                                      |
| `theme.spacing.panel`                    | `18`                 | Padding for standalone panels and overlays.                                                                                                                                          |
| `theme.sizes.launcher`                   | `48`                 | Width of the Waybar launcher button.                                                                                                                                                 |
| `theme.alpha.container`                  | `0.92`               | Alpha for top-level UI containers.                                                                                                                                                   |
| `theme.alpha.surface`                    | `0.80`               | Alpha for secondary surfaces and previews.                                                                                                                                           |
| `theme.alpha.inactive`                   | `0.25`               | Alpha for inactive controls.                                                                                                                                                         |
| `theme.alpha.hover`                      | `0.15`               | Alpha for hovered controls.                                                                                                                                                          |
| `theme.alpha.active`                     | `0.30`               | Alpha for active controls.                                                                                                                                                           |
| `theme.alpha.border`                     | `0.50`               | Alpha for secondary borders.                                                                                                                                                         |
| `theme.alpha.selected`                   | `0.90`               | Alpha for selected controls.                                                                                                                                                         |
| `theme.alpha.highlight`                  | `0.40`               | Alpha for prominent hover and glow states.                                                                                                                                           |
| `theme.alpha.subtle`                     | `0.20`               | Alpha for subtle borders and shadows.                                                                                                                                                |
| `theme.border.width`                     | `2`                  | Window border width                                                                                                                                                                  |
| `theme.border.subtle`                    | `1`                  | Subtle border width for secondary controls.                                                                                                                                          |
| `theme.cursor.name`                      | auto                 | Cursor theme (`"Breeze_Light"` on latte, `"breeze_cursors"` otherwise)                                                                                                               |
| `theme.cursor.package`                   | `kdePackages.breeze` | Cursor theme package                                                                                                                                                                 |
| `theme.cursor.size`                      | `24`                 | Cursor size                                                                                                                                                                          |
| `theme.icons.name`                       | auto                 | Icon theme (`"Papirus-Light"` on latte, `"Papirus-Dark"` otherwise)                                                                                                                  |
| `theme.icons.package`                    | Catppuccin Papirus   | Icon theme package (always Catppuccin Papirus)                                                                                                                                       |
| `theme.wallpaperPath`                    | Generated            | Resolved wallpaper path.                                                                                                                                                             |
| `theme.blurredWallpaperPath`             | Generated            | Resolved blurred wallpaper path.                                                                                                                                                     |
| `theme.snowflakeCatppuccinized`          | Generated            | Resolved Catppuccin snowflake asset.                                                                                                                                                 |
| `theme.qtConfig`                         | Generated            | Resolved Qt configuration.                                                                                                                                                           |

```nix
theme = {
  catppuccin = {
    flavor = "mocha";
    accent = "lavender";
  };
  scale = 1.0;
  backgrounds = {
    path = "nix-black-4k.png";
    catppuccinize = {
      enable = true;
      invert = false;
      accent = [ "lavender" ];
    };
  };
  radius = {
    default = 16;
  };
  gaps = {
    inner = 8;
    outer = 16;
  };
  border = {
    width = 2;
    subtle = 1;
  };
  cursor = {
    size = 24;
  };
};
```

### Font Options

Font options are set in `configuration.nix` and shared with Home Manager.

| Option                        | Default                     | Description                                                                                  |
| ----------------------------- | --------------------------- | -------------------------------------------------------------------------------------------- |
| `fonts.defaults.monospace`    | `"JetBrainsMono Nerd Font"` | Monospace font (terminal, code editors, UI when `uiStyle = "monospace"`)                     |
| `fonts.defaults.sansSerif`    | `"Noto Sans"`               | Sans-serif font (UI when `uiStyle = "sans-serif"`)                                           |
| `fonts.defaults.serif`        | `"Noto Serif"`              | Serif font (fontconfig default)                                                              |
| `fonts.defaults.uiStyle`      | `"monospace"`               | Font style for UI elements: `"monospace"` or `"sans-serif"`                                  |
| `fonts.defaults.ui`           | _(read-only)_               | Resolved font name based on `uiStyle` — used by waybar, dunst, rofi, hyprlock, SDDM, GTK, Qt |
| `fonts.defaults.size`         | `11`                        | Default font size for UI elements                                                            |
| `fonts.defaults.terminalSize` | `fonts.defaults.size`       | Terminal (kitty) font size                                                                   |
| `fonts.defaults.uiPixelSize`  | `floor(size * 4 / 3)`       | Resolved pixel size used by Waybar and other UI components (read-only).                      |

```nix
fonts.defaults = {
  monospace = "JetBrainsMono Nerd Font";
  uiStyle = "sans-serif";
  size = 11;
  terminalSize = 12;
};
```

### Locale Options

Locale options are set in `configuration.nix` and apply system-wide.

| Option            | Default           | Description                          |
| ----------------- | ----------------- | ------------------------------------ |
| `locale.timezone` | `"Europe/Berlin"` | Timezone                             |
| `locale.language` | `"de_DE.UTF-8"`   | System locale; German is the default |
| `locale.keyboard` | `"de"`            | Keyboard layout                      |

```nix
locale = {
  timezone = "Europe/Berlin";
  language = "de_DE.UTF-8";
  keyboard = "de";
};
```

### Display Options

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

| Option                                   | Default       | Description                                                                                                                                      |
| ---------------------------------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `displays.defaults.vrr`                  | `2`           | Default VRR mode for hotplugged/unlisted monitors where output-independent defaults are supported: `0` off, `1` always, `2` fullscreen/automatic |
| `displays.defaults.hdr`                  | `1`           | Default HDR mode for hotplugged/unlisted monitors where supported: `0` off, `1` Steam/Gamescope HDR, `2` full desktop HDR                        |
| `displays.defaultWorkspaceCount`         | `4`           | Number of workspaces created by default.                                                                                                         |
| `displays.monitors`                      | `[]`          | List of monitor configurations                                                                                                                   |
| `displays.monitors.*.name`               | —             | Connector name (`"DP-1"`, `"HDMI-A-1"`, `"eDP-1"`)                                                                                               |
| `displays.monitors.*.edidHash`           | `null`        | Optional stable EDID identifier for display matching.                                                                                            |
| `displays.monitors.*.make`               | `null`        | Optional monitor manufacturer for display matching.                                                                                              |
| `displays.monitors.*.model`              | `null`        | Optional monitor model for display matching.                                                                                                     |
| `displays.monitors.*.serial`             | `null`        | Optional monitor serial number for display matching.                                                                                             |
| `displays.monitors.*.width`              | `1920`        | Horizontal resolution                                                                                                                            |
| `displays.monitors.*.height`             | `1080`        | Vertical resolution                                                                                                                              |
| `displays.monitors.*.refreshRate`        | `60`          | Refresh rate in Hz                                                                                                                               |
| `displays.monitors.*.x`                  | `0`           | Horizontal position offset                                                                                                                       |
| `displays.monitors.*.y`                  | `0`           | Vertical position offset                                                                                                                         |
| `displays.monitors.*.scale`              | `theme.scale` | Scale factor                                                                                                                                     |
| `displays.monitors.*.rotation`           | `"normal"`    | Rotation (`"normal"`, `"90"`, `"180"`, or `"270"`)                                                                                               |
| `displays.monitors.*.wallpaper`          | `null`        | Per-monitor wallpaper; `null` uses the processed default                                                                                         |
| `displays.monitors.*.workspaces`         | `[]`          | Workspace IDs to bind to this monitor (Hyprland only)                                                                                            |
| `displays.monitors.*.vrr`                | `0`           | VRR mode: `0` off, `1` always, `2` fullscreen/automatic                                                                                          |
| `displays.monitors.*.hdr`                | `0`           | HDR mode: `0` off, `1` Steam/Gamescope, `2` full desktop HDR                                                                                     |
| `displays.monitors.*.hdrSdrMaxLuminance` | `450`         | SDR white level in nits for HDR conversion                                                                                                       |

Default behavior and limitations:

- Steam Machine/Gamescope uses `displays.defaults.vrr` and `displays.defaults.hdr != 0` as session-wide fallbacks, so a Steam session can enable adaptive sync and HDR even when the connected output is not listed in `displays.monitors`. It does not override Gamescope color management, virtual white, SDR brightness, or gamut behavior.
- Hyprland uses `displays.defaults.vrr` for its global VRR mode, so hotplugged/unlisted monitors get VRR behavior by default.
- Hyprland applies full desktop HDR only for monitors with `hdr = 2` or unknown outputs when `displays.defaults.hdr = 2`. `hdr = 1` keeps desktop HDR off to avoid flicker while still allowing Steam/Gamescope HDR.
- KDE applies HDR/VRR through `kscreen-doctor`, which needs concrete output names. HDR is enabled only for monitors with `hdr = 2`, with the configured SDR brightness but without overriding color profile or wide-gamut behavior.
- SDDM applies layout and VRR only; HDR is intentionally left off in the greeter so Game Mode and desktop sessions initialize HDR themselves.
- Set `displays.defaults.hdr = 0` on hosts that commonly connect SDR-only projectors/TVs and should not advertise HDR by default.

On Hyprland, a catch-all fallback rule (`preferred, auto, theme.scale`) is always added for hotplugged/unlisted monitors. On KDE, `kscreen-doctor` is run at login via an XDG autostart entry to apply the monitor layout for known outputs.

### Input Options

Input settings define the default pointer and touchpad behavior shared by
Hyprland and KDE. They are intentionally small; device-specific settings are
handled by the desktop session when it starts.

| Option                         | Default | Description                                     |
| ------------------------------ | ------- | ----------------------------------------------- |
| `input.mouse.naturalScroll`    | `true`  | Use natural (reversed) scrolling for mice.      |
| `input.touchpad.naturalScroll` | `true`  | Use natural (reversed) scrolling for touchpads. |

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

### Autostart Apps

Autostart entries are managed by Home Manager and translated to the selected
desktop's session mechanism. Feature modules add their own entries when enabled;
custom entries can be added to the same list.

| Option           | Default           | Description                                             |
| ---------------- | ----------------- | ------------------------------------------------------- |
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

- `features.apps.enable` adds Proton Pass and Vesktop
- `features.apps.enable` plus `features.apps.mumble.enable` adds Mumble
- `features.gaming.enable` adds Steam
- `features.tailscale.enable` adds Trayscale

Each entry contains a display `name` and an `exec` command. KDE writes XDG
autostart entries; Hyprland starts the commands with `exec-once`.

## System Requirements

The default installation expects a Btrfs layout with `@` for `/`, `@home` for
`/home`, `@nix` for `/nix`, and separate `@persist`, `@steam`, `@nextcloud`, and
`@smb` data subvolumes. The `@snapshots` subvolume is listed last because it is
used for snapshot storage rather than normal application data. Full-disk
encryption is also enabled by default.

These requirements are installation constraints rather than runtime feature
settings. Changing the impermanence or encryption defaults requires a matching
disk layout:

```nix
features = {
  # Traditional persistent root (no rollback)
  impermanence = {
    enable = false;
  };

  # Unencrypted disk (not recommended for laptops)
  encryption = {
    enable = false;
  };
};
```

See [INSTALL.md](INSTALL.md#disk-layout) for the required partition and subvolume structure.
