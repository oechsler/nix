# Development Tools Configuration
#
# This module configures GitHub CLI (gh).
#
# Configuration:
# - GitHub CLI enabled
# - Git protocol: SSH (not HTTPS)
# - Git credential helper: Disabled (using git-credential-manager from git.nix)
#
# Usage:
#   gh pr create
#   gh issue list
#   gh repo clone owner/repo

_:

{
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = false;
    settings.git_protocol = "ssh";
  };

}
