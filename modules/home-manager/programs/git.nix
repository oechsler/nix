# Git Configuration
#
# This module configures Git version control.
#
# Features:
# - SSH commit signing (with ~/.ssh/id_ed25519.pub)
# - Git Credential Manager for authentication
# - Neovim as diff/merge tool
# - Pull with rebase and auto-stash
# - Main as default branch
# - Global gitignore for common files
#
# Diff/Merge:
#   Tool: nvimdiff
#   Conflict style: diff3 (shows base, ours, theirs)
#
# User info:
#   Name: From user.fullName
#   Email: From user.email

{ config, pkgs, user, ... }:

{
  home.packages = [ pkgs.git-credential-manager ];

  programs.git = {
    enable = true;

    signing = {
      key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
      signByDefault = true;
      format = "ssh";
    };

    settings = {
      user.name = user.fullName;
      user.email = user.email;

      init.defaultBranch = "main";
      pull.rebase = true;
      pull.autoStash = true;

      diff.tool = "nvimdiff";
      difftool.prompt = false;

      merge.tool = "nvimdiff";
      merge.conflictstyle = "diff3";
      mergetool.prompt = false;

      credential.helper = "${pkgs.git-credential-manager}/bin/git-credential-manager";
      credential.credentialStore = "secretservice";

      # GitHub OAuth support
      "credential.https://github.com".provider = "github";
    };

    ignores = [
      "*~"
      ".DS_Store"
      "CLAUDE.md"
      ".github/copilot-instructions.md"
    ];
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      side-by-side = true;
    };
  };

  # Bitwarden SSH Agent
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks."*" = {
      identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
      extraOptions = {
        IdentityAgent = "${config.home.homeDirectory}/.bitwarden-ssh-agent.sock";
      };
    };
  };

  home.sessionVariables = {
    SSH_AUTH_SOCK = "${config.home.homeDirectory}/.bitwarden-ssh-agent.sock";
  };
}
