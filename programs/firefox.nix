{ pkgs, ... }:

{
  programs.firefox = {
    enable = false;
    profiles."default" = {
      extensions = {
        force = true;
        packages = [
          pkgs.nur.repos.rycee.firefox-addons.firefox-color
          pkgs.nur.repos.rycee.firefox-addons.ublock-origin
          pkgs.nur.repos.rycee.firefox-addons.keepassxc-browser
        ];
      };
      search = {
        force = true;
        default = "ddg";
        engines = {
          "google".metaData.hidden = true;
          "bing".metaData.hidden = true;
          "perplexity".metaData.hidden = true;

          "Nix Packages" = {
            urls = [
              {
                template = "https://search.nixos.org/packages";
                params = [
                  {
                    name = "type";
                    value = "packages";
                  }
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            icon = "''${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "@np" ];
          };

          "NixOS Options" = {
            urls = [
              {
                template = "https://search.nixos.org/options";
                params = [
                  {
                    name = "type";
                    value = "packages";
                  }
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            icon = "''${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "@no" ];
          };

          "Home Manager Options" = {
            urls = [
              {
                template = "https://home-manager-options.extranix.com/";
                params = [
                  {
                    name = "query";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            definedAliases = [ "@hm" ];
          };

          "GitHub" = {
            urls = [
              {
                template = "https://github.com/search";
                params = [
                  {
                    name = "q";
                    value = "{searchTerms}";
                  }
                ];
              }
            ];
            definedAliases = [ "@gh" ];
          };
        };
      };
      settings = {
        # Homepage & Session
        "browser.startup.homepage" = "https://nixos.org";
        "browser.startup.page" = 3; # Restore previous session
        "browser.newtabpage.pinned" = [
          {
            title = "NixOS";
            url = "https://nixos.org";
          }
        ];

        # Privacy & Performance QoL
        "privacy.donottrackheader.enabled" = true;
        "privacy.trackingprotection.enabled" = true;
        "privacy.trackingprotection.socialtracking.enabled" = true;

        # Security warnings - skip intermediate pages
        "browser.xul.error_pages.expert_bad_cert" = true; # Show "Advanced" button by default on cert errors

        # Disable telemetry
        "browser.newtabpage.activity-stream.feeds.telemetry" = false;
        "browser.newtabpage.activity-stream.telemetry" = false;
        "browser.ping-centre.telemetry" = false;
        "datareporting.healthreport.uploadEnabled" = false;
        "datareporting.policy.dataSubmissionEnabled" = false;
        "toolkit.telemetry.archive.enabled" = false;
        "toolkit.telemetry.bhrPing.enabled" = false;
        "toolkit.telemetry.enabled" = false;
        "toolkit.telemetry.unified" = false;

        # UI improvements
        "browser.compactmode.show" = true;
        "browser.uidensity" = 1; # Compact mode
        "browser.tabs.closeWindowWithLastTab" = false;
        "browser.tabs.warnOnClose" = false;
        "browser.download.useDownloadDir" = false; # Always ask where to save files
        "browser.tabs.inTitlebar" = 0; # Show title bar

        # Performance
        "gfx.webrender.all" = true;
        "media.ffmpeg.vaapi.enabled" = true; # Hardware video acceleration
        "layers.acceleration.force-enabled" = true;

        # Smooth scrolling
        "general.smoothScroll" = true;
        "general.smoothScroll.msdPhysics.enabled" = true;

        # Search improvements
        "browser.urlbar.suggest.searches" = true;
        "browser.urlbar.shortcuts.bookmarks" = true;
        "browser.urlbar.shortcuts.history" = true;
        "browser.urlbar.shortcuts.tabs" = true;
        "findbar.highlightAll" = true; # Highlight all matches when searching

        # Disable translation prompts
        "browser.translations.automaticallyPopup" = false;
        "browser.translations.neverTranslateLanguages" = "ru";

        # Mouse improvements
        "general.autoScroll" = true; # Middle mouse button for autoscroll

        # Extension settings
        "extensions.unifiedExtensions.enabled" = true; # Use unified extensions menu
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true; # Enable userChrome.css
      };

    };
  };
}
