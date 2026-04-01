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
#   user.name = "samuel";                  # Username (default: "samuel")
#   user.fullName = "Samuel Oechsler";     # Full name (default: "Samuel Oechsler")
#   user.email = "samuel@oechsler.it";     # Email (default: "samuel@oechsler.it")
#   user.github = "oechsler";              # GitHub username (default: "oechsler")
#   user.directories = [ "repos" ];        # Extra home directories (default: ["repos"])
#
# Authentication:
#   - TOTP is the primary auth method (see auth.nix)
#   - Password is a fallback for local services (login, sudo, SDDM)
#   - Plain password in sops (user/password), hashed to yescrypt at boot
#     by user-passwd.service via chpasswd (after sops-install-secrets)
#   - Fallback: "!" (locked) if sops key is missing (e.g. fresh install)
#   - Root account is locked (only sudo access via user account)
#   - Hosts do NOT need to set user.hashedPassword
#
# Security:
#   - Root login disabled (hashedPassword = "!")
#   - Mutable users disabled (passwords managed by NixOS, not passwd command)
#   - User is in wheel group (sudo access)

{ config, pkgs, lib, ... }:

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
      default = "samuel";
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
      default = ../../pictures/sam-memoji.png;
      description = "User profile picture (displayed by SDDM, system settings, etc.)";
    };

    github = lib.mkOption {
      type = lib.types.str;
      default = "oechsler";
      description = "GitHub username (used for SSH key import)";
    };

    # Home Directory
    directories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra directories to create in home (relative to ~, e.g. 'repos')";
    };

    # Authentication
    hashedPassword = lib.mkOption {
      type = lib.types.str;
      default = "!";  # Locked by default — user-passwd.service sets real password at boot
      description = "Hashed password fallback. Usually left at '!' (locked); runtime service overrides it.";
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
      users.root.hashedPassword = "!";  # "!" = account locked

      #---------------------------
      # 2. Declarative User Management
      #---------------------------
      # Why: NixOS should be the single source of truth for user accounts
      # Prevents manual changes via passwd/useradd commands
      mutableUsers = false;

      # Declarative password is "!" (locked) — user-passwd.service sets the
      # real password at boot via chpasswd. Tell NixOS this is intentional.
      allowNoPasswordLogin = true;

      #---------------------------
      # 3. Primary User Account
      #---------------------------
      users.${cfg.name} = {
      isNormalUser = true;
      description = cfg.fullName;

      # Groups
      extraGroups = [
        "networkmanager"  # Manage network connections
        "wheel"           # Sudo access
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
    # Only needed for desktop systems (SDDM, system settings)
    system.activationScripts.userIcon = lib.mkIf (!config.features.server) ''
      mkdir -p /var/lib/AccountsService/icons
      cp ${cfg.icon} /var/lib/AccountsService/icons/${cfg.name}
    '';

    #---------------------------
    # 5. Home Directory Structure
    #---------------------------
    # Default: Create ~/repos directory (desktop only)
    user.directories = lib.optionals (!config.features.server) [ "repos" ];

    # Create directories via tmpfiles (runs on boot)
    systemd.tmpfiles.rules = map (dir:
      "d ${user.home}/${dir} 0755 ${user.name} ${user.group} -"
    ) cfg.directories;

    #---------------------------
    # 5b. Runtime Password via sops
    #---------------------------
    # Why: Plain password stored encrypted in sops, hashed dynamically at boot.
    # Avoids storing any hash in the Nix store or git repo.
    # Falls back to "!" (locked) if sops key is missing (e.g. fresh install).
    sops.secrets."user/password" = {};

    systemd.services.user-passwd = {
      description = "Set user password from sops secret";
      wantedBy = [ "multi-user.target" ];
      after = [ "sops-install-secrets.service" ];
      unitConfig.ConditionPathExists = config.sops.age.keyFile;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        echo "${cfg.name}:$(cat ${config.sops.secrets."user/password".path})" \
          | ${pkgs.shadow}/bin/chpasswd
      '';
    };

    #---------------------------
    # 6. Sudo Configuration
    #---------------------------
    # sudo-rs: memory-safe Rust reimplementation of sudo
    security.sudo.enable = false;
    security.sudo-rs = {
      enable = true;
      extraConfig = ''
        Defaults timestamp_timeout=30  # Re-auth every 30 minutes (default: 5)
      '';
    };
  };
}
