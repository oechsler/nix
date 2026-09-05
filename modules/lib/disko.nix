# Disko Layout Helper
#
# Shared Btrfs subvolume layout and feature evaluation for host Disko files.

moduleArgs:

let
  config = moduleArgs.config or { };
  features = config.features or { };
  username =
    moduleArgs.username or (
      if config ? user then config.user.name else throw "disko.nix requires username or config.user.name"
    );

  impermanenceEnabled = features.impermanence.enable or false;
  encryptionEnabled = features.encryption.enable or false;
  snapshotsEnabled = features.snapshots.enable or false;
  gamingEnabled = features.gaming.enable or false;
  nextcloudEnabled = features.apps.nextcloud.enable or false;
  smbEnabled = (features.smb.enable or false) && (features.smb.shares or [ ]) != [ ];
  mountOptions = [
    "compress=zstd"
    "noatime"
  ];

  subvolumes = builtins.listToAttrs (
    builtins.filter (entry: entry != null) [
      {
        name = "@";
        value = {
          mountpoint = "/";
          inherit mountOptions;
        };
      }
      {
        name = "@home";
        value = {
          mountpoint = "/home";
          inherit mountOptions;
        };
      }
      {
        name = "@nix";
        value = {
          mountpoint = "/nix";
          inherit mountOptions;
        };
      }
      (
        if impermanenceEnabled then
          {
            name = "@persist";
            value = {
              mountpoint = "/persist";
              inherit mountOptions;
            };
          }
        else
          null
      )
      (
        if snapshotsEnabled then
          {
            name = "@snapshots";
            value = {
              mountpoint = "/.snapshots";
              inherit mountOptions;
            };
          }
        else
          null
      )
      (
        if gamingEnabled then
          {
            name = "@steam";
            value.mountpoint = "/home/${username}/.local/share/Steam";
          }
        else
          null
      )
      (
        if nextcloudEnabled then
          {
            name = "@nextcloud";
            value.mountpoint = "/home/${username}/Nextcloud";
          }
        else
          null
      )
      (
        if smbEnabled then
          {
            name = "@smb";
            value.mountpoint = "/home/${username}/smb";
          }
        else
          null
      )
    ]
  );

  btrfsContent = {
    type = "btrfs";
    extraArgs = [
      "-f"
      "-L"
      "nixos"
    ];
    inherit subvolumes;
  };

  efiLayout = {
    size = "512M";
    type = "EF00";
    content = {
      type = "filesystem";
      format = "vfat";
      mountpoint = "/boot";
      mountOptions = [ "umask=0077" ];
      extraArgs = [
        "-n"
        "BOOT"
      ];
    };
  };

  rootLayout =
    if encryptionEnabled then
      {
        type = "luks";
        name = "cryptroot";
        settings.allowDiscards = true;
        passwordFile = "/var/lib/nixos-install/luks-password";
        content = btrfsContent;
      }
    else
      btrfsContent;

  mainDisk = device: {
    type = "disk";
    inherit device;
    content = {
      type = "gpt";
      partitions = {
        BOOT = efiLayout;
        root = {
          size = "100%";
          content = rootLayout;
        };
      };
    };
  };

  additionalDisk =
    diskName:
    {
      device,
      partitionName ? "data",
      filesystem ? "btrfs",
      mountpoint ? null,
      mountOptions ? [
        "compress=zstd"
        "noatime"
      ],
      content ? null,
      encryption ? encryptionEnabled,
    }:
    let
      filesystemContent =
        if content != null then
          content
        else if mountpoint != null then
          {
            type = "filesystem";
            format = filesystem;
            inherit mountpoint mountOptions;
          }
        else
          throw "additionalDisk requires either content or mountpoint";
      encryptedContent =
        if encryption then
          {
            type = "luks";
            name = "crypt${diskName}";
            settings.allowDiscards = true;
            passwordFile = "/var/lib/nixos-install/luks-password";
            content = filesystemContent;
          }
        else
          filesystemContent;
    in
    {
      type = "disk";
      inherit device;
      content = {
        type = "gpt";
        partitions.${partitionName} = {
          size = "100%";
          content = encryptedContent;
        };
      };
    };
in
{
  inherit additionalDisk mainDisk;
}
