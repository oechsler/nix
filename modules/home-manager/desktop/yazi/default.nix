# Yazi Configuration
#
# This module configures Yazi as the terminal file manager.
#
# Active when:
#   features.desktop.fileManager = "terminal"
#
# Keybindings (leader = Space):
#   g+1-9/0            - Open configured bookmark 1-10
#   Space+i            - Show help
#   y / p              - Yank / paste files (y also copies to the system clipboard)
#   Space+h/l          - Previous / next tab
#   Space+H/L          - Move tab left / right
#   Space+t            - New tab in the current directory
#   Space+q            - Close tab or quit Yazi
#   Space+1-9/0        - Switch to tab 1-10
#   Space+d+m          - Open recycle bin
#   Space+d+u          - Restore last deleted files
#   Space+d+U          - Restore files interactively
#   Space+.            - Toggle hidden files
#   Space+p+m          - Toggle media metadata (when enabled)
#   Space+p+i          - Toggle media preview image (when enabled)

{
  config,
  pkgs,
  lib,
  features,
  ...
}:

let
  enableAppPreviews = features.apps.enable;
  enableRichPreviews = features.dev.enable;

  yaziBookmarks = config.fileManager.bookmarks ++ [
    {
      name = "Wechselmedien";
      path = "/mnt/removable";
      icon = "drive-removable-media";
    }
  ];

  staticBookmarkKeymaps = lib.imap1 (i: bookmark: {
    on = [
      "g"
      (toString i)
    ];
    run = "cd '${bookmark.path}'";
    desc = "Go to ${bookmark.name}";
  }) yaziBookmarks;

  tabKeymaps =
    lib.imap1
      (i: key: {
        on = [
          "<Space>"
          key
        ];
        run = "tab_switch ${toString (i - 1)}";
        desc = "Switch to tab ${toString i}";
      })
      [
        "1"
        "2"
        "3"
        "4"
        "5"
        "6"
        "7"
        "8"
        "9"
        "0"
      ];

  appPreloaders = [
    {
      mime = "{audio,video,image}/*";
      run = "mediainfo";
    }
    {
      mime = "application/subrip";
      run = "mediainfo";
    }
    {
      mime = "application/pdf";
      run = "pdf";
    }
    {
      mime = "application/openxmlformats-officedocument.*";
      run = "office";
    }
    {
      mime = "application/oasis.opendocument.*";
      run = "office";
    }
    {
      mime = "application/ms-*";
      run = "office";
    }
    {
      mime = "application/msword";
      run = "office";
    }
    {
      url = "*.docx";
      run = "office";
    }
  ];

  appPreviewers = [
    {
      mime = "application/pdf";
      run = "pdf";
    }
    {
      mime = "{audio,video,image}/*";
      run = "mediainfo";
    }
    {
      mime = "application/subrip";
      run = "mediainfo";
    }
    {
      mime = "application/openxmlformats-officedocument.*";
      run = "office";
    }
    {
      mime = "application/oasis.opendocument.*";
      run = "office";
    }
    {
      mime = "application/ms-*";
      run = "office";
    }
    {
      mime = "application/msword";
      run = "office";
    }
    {
      url = "*.docx";
      run = "office";
    }
  ];

  richPreviewers = [
    {
      url = "*.csv";
      run = "rich-preview";
    }
    {
      url = "*.ipynb";
      run = "rich-preview";
    }
    {
      url = "*.json";
      run = "rich-preview";
    }
    {
      url = "*.md";
      run = "rich-preview";
    }
    {
      url = "*.rst";
      run = "rich-preview";
    }
  ];

  mediaKeymaps = [
    {
      on = [
        "<Space>"
        "p"
        "m"
      ];
      run = "plugin mediainfo -- toggle-metadata";
      desc = "Toggle media preview metadata";
    }
    {
      on = [
        "<Space>"
        "p"
        "i"
      ];
      run = "plugin mediainfo -- toggle-preview";
      desc = "Toggle media preview image";
    }
  ];
