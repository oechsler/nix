{ config, pkgs, inputs, features, lib, ... }:

lib.mkIf features.desktop.enable {
  programs.firefox = {
    enable = true;
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

        # Dark Mode
        "layout.css.prefers-color-scheme.content-override" = 0; # 0 = System
        "ui.systemUsesDarkTheme" = 1; # Force dark theme for UI

        # Startup - restore previous session
        "browser.startup.homepage" = "https://dash.at.oechsler.it";
        "browser.startup.page" = 3; # 3 = Restore previous session

        # Vertical tabs
        "sidebar.verticalTabs" = true;
        "sidebar.revamp" = true;
        "sidebar.main.tools.shown" = true;

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
