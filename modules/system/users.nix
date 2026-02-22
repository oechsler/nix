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
# Password management:
#   - Passwords are declarative (hashed, stored in config)
#   - Generate hash: mkpasswd -m sha-512
#   - Root account is locked (only sudo access via user account)
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
      default = "$6$KGdmWN5KyLLzqxo9$/8Zy.CZ3DBNVr/wWwAO4JmDFzKBsE90roS.w9ryPqSCxwcJiDwLtURWL1oxcFBlfvxBosnCC/Nr2ipk07EZIR.";
      description = "Hashed password (generate with: mkpasswd -m sha-512)";
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
    system.activationScripts.userIcon = ''
      mkdir -p /var/lib/AccountsService/icons
      cp ${cfg.icon} /var/lib/AccountsService/icons/${cfg.name}
    '';

    #---------------------------
    # 5. Home Directory Structure
    #---------------------------
    # Default: Create ~/repos directory
    user.directories = [ "repos" ];

    # Create directories via tmpfiles (runs on boot)
    systemd.tmpfiles.rules = map (dir:
      "d ${user.home}/${dir} 0755 ${user.name} ${user.group} -"
    ) cfg.directories;

    #---------------------------
    # 6. Sudo Configuration
    #---------------------------
    security.sudo.extraConfig = ''
      Defaults pwfeedback       # Show asterisks when typing password
      Defaults lecture = never  # Skip the "with great power" lecture
    '';
  };
}
