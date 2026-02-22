# Proton Pass Configuration
#
# This module configures Proton Pass password manager:
# - Desktop application
# - CLI with SSH agent support
# - Init script for first-time setup (like tailscale-init)
# - Systemd user service for SSH agent
# - Session persistence
#
# Features:
# - Password management via desktop app
# - SSH key management via CLI
# - Automatic SSH agent startup
# - Persistent login session (survives reboots with impermanence)
# - Filesystem key storage (PROTON_PASS_KEY_PROVIDER=fs)
#
# Initial setup (one-time):
#   proton-pass-init
#
# This will:
# 1. Log you in via web browser (or --interactive for CLI)
# 2. Store session in ~/.config/proton-pass-cli
# 3. Enable and start the SSH agent service
#
# SSH agent:
#   Socket: ~/.ssh/proton-pass-agent.sock
#   Service: systemctl --user status proton-pass-ssh-agent

{ config, pkgs, lib, features, ... }:

{
  #===========================
  # Configuration
  #===========================

  config = lib.mkMerge [

    #---------------------------
    # Base Packages (Always)
    #---------------------------
    {
      home.packages = with pkgs; [
        proton-pass-cli

        # Init script for first-time setup (like tailscale-init)
        (pkgs.writeShellScriptBin "proton-pass-init" ''
          set -e
          echo "Starting Proton Pass CLI login..."
          echo "A browser window will open for authentication."
          ${pkgs.proton-pass-cli}/bin/pass-cli login

          echo ""
          echo "Login successful! Session stored in ~/.config/proton-pass-cli"
          echo ""
          echo "Starting SSH agent service..."
          systemctl --user enable proton-pass-ssh-agent
          systemctl --user start proton-pass-ssh-agent

          echo ""
          echo "Done! Proton Pass is ready."
          echo ""
          echo "SSH agent status:"
          systemctl --user status proton-pass-ssh-agent --no-pager
        '')
      ];

      # Environment variables
      home.sessionVariables = {
        SSH_AUTH_SOCK = "${config.home.homeDirectory}/.ssh/proton-pass-agent.sock";
        # Use filesystem key provider instead of kernel keyring
        # The kernel keyring has issues with keyring-rs library on some systems
        PROTON_PASS_KEY_PROVIDER = "fs";
      };
    }

    #---------------------------
    # Desktop App
    #---------------------------
    (lib.mkIf features.apps.enable {
      home.packages = [ pkgs.proton-pass ];
    })

    #---------------------------
    # SSH Agent
    #---------------------------
    {
      # Systemd user service for Proton Pass SSH agent
      systemd.user.services.proton-pass-ssh-agent = {
        Unit = {
          Description = "Proton Pass SSH Agent";
          After = [ "graphical-session.target" ];
        };

        Service = {
          Type = "simple";
          ExecStart = "${pkgs.proton-pass-cli}/bin/pass-cli ssh-agent start";
          Restart = "on-failure";
          RestartSec = "5s";

          # Use standard socket path for consistency
          Environment = "SSH_AUTH_SOCK=%h/.ssh/proton-pass-agent.sock";
        };

        Install = {
          WantedBy = [ "default.target" ];
        };
      };

      # SSH configuration
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        matchBlocks."*" = {
          identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
          extraOptions = {
            IdentityAgent = "${config.home.homeDirectory}/.ssh/proton-pass-agent.sock";
          };
        };
      };
    }

  ];
}
