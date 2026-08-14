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
# - proton-pass - Password manager
# - new-tab-override - Custom new tab page
# - plasma-integration (KDE only) - Desktop integration
#
# Search:
# - Default: DuckDuckGo
# - Hidden: Google, Bing, Amazon, eBay, Wikipedia, LEO, Ecosia, Perplexity
#
# Toolbar layout:
#   Back | Forward | Reload | Spacer | URL bar | Spacer | Downloads | Proton Pass

{
  pkgs,
  inputs,
  features,
  fonts,
  lib,
  config,
  ...
}:

let
  firefoxAddons = inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system};
  stylusId = firefoxAddons.stylus.addonId;
  catppuccinUserstylesExport = pkgs.fetchurl {
    url = "https://github.com/catppuccin/userstyles/releases/download/all-userstyles-export/import.json";
    hash = "sha256-+eqOt92dkNcnFK7L1jMrsMyOocxZXdbz1UdAOjZGsvw=";
  };
  catppuccinUserstylesLibrary = pkgs.fetchurl {
    url = "https://userstyles.catppuccin.com/lib/lib.less";
    hash = "sha256-XK9Oqan7Kz81DNyE3+ryl5sPi/OpvV+EkgL7WuLoGfM=";
  };
  # Inlined from compile-catppuccin-userstyles.js — compiles all Catppuccin
  # userstyles with the Stylus worker for the configured flavor/accent.
  # Note: ''${ escapes Nix interpolation so the literal ${ reaches node.
  compileCatppuccinUserstyles = pkgs.writeText "compile-catppuccin-userstyles.js" ''
    const crypto = require("crypto");
    const fs = require("fs");
    const path = require("path");
    const vm = require("vm");

    const [stylusDir, exportPath, libraryPath, flavor, accent] = process.argv.slice(2);
    const imported = JSON.parse(fs.readFileSync(exportPath, "utf8"));
    const library = fs.readFileSync(libraryPath, "utf8");
    const context = vm.createContext({
      console,
      setTimeout,
      clearTimeout,
      performance,
      location: { pathname: "/js/worker.js" },
      navigator: { locks: null },
      close() {},
    });
    context.self = context;
    context.globalThis = context;
    context.importScripts = file => {
      const source = fs.readFileSync(path.join(stylusDir, file), "utf8");
      vm.runInContext(source, context, { filename: file });
    };
    vm.runInContext(fs.readFileSync(path.join(stylusDir, "worker.js"), "utf8"), context, {
      filename: "worker.js",
    });

    function compile(source, preprocessor, vars, id) {
      return new Promise((resolve, reject) => {
        const port = {
          postMessage(message) {
            if (message.err) reject(message.err);
            else resolve(message.res[0]);
          },
        };
        context.onmessage({
          data: { id, args: ["compileUsercss", source, preprocessor, vars, id, true] },
          ports: [port],
        });
      });
    }

    function uuid(namespace) {
      const bytes = crypto.createHash("sha256").update(namespace).digest().subarray(0, 16);
      bytes[6] = (bytes[6] & 0x0f) | 0x50;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      const value = bytes.toString("hex");
      return `''${value.slice(0, 8)}-''${value.slice(8, 12)}-''${value.slice(12, 16)}-''${value.slice(16, 20)}-''${value.slice(20)}`;
    }

    (async () => {
      const storage = {
        dbInChromeStorage: true,
        settings: imported[0].settings,
      };

      for (const [offset, original] of imported.slice(1).entries()) {
        const id = offset + 1;
        const style = JSON.parse(JSON.stringify(original));
        const vars = style.usercssData.vars || {};
        if (vars.lightFlavor) vars.lightFlavor.value = "latte";
        if (vars.darkFlavor) vars.darkFlavor.value = flavor;
        if (vars.accentColor) vars.accentColor.value = accent;
        const source = style.sourceCode.replace(
          '@import "https://userstyles.catppuccin.com/lib/lib.less";',
          library,
        ).replace(
          'domain("cinny.in")',
          'domain("cinny.in"), domain("matrix.at.oechsler.it")',
        );
        style.sections = await compile(source, style.usercssData.preprocessor, vars, id);
        if (!style.sections.length) throw new Error(`''${style.name} compiled without sections`);
        style.id = id;
        style._id = uuid(style.usercssData.namespace || style.name);
        style._rev = 1;
        storage[`style-''${id}`] = style;
      }

      process.stdout.write(JSON.stringify(storage));
      process.exit(0);
    })().catch(error => {
      console.error(error);
      process.exit(1);
    });
  '';
  catppuccinUserstylesStorage =
    pkgs.runCommand "catppuccin-userstyles-storage.json"
      {
        nativeBuildInputs = [
          pkgs.nodejs
          pkgs.unzip
        ];
      }
      ''
        mkdir stylus
        unzip -q ${firefoxAddons.stylus}/share/mozilla/extensions/'{ec8030f7-c20a-464f-9b0e-13a3a9e97384}'/${stylusId}.xpi -d stylus
        node ${compileCatppuccinUserstyles} \
          stylus/js \
          ${catppuccinUserstylesExport} \
          ${catppuccinUserstylesLibrary} \
          ${config.catppuccin.flavor} \
          ${config.catppuccin.accent} > "$out"
      '';
