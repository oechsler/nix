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
  };

  config = {
    users.users.${cfg.name} = {
      isNormalUser = true;
      description = cfg.fullName;
      extraGroups = [ "networkmanager" "wheel" "docker" ];
      shell = pkgs.fish;
    };

    # User icon for AccountsService (SDDM, etc.)
    system.activationScripts.userIcon = ''
      mkdir -p /var/lib/AccountsService/icons
      cp ${cfg.icon} /var/lib/AccountsService/icons/${cfg.name}
    '';

    systemd.tmpfiles.rules = [
      "d ${user.home}/repos 0755 ${user.name} ${user.group} -"
      "d ${user.home}/Nextcloud 0755 ${user.name} ${user.group} -"
    ];

    security.sudo.extraConfig = ''
      Defaults pwfeedback
    '';
  };
}
