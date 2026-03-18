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
# Credential providers:
#   GitHub:  OAuth via GCM
#   Forgejo: generic provider — PAT stored in system keyring after first push
#            Token: https://git.at.oechsler.it/user/settings/applications
#
# Diff/Merge:
#   Tool: nvimdiff
#   Conflict style: diff3 (shows base, ours, theirs)
#
# User info:
#   Name: From user.fullName
#   Email: From user.email
#
# Note: SSH agent is configured in proton-pass.nix

{ config, pkgs, user, ... }:

{
  home.packages = [ pkgs.git-credential-manager ];

  programs = {
    git = {
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

      # Forgejo instance (git.at.oechsler.it) — use generic provider with PAT
      "credential.https://git.at.oechsler.it".provider = "generic";
      "credential.https://git.at.oechsler.it".username = "samuel";
    };

    ignores = [
      "*~"
      ".DS_Store"
      "CLAUDE.md"
      ".github/copilot-instructions.md"
    ];
  };

    delta = {
      enable = true;
      enableGitIntegration = true;
      options = {
        navigate = true;
        side-by-side = true;
      };
    };
  };
}
