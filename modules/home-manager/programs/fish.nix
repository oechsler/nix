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
#   cat → bat, Kitty image preview for images
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

{ lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    file
    trash-cli
  ];

  # Fish 4.3 migrates fish_key_bindings away from universal scope. Distrobox can
  # retrigger that migration when it starts fish with the shared host home, so
  # keep fish's generated cleanup declarative instead of letting it rewrite files.
  xdg.configFile."fish/conf.d/fish_frozen_key_bindings.fish".text = ''
    set --erase --universal fish_key_bindings
  '';

  programs.fish = {
    enable = true;
    shellInit = ''
      # Electron apps: native Wayland (NIXOS_OZONE_WL not available via sessionVariables in NixOS module mode)
      set -gx NIXOS_OZONE_WL 1
      fish_add_path --prepend --global \
        ${pkgs.bat}/bin \
        ${pkgs.eza}/bin \
        ${pkgs.fzf}/bin \
        ${pkgs.kitty}/bin \
        ${pkgs.tmux}/bin \
        ${pkgs.trash-cli}/bin \
        ${pkgs.zoxide}/bin
    '';
    interactiveShellInit = ''
      set fish_greeting
      fzf_configure_bindings --directory=\co --history=\cr --processes= --variables= --git_status= --git_log=
      if not set -q TMUX; and begin; set -q KITTY_WINDOW_ID; or set -q SSH_CONNECTION; end
        if set -q SSH_CONNECTION
          exec ${pkgs.tmux}/bin/tmux new-session -A -s ssh
        else
          # Attach to first detached non-SSH session, or create a new one
          for s in (${pkgs.tmux}/bin/tmux list-sessions -f '#{?session_attached,,#{?#{m:ssh-*,#{session_name}},,1}}' -F '#{session_name}' 2>/dev/null)
            exec ${pkgs.tmux}/bin/tmux attach-session -t "$s"
          end
          exec ${pkgs.tmux}/bin/tmux new-session
        end
      end
    '';
    shellAliases = lib.mkForce {
      eza = "${pkgs.eza}/bin/eza --icons auto --group-directories-first";
      la = "${pkgs.eza}/bin/eza --icons auto --group-directories-first -a";
      ll = "${pkgs.eza}/bin/eza --icons auto --group-directories-first --long";
      lla = "${pkgs.eza}/bin/eza --icons auto --group-directories-first -la";
      ls = "${pkgs.eza}/bin/eza --icons auto --group-directories-first";
      lt = "${pkgs.eza}/bin/eza --icons auto --group-directories-first --tree --level 1";
      rm = "${pkgs.trash-cli}/bin/trash-put";
      trash = "${pkgs.trash-cli}/bin/trash-list";
      unrm = "${pkgs.trash-cli}/bin/trash-restore";
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
      cat = {
        wraps = "bat";
        body = ''
          if test (count $argv) -eq 0
            ${pkgs.bat}/bin/bat
            return
          end

          for arg in $argv
            if string match -q -- '-*' $arg
              ${pkgs.bat}/bin/bat $argv
              return
            end
          end

          for arg in $argv
            if set -q KITTY_WINDOW_ID; and test -f "$arg"
              set mime (${pkgs.file}/bin/file --brief --mime-type -- "$arg")
              if string match -q 'image/*' "$mime"
                ${pkgs.kitty}/bin/kitty +kitten icat -- "$arg"
                continue
              end
            end

            ${pkgs.bat}/bin/bat "$arg"
          end
        '';
      };
    };
    plugins = [
      {
        name = "fzf.fish";
        inherit (pkgs.fishPlugins.fzf-fish) src;
      }
    ];
  };

  home.sessionVariables.PAGER = "less";
}
