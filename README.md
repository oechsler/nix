# :snowflake: NixOS Config

Hello :wave:,

This repository is my approach to NixOS.

After many years of using Linux, I reached a point where configuring yet
another distribution started to feel like work without an end. I wanted to
write the last Linux configuration of my life: a system that grows with me,
does exactly what I need, and remains flexible, maintainable, and pleasant to
use.

NixOS gave me a way to work towards that idea. I started by learning the
language and the ecosystem, then gradually wrote that knowledge down as a
reproducible configuration for my machines. This repository is the result: a
personal system that is opinionated where it should be, and reusable where it
can be. It is not a finished distribution or a universal answer to NixOS. I
still have a lot to learn, and the configuration will keep changing as my
understanding and my needs change.

Here is a preview of what the configuration looks like today:

![Hyprland Preview](.assets/preview-hyprland.png)

<details>
<summary>Show KDE Plasma Preview</summary>
<br>

![KDE Preview](.assets/preview-kde.png)

</details>

The wallpaper shown in the preview can be purchased from [kram.store](https://kram.store/collections/wallpaper).

## What is here

The configuration is split into reusable modules and host-specific choices:

```
flake.nix                 # Entry point, host discovery, outputs, and checks
hosts/                    # Machine-specific configuration
modules/system/           # Hardware, boot, networking, storage, and security
modules/home-manager/     # Desktop, programs, theming, and user configuration
modules/lib/              # Reusable module helpers
modules/packages/         # Packages maintained by this configuration
backgrounds/              # Encrypted personal background archive
sops/                     # Encrypted secrets
docs/                     # Installation, configuration, and operational guides
```

The flake discovers local hosts automatically from `hosts/`. Shared behavior
lives in modules; a host mostly describes its hardware and the choices that
make it different.

## Getting started

- **Fresh installation:** [docs/INSTALL.md](docs/INSTALL.md)
- **Use this as a base:** [docs/QUICKSTART.md](docs/QUICKSTART.md)
- **Configuration reference:** [docs/CONFIG.md](docs/CONFIG.md)
- **Security model:** [docs/SECURITY.md](docs/SECURITY.md)

## Making it yours

Host configuration is organized by feature groups. Keep only the values that
are different for the machine:

```nix
features = {
  hardware = {
    formFactor = "laptop";
    cpu = "intel";
    gpu = "intel";
  };

  desktop = {
    wm = "kde";
    fileManager = "default";
    browser = {
      type = "librewolf";
      newTabPage = "https://dash.example.com";
    };
  };

  encryption = {
    unlockMethod = "tpm2";
  };

  gaming.enable = false;
  virtualisation.vm.enable = false;
};
```

Most defaults are useful for a normal desktop or laptop. The full set of
overrides, defaults, and examples is in [docs/CONFIG.md](docs/CONFIG.md).

## Using as a flake input

The flake exports `lib.mkHost` and `lib.mkDisko` for use from another
repository. The current interface and a complete example are documented in
[docs/QUICKSTART.md](docs/QUICKSTART.md).
