# Browser Configuration (Firefox)
#
# This module configures Firefox as the default web browser.
#
# Features:
# - Catppuccin color scheme (via firefox-color extension)
# - Privacy-focused extensions (uBlock Origin, Bitwarden)
# - KDE Plasma integration (media controls, downloads, tabs)
# - Custom toolbar layout
# - DuckDuckGo as default search engine
# - German language preference
# - New tab override
#
# Extensions:
# - firefox-color - Catppuccin theme
# - ublock-origin - Ad blocker
# - bitwarden - Password manager
# - new-tab-override - Custom new tab page
# - plasma-integration (KDE only) - Desktop integration
#
# Search:
# - Default: DuckDuckGo
# - Hidden: Google, Bing, Amazon, eBay, Wikipedia, LEO, Ecosia, Perplexity
#
# Toolbar layout:
#   Back | Forward | Reload | Spacer | URL bar | Spacer | Downloads | Bitwarden

{ pkgs, inputs, features, fonts, lib, ... }:

{
  #===========================
  # Configuration
  #===========================

  config = lib.mkIf features.desktop.enable {
    #---------------------------
    # Firefox Configuration
    #---------------------------

    programs.firefox = {
    enable = true;

    # KDE Plasma integration (media controls, downloads, tabs)
    nativeMessagingHosts = lib.optionals (features.desktop.wm == "kde") [
      pkgs.kdePackages.plasma-browser-integration
    ];

    #---------------------------
    # Default Profile
    #---------------------------
    profiles.default = {
      isDefault = true;

      # Extensions
      extensions.force = true;  # Prevent Firefox from disabling extensions
      extensions.packages = with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}; [
        firefox-color # catppuccin.firefox
        ublock-origin
        bitwarden
        new-tab-override
      ] ++ lib.optionals (features.desktop.wm == "kde") [
        inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}.plasma-integration
      ];

      # Search configuration
      search = {
        default = "ddg";  # DuckDuckGo
        force = true;     # Prevent Firefox from changing search engine
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
        "intl.accept_languages" = "de-DE,de,en-US,en";
        "intl.locale.requested" = "de";

        "browser.toolbars.bookmarks.visibility" = "never";

        # Toolbar layout: back forward reload | spacer | urlbar | spacer | downloads bitwarden
        "browser.uiCustomization.state" = builtins.toJSON {
          placements = {
            nav-bar = [
              "back-button"
              "forward-button"
              "stop-reload-button"
              "customizableui-special-spring1"
              "urlbar-container"
              "customizableui-special-spring2"
              "downloads-button"
              "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action" # Bitwarden
            ];
            toolbar-menubar = [ "menubar-items" ];
            TabsToolbar = [ "tabbrowser-tabs" ];
            PersonalToolbar = [ "personal-bookmarks" ];
            widget-overflow-fixed-list = [];
            unified-extensions-area = [];
          };
          seen = [ "developer-button" "profiler-button" ];
          dirtyAreaCache = [ "nav-bar" ];
          currentVersion = 21;
          newElementCount = 2;
        };

        "layout.css.prefers-color-scheme.content-override" = 0; # 0 = System
        "ui.systemUsesDarkTheme" = 1; # Force dark theme for UI

        "browser.startup.homepage" = "https://dash.at.oechsler.it";
        "browser.startup.page" = 3; # 3 = Restore previous session

        # Vertical tabs — collapsed, no extra tools
        "sidebar.verticalTabs" = true;
        "sidebar.revamp" = true;
        "sidebar.visibility" = "always-show";
        "sidebar.main.tools" = "";

        # DRM content (Netflix, Spotify, etc.)
        "media.eme.enabled" = true;
        "media.gmp-widevinecdm.enabled" = true;

        "browser.contentblocking.category" = "strict";
        "privacy.trackingprotection.enabled" = true;
        "privacy.trackingprotection.socialtracking.enabled" = true;
        "privacy.annotate_channels.strict_list.enabled" = true;
        "privacy.fingerprintingProtection" = true;
        "privacy.antitracking.enableWebcompat" = false;
        "privacy.globalprivacycontrol.enabled" = true;

        "browser.urlbar.suggest.searches" = false;
        "browser.urlbar.suggest.quicksuggest.sponsored" = false;
        "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
        "browser.urlbar.sponsoredTopSites" = false;
        "browser.urlbar.quicksuggest.enabled" = false;
        "browser.urlbar.quicksuggest.dataCollection.enabled" = false;
        "browser.search.suggest.enabled" = false;

        "signon.rememberSignons" = false;
        "signon.autofillForms" = false;
        "extensions.formautofill.creditCards.enabled" = false;
        "extensions.formautofill.addresses.enabled" = false;

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

        "datareporting.healthreport.uploadEnabled" = false;
        "datareporting.policy.dataSubmissionEnabled" = false;
        "toolkit.telemetry.enabled" = false;
        "toolkit.telemetry.unified" = false;
        "toolkit.telemetry.archive.enabled" = false;
        "browser.ping-centre.telemetry" = false;
        "app.shield.optoutstudies.enabled" = false;

        "dom.security.https_only_mode" = true;
        "dom.security.https_only_mode_ever_enabled" = true;

        "browser.translations.automaticallyPopup" = false;
        "browser.translations.enable" = false;

        # Fonts — always use real font families for web content, regardless of uiStyle
        "font.default.x-western" = "sans-serif";
        "font.default.x-unicode" = "sans-serif";
        "font.name.sans-serif.x-western" = fonts.sansSerif;
        "font.name.sans-serif.x-unicode" = fonts.sansSerif;
        "font.name.serif.x-western" = fonts.serif;
        "font.name.serif.x-unicode" = fonts.serif;
        "font.name.monospace.x-western" = fonts.monospace;
        "font.name.monospace.x-unicode" = fonts.monospace;

        # DNS over HTTPS
        "network.trr.mode" = 5;  # 5 = Off

        # Enable userContent.css for font overrides
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      };

      # Override system-ui / inherited fonts so web content stays sans-serif
      # even when the desktop uiStyle is set to monospace.
      userContent = ''
        @-moz-document url-prefix("http://"), url-prefix("https://") {
          :root, body {
            font-family: "${fonts.sansSerif}", sans-serif !important;
          }
          code, pre, kbd, samp, tt {
            font-family: "${fonts.monospace}", monospace !important;
          }
        }
      '';
    };
  };

    catppuccin.firefox = {
      enable = true;
      force = true;
    };
  };
}