in
{
  programs.yazi = {
    enable = true;
    shellWrapperName = "yy";

    extraPackages =
      with pkgs;
      [
        file
        ouch
        trash-cli
        unzip
        wl-clipboard
        xclip
        zip
      ]
      ++ lib.optionals enableAppPreviews [
        ffmpeg
        ffmpegthumbnailer
        imagemagick
        mediainfo
        poppler-utils
      ]
      ++ lib.optionals enableRichPreviews [
        jq
        rich-cli
      ];

    plugins = {
      inherit (pkgs.yaziPlugins)
        ouch
        restore
        wl-clipboard
        ;

      git = {
        package = pkgs.yaziPlugins.git;
        setup = true;
        settings.order = 1500;
      };

      recycle-bin = {
        package = pkgs.yaziPlugins.recycle-bin;
        setup = true;
      };
    }
    // lib.optionalAttrs enableAppPreviews {
      inherit (pkgs.yaziPlugins)
        mediainfo
        office
        ;
    }
    // lib.optionalAttrs enableRichPreviews {
      rich-preview = pkgs.yaziPlugins.rich-preview;
    };

    settings = {
      opener.extract = [
        {
          run = ''ouch d -y "$@"'';
          desc = "Extract here with ouch";
          for = "unix";
        }
      ];

      plugin = {
        prepend_fetchers = [
          {
            id = "git";
            url = "*";
            run = "git";
            group = "git";
          }
          {
            id = "git";
            url = "*/";
            run = "git";
            group = "git";
          }
        ];

        prepend_preloaders = lib.optionals enableAppPreviews appPreloaders;
        prepend_previewers = [
          {
            mime = "application/{*zip,tar,bzip2,7z*,rar,xz,zstd,java-archive}";
            run = "ouch";
          }
        ]
        ++ lib.optionals enableAppPreviews appPreviewers
        ++ lib.optionals enableRichPreviews richPreviewers;
      };
    };

    keymap.mgr.prepend_keymap =
      staticBookmarkKeymaps
      ++ [
        {
          on = [
            "<Space>"
            "i"
          ];
          run = "help";
          desc = "Show yazi help";
        }
        {
          on = "y";
          run = [
            "yank"
            "plugin wl-clipboard -- --action=copy"
          ];
          desc = "Yank and copy to system clipboard";
        }
        {
          on = "p";
          run = "paste";
          desc = "Paste yanked files";
        }
        {
          on = [
            "<Space>"
            "."
          ];
          run = "hidden toggle";
          desc = "Toggle hidden files";
        }
        {
          on = [
            "<Space>"
            "h"
          ];
          run = "tab_switch -1 --relative";
          desc = "Switch to previous tab";
        }
        {
          on = [
            "<Space>"
            "l"
          ];
          run = "tab_switch 1 --relative";
          desc = "Switch to next tab";
        }
        {
          on = [
            "<Space>"
            "H"
          ];
          run = "tab_swap -1";
          desc = "Move tab left";
        }
        {
          on = [
            "<Space>"
            "L"
          ];
          run = "tab_swap 1";
          desc = "Move tab right";
        }
        {
          on = [
            "<Space>"
            "t"
          ];
          run = "tab_create --current";
          desc = "New tab in current directory";
        }
        {
          on = [
            "<Space>"
            "q"
          ];
          run = "close";
          desc = "Close tab or quit";
        }
      ]
      ++ tabKeymaps
      ++ [
        {
          on = [
            "<Space>"
            "d"
            "m"
          ];
          run = "plugin recycle-bin";
          desc = "Open recycle bin menu";
        }
        {
          on = [
            "<Space>"
            "d"
            "u"
          ];
          run = "plugin restore";
          desc = "Restore last deleted files";
        }
        {
          on = [
            "<Space>"
            "d"
            "U"
          ];
          run = "plugin restore -- --interactive";
          desc = "Restore deleted files interactively";
        }
        {
          on = [
            "<Space>"
            "a"
          ];
          run = "shell --block 'zip -r --junk-paths archiv.zip %s'";
          desc = "Zip selected files";
        }
        {
          on = [
            "<Space>"
            "x"
          ];
          run = "shell --block 'unzip -q %h'";
          desc = "Extract ZIP file";
        }
      ]
      ++ lib.optionals enableAppPreviews mediaKeymaps;
  };

  xdg.desktopEntries.yazi = {
    name = "Yazi";
    genericName = "File Manager";
    exec = "kitty yazi %U";
    icon = "folder";
    terminal = false;
    categories = [
      "System"
      "FileManager"
    ];
    mimeType = [ "inode/directory" ];
  };

  xdg.mimeApps.defaultApplications = {
    "inode/directory" = [ "yazi.desktop" ];
    "inode/mount-point" = [ "yazi.desktop" ];
  };

  programs.fish.functions.y = {
    body = ''
      set -l tmp (mktemp -t yazi-cwd.XXXXXX)
      yazi --cwd-file="$tmp" $argv
      if test -f "$tmp"
        set -l cwd (cat "$tmp")
        command rm -f "$tmp"
        if test -n "$cwd" -a "$cwd" != "$PWD"
          builtin cd "$cwd"
        end
      end
    '';
  };
}
