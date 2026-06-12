# Development Tools Configuration
#
# This module configures general CLI tools.
#
# Configuration:
# - GitHub CLI enabled
# - Git protocol: SSH (not HTTPS)
# - Git credential helper: Disabled (using git-credential-manager from git.nix)
# - Ouch for archive compression/extraction
#
# Usage:
#   gh pr create
#   gh issue list
#   gh repo clone owner/repo

{ pkgs, ... }:

{
  home.packages = [ pkgs.ouch ];

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = false;
    settings.git_protocol = "ssh";
  };

}
