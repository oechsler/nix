# NixOS Config

My personal NixOS configurations using Flakes and Home-Manager.

![Hyprland Preview](.assets/preview-hyprland.png)

<details>
<summary>Show KDE Plasma Preview</summary>
<br>

![KDE Preview](.assets/preview-kde.png)

</details>

## Structure

```
hosts/              # Per-host configs
modules/
  system/           # Boot, networking, impermanence, snapshots
  desktop/          # Hyprland, KDE, SDDM
  home-manager/     # User programs, dotfiles, theming
sops/               # Encrypted secrets
```

## Quick Start

- **Fresh install:** [docs/INSTALL.md](docs/INSTALL.md)
- **Use as base for your config:** [docs/QUICKSTART.md](docs/QUICKSTART.md)
- **Configuration reference:** [docs/CONFIG.md](docs/CONFIG.md)
- **Security overview:** [docs/SECURITY.md](docs/SECURITY.md)

## Host Overrides

Example host overrides. Keep the values that apply to the host and remove the rest:

```nix
features = {
  hardware = {
    formFactor = "laptop";                         # "desktop" or "laptop"
    cpu = "amd";                                   # "amd" or "intel"
    gpu = "amd";                                   # "amd" or "intel"
  };

  desktop = {
    wm = "kde";                                    # "hyprland" or "kde"
    login = "greeter";                             # "greeter" or "autologin"
    fileManager = "default";                       # "default" or "terminal"
    browser = {
      type = "librewolf";                          # "librewolf" or "firefox"
      homepage = "https://dash.example.com";
    };
  };

  impermanence.enable = true;                       # Root rollback on boot
  encryption.unlockMethod = "tpm2";                 # "tpm2", "yubikey", or "password"
  gaming.enable = true;                             # Steam and gaming tools
  dev.enable = true;                                # Development tools
  virtualisation.enable = true;                     # Containers and VMs
  compat.enable = true;                             # nix-ld/glibc compatibility
};
```

Less common options, including browser cookie exceptions and display defaults,
are documented in `docs/CONFIG.md`.

```nix
displays.defaults = {
  hdr = 1;  # 0=off, 1=Steam, 2=full desktop
  vrr = 2;  # VRR mode for unknown displays
};
```

## Using as Flake Input

This flake exports `lib.mkHost` for building NixOS systems. See [docs/QUICKSTART.md](docs/QUICKSTART.md) for setup guide.
