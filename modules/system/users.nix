{ config, pkgs, lib, ... }:

let
  cfg = config.user;
  user = config.users.users.${cfg.name};
in
{
  options.user = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "samuel";
      description = "Primary username";
    };
    fullName = lib.mkOption {
      type = lib.types.str;
      default = "Samuel Oechsler";
      description = "Full name";
    };
    email = lib.mkOption {
      type = lib.types.str;
      default = "samuel@oechsler.it";
      description = "Email address";
    };
    icon = lib.mkOption {
      type = lib.types.path;
      default = ../../pictures/sam-memoji.png;
      description = "User profile picture";
    };
    github = lib.mkOption {
      type = lib.types.str;
      default = "oechsler";
      description = "GitHub username (used for SSH key import)";
    };
    directories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra directories to create in the user's home (relative to ~)";
    };
  };

  config = {
    users.users.${cfg.name} = {
      isNormalUser = true;
      description = cfg.fullName;
      extraGroups = [ "networkmanager" "wheel" ];
      shell = pkgs.fish;
    };

    # User icon for AccountsService (SDDM, etc.)
    system.activationScripts.userIcon = ''
      mkdir -p /var/lib/AccountsService/icons
      cp ${cfg.icon} /var/lib/AccountsService/icons/${cfg.name}
    '';

    user.directories = [ "repos" "Nextcloud" ];

    systemd.tmpfiles.rules = map (dir:
      "d ${user.home}/${dir} 0755 ${user.name} ${user.group} -"
    ) cfg.directories;

    security.sudo.extraConfig = ''
      Defaults pwfeedback
    '';
  };
}
