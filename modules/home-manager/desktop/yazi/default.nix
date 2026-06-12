# Yazi Configuration
#
# This module configures Yazi as the terminal file manager.
#
# Active when:
#   features.desktop.fileManager = "terminal"

{
  config,
  pkgs,
  lib,
  features,
  ...
}:

let
  enableAppPreviews = features.apps.enable;
  enableRichPreviews = features.development.enable;

  yaziBookmarks =
    config.fileManager.bookmarks
    ++ lib.optionals features.apps.enable [
      {
        name = "Nextcloud";
        path = "${config.home.homeDirectory}/Nextcloud";
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
          " "
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
        " "
        "p"
        "m"
      ];
      run = "plugin mediainfo -- toggle-metadata";
      desc = "Toggle media preview metadata";
    }
    {
      on = [
        " "
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
    shellWrapperName = "y";

    extraPackages =
      with pkgs;
      [
        file
        ouch
        trash-cli
        wl-clipboard
        xclip
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
        clipboard
        ouch
        restore
        ;

      bookmarks = {
        package = pkgs.yaziPlugins.bookmarks;
        setup = true;
        settings = {
          persist = "all";
          desc_format = "parent";
          file_pick_mode = "parent";
          show_keys = true;
          notify = {
            enable = true;
            timeout = 2;
          };
        };
      };

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
            " "
            "i"
          ];
          run = "help";
          desc = "Show yazi help";
        }
        {
          on = "y";
          run = [
            "yank"
            "plugin clipboard -- --action=copy"
          ];
          desc = "Yank and copy to system clipboard";
        }
        {
          on = "<C-p>";
          run = "plugin clipboard -- --action=paste";
          desc = "Paste files from system clipboard";
        }
        {
          on = "m";
          run = "plugin bookmarks save";
          desc = "Save bookmark";
        }
        {
          on = "'";
          run = "plugin bookmarks jump";
          desc = "Jump to bookmark";
        }
        {
          on = [
            " "
            "b"
            "d"
          ];
          run = "plugin bookmarks delete";
          desc = "Delete bookmark";
        }
        {
          on = [
            " "
            "b"
            "D"
          ];
          run = "plugin bookmarks delete_all";
          desc = "Delete all bookmarks";
        }
        {
          on = [
            " "
            "h"
          ];
          run = "tab_switch -1 --relative";
          desc = "Switch to previous tab";
        }
        {
          on = [
            " "
            "l"
          ];
          run = "tab_switch 1 --relative";
          desc = "Switch to next tab";
        }
        {
          on = [
            " "
            "H"
          ];
          run = "tab_swap -1";
          desc = "Move tab left";
        }
        {
          on = [
            " "
            "L"
          ];
          run = "tab_swap 1";
          desc = "Move tab right";
        }
        {
          on = [
            " "
            "t"
          ];
          run = "tab_create --current";
          desc = "New tab in current directory";
        }
        {
          on = [
            " "
            "w"
          ];
          run = "close";
          desc = "Close tab or quit";
        }
      ]
      ++ tabKeymaps
      ++ [
        {
          on = [
            " "
            "d"
            "m"
          ];
          run = "plugin recycle-bin";
          desc = "Open recycle bin menu";
        }
        {
          on = [
            " "
            "d"
            "u"
          ];
          run = "plugin restore";
          desc = "Restore last deleted files";
        }
        {
          on = [
            " "
            "d"
            "U"
          ];
          run = "plugin restore -- --interactive";
          desc = "Restore deleted files interactively";
        }
        {
          on = [
            " "
            "a"
            "z"
          ];
          run = "plugin ouch zip";
          desc = "Archive selected files as zip";
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

  xdg.mimeApps.defaultApplications."inode/directory" = [ "yazi.desktop" ];
}
