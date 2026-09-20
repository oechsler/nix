# Git Configuration
#
# This module configures Git version control.
#
# Features:
# - SSH commit signing (with ~/.ssh/id_ed25519.pub)
# - Git Credential Manager for authentication
# - Neovim as editor and diff/merge tool
# - Rebase-friendly pulls and conflict reuse
# - Main as default branch
# - Global gitignore for common files
#
# Credential providers:
#   GitHub:  OAuth via GCM
#   Forgejo: generic provider — PAT stored in system keyring after first push
#            Token: https://git.at.oechsler.it/user/settings/applications
#
# Diff/Merge:
#   Pager: delta with the active Catppuccin flavour
#   Tool: nvimdiff
#   Conflict style: zdiff3 (shows base inline with ours/theirs)
#
# User info:
#   Name: From user.fullName
#   Email: From user.email
#
# Note: SSH agent is configured in proton-pass.nix

{
  config,
  pkgs,
  user,
  theme,
  lib,
  ...
}:

let
  capitalize = value: (lib.toUpper (builtins.substring 0 1 value)) + (builtins.substring 1 99 value);
  deltaTheme = "Catppuccin ${capitalize theme.catppuccin.flavor}";
in
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
        alias = {
          st = "status --short --branch";
          d = "diff";
          staged = "diff --cached";
          patch = "add --patch";
          unstage = "restore --staged";
          unstage-all = "restore --staged :/";
          last = "log -1 HEAD";
          lg = "log --graph --decorate --all";
          amend = "commit --amend --no-edit";
          fixup = "commit --fixup";
        };
        user.name = user.fullName;
        user.email = user.email;

        core.editor = "nvim";
        sequence.editor = "nvim";
        init.defaultBranch = "main";
        branch.sort = "-committerdate";
        tag.sort = "version:refname";
        pull = {
          rebase = true;
          autoStash = true;
        };
        rebase = {
          autoStash = true;
          autoSquash = true;
          updateRefs = true;
          abbreviateCommands = true;
        };
        rerere = {
          enabled = true;
          autoupdate = true;
        };
        fetch = {
          prune = true;
          pruneTags = true;
          writeCommitGraph = true;
        };
        push = {
          autoSetupRemote = true;
          followTags = true;
        };
        diff = {
          algorithm = "histogram";
          indentHeuristic = true;
          colorMoved = "zebra";
          colorMovedWS = "allow-indentation-change";
        };
        diff.tool = "nvimdiff";
        difftool.prompt = false;

        merge = {
          tool = "nvimdiff";
          conflictstyle = "zdiff3";
        };
        mergetool = {
          prompt = false;
          keepBackup = false;
        };

        credential = {
          helper = "${pkgs.git-credential-manager}/bin/git-credential-manager";
          credentialStore = "secretservice";

          # GitHub OAuth support
          "https://github.com".provider = "github";

          # Forgejo instance (git.at.oechsler.it) — use generic provider with PAT
          "https://git.at.oechsler.it".provider = "generic";
          "https://git.at.oechsler.it".username = "samuel";
        };
      };

      ignores = [
        "*~"
        ".DS_Store"
        "AGENTS.md"
        "VAULT.md"
        ".opencode/opencode.json"
      ];
    };

    delta = {
      enable = true;
      enableGitIntegration = true;
      options = {
        navigate = true;
        side-by-side = true;
        line-numbers = true;
        syntax-theme = deltaTheme;
        hyperlinks = true;
      };
    };
  };
}
