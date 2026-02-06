{ config, pkgs, inputs, features, lib, ... }:

lib.mkIf features.desktop.enable {
  programs.firefox = {
    enable = true;
    # Native messaging host for Plasma browser integration (media controls, downloads, tabs)
    nativeMessagingHosts = lib.optionals (features.desktop.wm == "kde") [
      pkgs.kdePackages.plasma-browser-integration
    ];
    profiles.default = {
      isDefault = true;
      extensions.force = true;
      extensions.packages = with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
        firefox-color # catppuccin.firefox
        ublock-origin
        bitwarden
        new-tab-override
      ] ++ lib.optionals (features.desktop.wm == "kde") [
        inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}.plasma-integration
      ];

      search = {
        default = "ddg"; # DuckDuckGo
        force = true;
        engines = {
          "google".metaData.hidden = true;
          "bing".metaData.hidden = true;
          "amazondotcom-de".metaData.hidden = true;
          "ebay".metaData.hidden = true;
          "ebay-de".metaData.hidden = true;
          "wikipedia".metaData.hidden = true;
          "wikipedia_de".metaData.hidden = true;
          "wikipedia-de".metaData.hidden = true;
          "leo_ende_de".metaData.hidden = true;
          "ecosia".metaData.hidden = true;
          "perplexity".metaData.hidden = true;
        };
      };

      settings = {
        # Language
        "intl.accept_languages" = "de-DE,de,en-US,en";
        "intl.locale.requested" = "de";

        # Bookmarks toolbar — always hidden
        "browser.toolbars.bookmarks.visibility" = "never";

        # Toolbar layout: sidebar | back forward reload | spacer | urlbar | spacer | bitwarden downloads extensions
        "browser.uiCustomization.state" = builtins.toJSON {
          placements = {
            nav-bar = [
              "sidebar-button"
              "back-button"
              "forward-button"
              "stop-reload-button"
              "customizableui-special-spring1"
              "urlbar-container"
              "customizableui-special-spring2"
              "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action" # Bitwarden
              "downloads-button"
              "unified-extensions-button"
            ];
            toolbar-menubar = [ "menubar-items" ];
            TabsToolbar = [ "tabbrowser-tabs" ];
            PersonalToolbar = [ "personal-bookmarks" ];
            widget-overflow-fixed-list = [];
            unified-extensions-area = [
              "uBlock0_raymondhill_net-browser-action"
              "addon_nicothin_com-browser-action"
            ];
          };
          seen = [
            "developer-button"
            "profiler-button"
            "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action" # Bitwarden
            "uBlock0_raymondhill_net-browser-action"
            "addon_nicothin_com-browser-action" # New Tab Override
          ];
          dirtyAreaCache = [ "nav-bar" "unified-extensions-area" ];
          currentVersion = 21;
          newElementCount = 2;
        };

        # Dark Mode
        "layout.css.prefers-color-scheme.content-override" = 0; # 0 = System
        "ui.systemUsesDarkTheme" = 1; # Force dark theme for UI

        # Startup - restore previous session
        "browser.startup.homepage" = "https://dash.at.oechsler.it";
        "browser.startup.page" = 3; # 3 = Restore previous session

        # Vertical tabs — collapsed, no extra tools
        "sidebar.verticalTabs" = true;
        "sidebar.revamp" = true;
        "sidebar.visibility" = "hide-sidebar";
        "sidebar.main.tools" = "";

        # DRM content (Netflix, Spotify, etc.)
        "media.eme.enabled" = true;
        "media.gmp-widevinecdm.enabled" = true;

        # Protection strict
        "browser.contentblocking.category" = "strict";
        "privacy.trackingprotection.enabled" = true;
        "privacy.trackingprotection.socialtracking.enabled" = true;
        "privacy.annotate_channels.strict_list.enabled" = true;
        "privacy.fingerprintingProtection" = true;
        "privacy.antitracking.enableWebcompat" = false;
        "privacy.globalprivacycontrol.enabled" = true;

        # Disable search suggestions and sponsored content
        "browser.urlbar.suggest.searches" = false;
        "browser.urlbar.suggest.quicksuggest.sponsored" = false;
        "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
        "browser.urlbar.sponsoredTopSites" = false;
        "browser.urlbar.quicksuggest.enabled" = false;
        "browser.urlbar.quicksuggest.dataCollection.enabled" = false;
        "browser.search.suggest.enabled" = false;

        # No remember (password, addresses, ...)
        "signon.rememberSignons" = false;
        "signon.autofillForms" = false;
        "extensions.formautofill.creditCards.enabled" = false;
        "extensions.formautofill.addresses.enabled" = false;

        # New tab minimal
        "browser.newtabpage.enabled" = false;
        "browser.newtabpage.activity-stream.showSponsored" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
        "browser.newtabpage.activity-stream.feeds.topsites" = false;
        "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
        "browser.newtabpage.activity-stream.feeds.section.highlights" = false;
        "browser.newtabpage.activity-stream.feeds.snippets" = false;
        "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
        "browser.newtabpage.activity-stream.showSearch" = false;
        "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features" = false;
        "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons" = false;

        # Telemetry
        "datareporting.healthreport.uploadEnabled" = false;
        "datareporting.policy.dataSubmissionEnabled" = false;
        "toolkit.telemetry.enabled" = false;
        "toolkit.telemetry.unified" = false;
        "toolkit.telemetry.archive.enabled" = false;
        "browser.ping-centre.telemetry" = false;
        "app.shield.optoutstudies.enabled" = false;

        # HTTPS only
        "dom.security.https_only_mode" = true;
        "dom.security.https_only_mode_ever_enabled" = true;

        # Disable translation
        "browser.translations.automaticallyPopup" = false;
        "browser.translations.enable" = false;

        # DNS over HTTPS
        "network.trr.mode" = 5;  # 5 = Off
      };
    };
  };

  catppuccin.firefox = {
    enable = true;
    force = true;
  };
}
