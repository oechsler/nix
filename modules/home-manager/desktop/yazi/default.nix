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
  i18n,
  ...
}:

let
  enableAppPreviews = features.apps.enable;
  enableRichPreviews = features.dev.enable;
  inherit (i18n) translate;

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
    desc = translate "Go to ${bookmark.name}" "Zu ${bookmark.name}";
  }) yaziBookmarks;

  tabKeymaps =
    lib.imap1
      (i: key: {
        on = [
          "<Space>"
          key
        ];
        run = "tab_switch ${toString (i - 1)}";
        desc = translate "Switch to tab ${toString i}" "Zu Tab ${toString i} wechseln";
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
      desc = translate "Toggle media preview metadata" "Mediendaten ein-/ausblenden";
    }
    {
      on = [
        "<Space>"
        "p"
        "i"
      ];
      run = "plugin mediainfo -- toggle-preview";
      desc = translate "Toggle media preview image" "Medienvorschau ein-/ausblenden";
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
        clipboard
        ouch
        restore
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
          desc = translate "Extract here with ouch" "Hier mit ouch entpacken";
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
          desc = translate "Show yazi help" "Yazi-Hilfe anzeigen";
        }
        {
          on = "y";
          run = [
            "yank"
            "plugin clipboard -- --action=copy"
          ];
          desc = translate "Yank and copy to system clipboard" "Kopieren und in die Zwischenablage legen";
        }
        {
          on = "p";
          run = "plugin clipboard -- --action=paste";
          desc = translate "Paste files from system clipboard" "Dateien aus der Zwischenablage einfuegen";
        }
        {
          on = [
            "<Space>"
            "h"
          ];
          run = "tab_switch -1 --relative";
          desc = translate "Switch to previous tab" "Zum vorherigen Tab wechseln";
        }
        {
          on = [
            "<Space>"
            "l"
          ];
          run = "tab_switch 1 --relative";
          desc = translate "Switch to next tab" "Zum nächsten Tab wechseln";
        }
        {
          on = [
            "<Space>"
            "H"
          ];
          run = "tab_swap -1";
          desc = translate "Move tab left" "Tab nach links verschieben";
        }
        {
          on = [
            "<Space>"
            "L"
          ];
          run = "tab_swap 1";
          desc = translate "Move tab right" "Tab nach rechts verschieben";
        }
        {
          on = [
            "<Space>"
            "t"
          ];
          run = "tab_create --current";
          desc = translate "New tab in current directory" "Neuen Tab im aktuellen Verzeichnis öffnen";
        }
        {
          on = [
            "<Space>"
            "q"
          ];
          run = "close";
          desc = translate "Close tab or quit" "Tab schließen oder beenden";
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
          desc = translate "Open recycle bin menu" "Papierkorb-Menü öffnen";
        }
        {
          on = [
            "<Space>"
            "d"
            "u"
          ];
          run = "plugin restore";
          desc = translate "Restore last deleted files" "Zuletzt gelöschte Dateien wiederherstellen";
        }
        {
          on = [
            "<Space>"
            "d"
            "U"
          ];
          run = "plugin restore -- --interactive";
          desc = translate "Restore deleted files interactively" "Gelöschte Dateien interaktiv wiederherstellen";
        }
        {
          on = [
            "<Space>"
            "a"
          ];
          run = "shell --block 'zip -r --junk-paths archiv.zip %s'";
          desc = translate "Zip selected files" "Ausgewaehlte Dateien als ZIP archivieren";
        }
        {
          on = [
            "<Space>"
            "x"
          ];
          run = "shell --block 'unzip -q %h'";
          desc = translate "Extract ZIP file" "ZIP-Datei entpacken";
        }
      ]
      ++ lib.optionals enableAppPreviews mediaKeymaps;
  };

  xdg.desktopEntries.yazi = {
    name = "Yazi";
    genericName = translate "File Manager" "Dateimanager";
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
