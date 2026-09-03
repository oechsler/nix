# User Account Configuration
#
# This module configures:
# 1. Primary user account (username, full name, email, etc.)
# 2. User profile picture (AccountsService icon)
# 3. Home directory structure
# 4. Root account lockdown
# 5. Sudo configuration
#
# Configuration options:
#   user.name = "samuel";                  # Username (default: flake.primaryUser)
#   user.fullName = "Samuel Oechsler";     # Full name (default: "Samuel Oechsler")
#   user.email = "samuel@oechsler.it";     # Email (default: "samuel@oechsler.it")
#   user.keys = "https://git.at.oechsler.it/samuel.keys"; # SSH public keys URL or local file
#   user.directories = [ "repos" ];        # Extra home directories (default: ["repos"])
#
# Authentication:
#   - TOTP is the primary auth method (see auth.nix)
#   - Password is a fallback for local services (login, sudo, SDDM)
#   - Password authentication is provided by SSSD/LLDAP (see ldap.nix)
#   - Root account is locked (only sudo access via user account)
#   - The local shadow password remains locked; the account is still declared
#     locally for its home directory, UID/GID, and desktop session.
#
# Security:
#   - Root login disabled (hashedPassword = "!")
#   - Mutable users disabled (passwords managed by NixOS, not passwd command)
#   - User is in wheel group (sudo access)

{
  config,
  primaryUser,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.user;
  user = config.users.users.${cfg.name};
in
{
  #===========================
  # Options
  #===========================

  options.user = {
    # User Identity
    name = lib.mkOption {
      type = lib.types.str;
      default = primaryUser;
      description = "Primary username (login name)";
    };

    fullName = lib.mkOption {
      type = lib.types.str;
      default = "Samuel Oechsler";
      description = "Full name (display name)";
    };

    email = lib.mkOption {
      type = lib.types.str;
      default = "samuel@oechsler.it";
      description = "Email address (used by git, etc.)";
    };

    # User Profile
    icon = lib.mkOption {
      type = lib.types.path;
      default = ../../.assets/sam-memoji.png;
      description = "User profile picture (displayed by SDDM, system settings, etc.)";
    };

    keys = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
      default = "https://git.at.oechsler.it/samuel.keys";
      description = "SSH public keys source: URL or local file path; null or an empty string disables local key synchronization";
    };

    # Home Directory
    directories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra directories to create in home (relative to ~, e.g. 'repos')";
    };

    # Authentication
    hashedPassword = lib.mkOption {
      type = lib.types.str;
      default = "!"; # Locked by default — user-passwd.service sets real password at boot
      description = "Local shadow password fallback; LDAP provides authentication.";
    };
  };

  #===========================
  # Configuration
  #===========================

  config = {

    #---------------------------
    # 1. Root Account Lockdown
    users = {
      #---------------------------
      # Why: Disable direct root login for security
      # Users must use sudo via their personal account (audit trail)
      users.root.hashedPassword = "!"; # "!" = account locked

      #---------------------------
      # 2. Declarative User Management
      #---------------------------
      # Why: NixOS should be the single source of truth for user accounts
      # Prevents manual changes via passwd/useradd commands
      mutableUsers = false;

      # Declarative password is "!" (locked) — user-passwd.service sets the
      # real password at boot via chpasswd. Tell NixOS this is intentional.
      # Required while the declarative shadow password is locked and the real
      # password is installed from SOPS at boot by user-passwd.service.
      allowNoPasswordLogin = true;

      #---------------------------
      # 3. Primary User Account
      #---------------------------
      users.${cfg.name} = {
        isNormalUser = true;
        description = cfg.fullName;

        # Groups
        extraGroups = [
          "networkmanager" # Manage network connections
          "wheel" # Sudo access
          "i2c" # Access I2C devices
        ];

        shell = pkgs.fish;
        inherit (cfg) hashedPassword;
      };
    };

    #---------------------------
    # 4. User Profile Picture
    #---------------------------
    # AccountsService provides user icons to SDDM, system settings, etc.
    # Icons must be in /var/lib/AccountsService/icons/<username>
    # Used by desktop account settings (SDDM, system settings)
    system.activationScripts.userIcon = ''
      mkdir -p /var/lib/AccountsService/icons
      cp ${lib.escapeShellArg cfg.icon} ${lib.escapeShellArg "/var/lib/AccountsService/icons/${cfg.name}"}
    '';

    #---------------------------
    # 5. Home Directory Structure
    #---------------------------
    # Create the default ~/repos directory.
    user.directories = lib.mkDefault [ "repos" ];

    # When LDAP is disabled, restore the local SOPS-managed password.
    sops.secrets."user/password" = lib.mkIf (!config.features.auth.ldap.enable) { };

    system.activationScripts.user-passwd = lib.mkIf (!config.features.auth.ldap.enable) {
      deps = [ "users" ];
      text = ''
        password_file=${lib.escapeShellArg config.sops.secrets."user/password".path}
        if [ -f "$password_file" ]; then
          printf '%s:%s\n' ${lib.escapeShellArg cfg.name} "$(cat "$password_file")" \
            | ${pkgs.shadow}/bin/chpasswd
        fi
      '';
    };

    systemd.services.user-passwd = lib.mkIf (!config.features.auth.ldap.enable) {
      description = "Set user password from sops secret";
      wantedBy = [ "multi-user.target" ];
      after = [ "sops-install-secrets.service" ];
      unitConfig.ConditionPathExists = config.sops.age.keyFile;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        password_file=${lib.escapeShellArg config.sops.secrets."user/password".path}
        printf '%s:%s\n' ${lib.escapeShellArg cfg.name} "$(cat "$password_file")" \
          | ${pkgs.shadow}/bin/chpasswd
      '';
    };

    # Create directories via tmpfiles (runs on boot)
    systemd.tmpfiles.rules = map (
      dir: "d ${user.home}/${dir} 0755 ${user.name} ${user.group} -"
    ) cfg.directories;

    #---------------------------
    # 6. Sudo Configuration
    #---------------------------
    # sudo-rs: memory-safe Rust reimplementation of sudo
    security.sudo.enable = false;
    security.sudo-rs = {
      enable = true;
      extraConfig = ''
        Defaults timestamp_timeout=30
      '';
    };
  };
}
