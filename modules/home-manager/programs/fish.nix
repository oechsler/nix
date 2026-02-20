# Fish Shell Configuration
#
# This module configures Fish as the interactive shell.
#
# Features:
# - Auto-attach to tmux on startup (SSH or Kitty)
# - fzf integration (Ctrl+O for directories, Ctrl+R for history)
# - Zoxide integration (smart cd)
# - Catppuccin theme (via catppuccin.fish)
# - Trash-cli for safe file deletion
#
# Aliases:
#   cat → bat (syntax highlighting)
#   ll → eza --long (better ls)
#   lt → eza --tree --level 1 (tree view)
#   rm → trash-put (move to trash)
#   trash → trash-list (list trash)
#   unrm → trash-restore (restore from trash)
#
# Functions:
#   cd → z (zoxide + auto-tree)
#   cf → zi (interactive zoxide)
#
# Tmux behavior:
# - SSH: Auto-attach to "ssh" session
# - Kitty: Auto-attach to first non-SSH session or create new

{ pkgs, ... }:

{
  home.packages = [ pkgs.trash-cli ];

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting
      fzf_configure_bindings --directory=\co --history=\cr --processes= --variables= --git_status= --git_log=
      if not set -q TMUX; and begin; set -q KITTY_WINDOW_ID; or set -q SSH_CONNECTION; end
        if set -q SSH_CONNECTION
          exec tmux new-session -A -s ssh
        else
          # Attach to first detached non-SSH session, or create a new one
          for s in (tmux list-sessions -f '#{?session_attached,,#{?#{m:ssh-*,#{session_name}},,1}}' -F '#{session_name}' 2>/dev/null)
            exec tmux attach-session -t "$s"
          end
          exec tmux new-session
        end
      end
    '';
    shellAliases = {
      cat = "bat";
      ll = "eza --long";
      lt = "eza --tree --level 1";
      rm = "trash-put";
      trash = "trash-list";
      unrm = "trash-restore";
    };
    functions = {
      cd = {
        wraps = "z";
        body = ''
          __zoxide_z $argv
          and lt
        '';
      };
      cf = {
        wraps = "zi";
        body = "__zoxide_zi $argv";
      };
    };
    plugins = [
      { name = "fzf.fish"; src = pkgs.fishPlugins.fzf-fish.src; }
    ];
  };

  home.sessionVariables.PAGER = "less";
}