in
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
      configPath = "${config.xdg.configHome}/mozilla/firefox";

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
        extensions.force = true; # Prevent Firefox from disabling extensions
        extensions.packages =
          with inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system};
          [
            firefox-color # catppuccin.firefox
            ublock-origin
            proton-pass
            new-tab-override
            stylus
            catppuccin-web-file-icons
          ]
          ++ lib.optionals (features.desktop.wm == "kde") [
            inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}.plasma-integration
          ];

        # Search configuration
        search = {
          default = "ddg"; # DuckDuckGo
          force = true; # Prevent Firefox from changing search engine
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

          # Toolbar layout: back forward reload | spacer | urlbar | spacer | downloads proton-pass
          # To customize toolbar: Right-click toolbar → Customize Toolbar
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
                "78272b6fa58f4a1abaac99321d503a20_proton_me-browser-action"
                "unified-extensions-button"
              ];
              toolbar-menubar = [ "menubar-items" ];
              TabsToolbar = [ "tabbrowser-tabs" ];
              PersonalToolbar = [ "personal-bookmarks" ];
              widget-overflow-fixed-list = [ ];
              unified-extensions-area = [
                "ublock0_raymondhill_net-browser-action"
                "newtaboverride_agenedia_com-browser-action"
              ];
            };
            seen = [
              "developer-button"
              "profiler-button"
              "78272b6fa58f4a1abaac99321d503a20_proton_me-browser-action"
              "ublock0_raymondhill_net-browser-action"
              "newtaboverride_agenedia_com-browser-action"
            ];
            dirtyAreaCache = [
              "nav-bar"
              "unified-extensions-area"
            ];
            currentVersion = 21;
            newElementCount = 2;
          };

          "layout.css.prefers-color-scheme.content-override" = 0; # 0 = System
          "ui.systemUsesDarkTheme" = 1; # Force dark theme for UI

          # Home Manager installs extensions into the profile. Keep them enabled
          # without a first-run approval prompt. Firefox Color / Catppuccin
          # settings are written via storage.js, which requires
          # extensions.webextensions.ExtensionStorageIDB.enabled = false.
          # Home Manager sets this automatically when extension settings exist.
          "extensions.autoDisableScopes" = 0;

          "browser.startup.homepage" = "https://dash.at.oechsler.it";
          "browser.startup.page" = 3; # 3 = Restore previous session

          # Vertical tabs — collapsed, no extra tools
          "sidebar.verticalTabs" = true;
          "sidebar.revamp" = true;
          "sidebar.visibility" = "always-show";
          "sidebar.main.tools" = "";
          "sidebar.installed.extensions" = stylusId;

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
          "network.http.referer.XOriginTrimmingPolicy" = 2;

          "network.prefetch-next" = false;
          "network.dns.disablePrefetch" = true;
          "network.dns.disablePrefetchFromHTTPS" = true;
          "network.http.speculative-parallel-limit" = 0;

          "browser.urlbar.suggest.searches" = false;
          "browser.urlbar.speculativeConnect.enabled" = false;
          "browser.places.speculativeConnect.enabled" = false;
          "browser.urlbar.suggest.quicksuggest.sponsored" = false;
          "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
          "browser.urlbar.sponsoredTopSites" = false;
          "browser.urlbar.quicksuggest.enabled" = false;
          "browser.urlbar.quicksuggest.dataCollection.enabled" = false;
          "browser.search.suggest.enabled" = false;

          "signon.rememberSignons" = false;
          "signon.autofillForms" = false;
          "signon.firefoxRelay.feature" = "disabled";
          "browser.formfill.enable" = false;
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
          "app.shield.optoutstudies.enabled" = false;
          "app.normandy.enabled" = false;
          "app.normandy.api_url" = "";
          "breakpad.reportURL" = "";
          "browser.discovery.enabled" = false;
          "extensions.htmlaboutaddons.recommendations.enabled" = false;

          "network.captive-portal-service.enabled" = false;
          "network.connectivity-service.enabled" = false;

          "dom.security.https_only_mode" = true;
          "dom.security.https_only_mode_ever_enabled" = true;
          "security.ssl.require_safe_negotiation" = true;
          "security.tls.enable_0rtt_data" = false;
          "security.cert_pinning.enforcement_level" = 2;

          "browser.uitour.enabled" = false;
          "permissions.manager.defaultsUrl" = "";
          "network.IDN_show_punycode" = true;
          "dom.disable_window_move_resize" = true;

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
          "network.trr.mode" = 5; # 5 = Off

          # Enable userContent.css for font overrides
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

          "extensions.webextensions.ExtensionStorageIDB.enabled" = false;
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

    # Stylus extension data — pre-compiled Catppuccin userstyles
    xdg.configFile."mozilla/firefox/default/browser-extension-data/${stylusId}/storage.js" = {
      source = catppuccinUserstylesStorage;
      force = true;
    };
  };
}
