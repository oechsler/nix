# Disko Layout Helper
#
# Shared Btrfs subvolume layout and feature evaluation for host Disko files.

moduleArgs:

let
  config = moduleArgs.config or { };
  features = config.features or { };
  username =
    moduleArgs.username or (
      if config ? user then
        config.user.name
      else
        throw "disko-layout.nix requires username or config.user.name"
    );

  impermanenceEnabled = features.impermanence.enable or false;
  encryptionEnabled = features.encryption.enable or false;
  snapshotsEnabled = features.snapshots.enable or false;
  gamingEnabled = features.gaming.enable or false;
  nextcloudEnabled = features.apps.nextcloud.enable or false;
  smbEnabled = (features.smb.enable or false) && (features.smb.shares or [ ]) != [ ];
  sshEnabled = !impermanenceEnabled && (features.ssh.enable or false);
  libvirtEnabled =
    !impermanenceEnabled
    && (features.virtualisation.enable or false)
    && (features.virtualisation.vm.enable or false);

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
          {
            name = "@var";
            value = {
              mountpoint = "/var";
              inherit mountOptions;
            };
          }
      )
      (
        if sshEnabled then
          {
            name = "@ssh";
            value.mountpoint = "/etc/ssh";
          }
        else
          null
      )
      (
        if libvirtEnabled then
          {
            name = "@libvirt";
            value.mountpoint = "/etc/libvirt";
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
in
if encryptionEnabled then
  {
    type = "luks";
    name = "cryptroot";
    settings.allowDiscards = true;
    passwordFile = "/var/lib/nixos-install/luks-password";
    content = btrfsContent;
  }
else
  btrfsContent
