# Proton Pass Configuration
#
# This module configures Proton Pass password manager for both desktop and server:
# - CLI for password/secrets retrieval (always enabled)
# - Init script for easy login (always enabled)
# - SSH agent for SSH key management (always enabled, opt-in via login)
# - Desktop app (desktop only, requires features.apps.enable)
#
# Features:
# - Password/secrets management via CLI (works on servers!)
# - SSH key management via SSH agent (works on servers!)
# - Persistent login session (survives reboots with impermanence)
# - Filesystem key storage (PROTON_PASS_KEY_PROVIDER=fs)
# - Opt-in activation: SSH agent only works after proton-pass-init
#
# Initial setup (one-time):
#   proton-pass-init
#
# This will:
# 1. Log you in (browser on desktop, interactive CLI on server)
# 2. Store session in ~/.local/share/proton-pass-cli
# 3. Restart the SSH agent service (enables SSH key access)
#
# Usage:
#   Desktop: proton-pass-init  (opens browser)
#   Server:  proton-pass-init  (prompts for username/password)
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
    # Base (Always - Server + Desktop)
    #---------------------------
    {
      home.packages = with pkgs; [
        proton-pass-cli

        # Init script for first-time setup
        # Desktop: Browser-based login
        # Server: Interactive CLI login
        (pkgs.writeShellScriptBin "proton-pass-init" ''
          set -e
          echo "Starting Proton Pass CLI login..."
          echo "A browser window will open for authentication."
          ${pkgs.proton-pass-cli}/bin/pass-cli login

          echo ""
          echo "Login successful! Session stored in ~/.local/share/proton-pass-cli"
          echo ""
          echo "Restarting SSH agent service..."
          systemctl --user restart proton-pass-ssh-agent

          echo ""
          echo "Done! Proton Pass is ready."
          echo ""
          echo "SSH agent status:"
          systemctl --user status proton-pass-ssh-agent --no-pager
        '')
      ];

      # PROTON_PASS_KEY_PROVIDER for all shells (bash, fish, etc.)
      # Use filesystem key storage instead of kernel keyring
      home.sessionVariables.PROTON_PASS_KEY_PROVIDER = "fs";

      # Fish-specific: Also set in shellInit for immediate availability
      programs.fish.shellInit = ''
        set -gx PROTON_PASS_KEY_PROVIDER "fs"
      '';
    }

    #---------------------------
    # SSH Agent Environment
    #---------------------------
    {
      # SSH_AUTH_SOCK for Proton Pass SSH agent
      programs.fish.shellInit = ''
        set -gx SSH_AUTH_SOCK "${config.home.homeDirectory}/.ssh/proton-pass-agent.sock"
      '';
    }

    #---------------------------
    # Desktop App
    #---------------------------
    (lib.mkIf features.apps.enable {
      home.packages = [ pkgs.proton-pass ];
    })

    #---------------------------
    # SSH Agent Service
    #---------------------------
    {
      # Systemd user service for Proton Pass SSH agent
      # Opt-in: Requires proton-pass-init to create session
      # Without login, service will fail harmlessly and retry
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

          # Environment variables for the SSH agent
          Environment = [
            "SSH_AUTH_SOCK=%h/.ssh/proton-pass-agent.sock"
            "PROTON_PASS_KEY_PROVIDER=fs"  # Use filesystem key storage
          ];
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
