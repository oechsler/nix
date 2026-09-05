# Terminal Configuration (Kitty)
#
# This module configures Kitty as the terminal emulator.
#
# Features:
# - Catppuccin theme (via catppuccin.kitty)
# - Monospace font from theme
# - Window padding matching theme gaps
# - No close confirmation
# - Fixed window size for non-Hyprland WMs (96x22 characters)
#
# Keybindings:
#   Alt+Shift+Enter - Send escape sequence (for tmux/vim)
#
# Exposed option:
#   terminal.exec - Command prefix to launch TUI apps
#   Usage: terminal.exec <command>

{
  config,
  pkgs,
  lib,
  fonts,
  theme,
  features,
  ...
}:

let
  palette = config.theme.catppuccinPalette;
  accentColor = palette.${theme.catppuccin.accent}.hex;
  textColor = palette.text.hex;

  info = type: key: {
    inherit type key;
    keyColor = accentColor;
    outputColor = textColor;
  };

  sessionModules = [
    (info "os" "")
    (info "kernel" "")
    (info "packages" "󰏖")
    (info "wm" "󰖲")
    (info "terminal" "")
    (info "shell" "")
  ];
  hardwareModules = [
    (info "cpu" "")
    (info "gpu" "󰢮")
    (info "memory" "")
    (info "swap" "󰓡")
    (info "disk" "󰋊")
  ];
  infoModules = sessionModules ++ hardwareModules;
  titleModule = {
    type = "title";
    key = "󰀄";
    keyColor = accentColor;
    format = "{user-name}@{host-name}";
    outputColor = textColor;
  };
  fastfetchModules = [
    titleModule
  ]
  ++ sessionModules
  ++ [ "break" ]
  ++ hardwareModules
  ++ [
    "break"
    "colors"
  ];
  logoHeight = builtins.length infoModules + 3;
  logoOffsetY = 0;
in
{
  #===========================
  # Options
  #===========================

  options.terminal.exec = lib.mkOption {
    type = lib.types.str;
    default =
      if features.desktop.enable then
        "${pkgs.kitty}/bin/kitty -e"
      else
        "${pkgs.tmux}/bin/tmux new-window";
    readOnly = true;
    description = "Command prefix to launch a TUI app in the terminal (usage: exec <command>)";
  };

  config = {
    programs = {
      fastfetch = {
        settings = {
          logo.type = "none";
          display.separator = "  ";
          modules = fastfetchModules;
        };
      };

      kitty = lib.mkIf features.desktop.enable {
        enable = true;
        font = {
          name = fonts.monospace;
          size = fonts.terminal.size;
        };
        settings = {
          window_padding_width = theme.gaps.outer;
          confirm_os_window_close = 0;
          background_opacity = if features.desktop.wm == "kde" then "1.0" else "0.92";
        }
        // lib.optionalAttrs (features.desktop.wm != "hyprland") {
          remember_window_size = "no";
          initial_window_width = "96c";
          initial_window_height = "22c";
        };
        keybindings = {
          "alt+shift+enter" = "send_text all \\x1b-";
        };
      };

    };

    home.file.".local/bin/fastfetch-image" = lib.mkIf features.desktop.enable {
      executable = true;
      text = ''
        #!${pkgs.fish}/bin/fish

        clear
        set -l window_size (${pkgs.kitty}/bin/kitten icat --print-window-size | string split x)
        set -l terminal_size (stty size | string split ' ')
        set -l window_width $window_size[1]
        set -l window_height $window_size[2]
        set -l terminal_rows $terminal_size[1]
        set -l terminal_columns $terminal_size[2]
        set -l cell_width (math "floor($window_width / $terminal_columns)")
        set -l cell_height (math "floor($window_height / $terminal_rows)")
        set -l image_height ${toString logoHeight}
        set -l max_image_height (math "$terminal_rows - ${toString logoOffsetY} - 1")
        if test $image_height -gt $max_image_height
          set image_height $max_image_height
        end
        set -l image_width (math "ceil($image_height * $cell_height / $cell_width)")
        set -l max_image_width (math "$terminal_columns - 1")
        if test $image_width -gt $max_image_width
          set image_width $max_image_width
        end
        set -l text_column (math "$image_width + 7")
        set -l image_args --unicode-placeholder --scale-up --place $image_width"x"$image_height@0x${toString logoOffsetY}
        if set -q TMUX
          set -a image_args --passthrough tmux
        end
        ${pkgs.kitty}/bin/kitten icat $image_args \
          "${theme.snowflakeCatppuccinized}"
        set -l row 1
        ${pkgs.fastfetch}/bin/fastfetch --logo-type none --pipe false $argv | while read -l line
          printf '\033[%d;%dH%s\n' $row $text_column "$line"
          set row (math $row + 1)
        end
      '';
    };

  };
}
