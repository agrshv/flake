{ config, ... }:
let
  # Installed and kept up to date from addons.mozilla.org by policy, so they
  # are present on a fresh profile without NUR; not pinned by the lockfile.
  addon = id: slug: {
    name = id;
    value = {
      installation_mode = "force_installed";
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
      private_browsing = true;
    };
  };
in
{
  # Trial alongside Brave (programs/chromium.nix stays the default browser in
  # programs/xdg.nix until this one wins).
  programs.firefox = {
    enable = true;
    # New default since home-manager 26.05; set so it doesn't warn. A fresh
    # profile, so there is no ~/.mozilla/firefox to migrate.
    configPath = "${config.xdg.configHome}/mozilla/firefox";
    # No nativeMessagingHosts: the Pywalfox host is noctalia itself, and the
    # pywalfox template's firefox-theme post action (programs/noctalia.nix)
    # rewrites ~/.mozilla/native-messaging-hosts/pywalfox.json on every theme
    # apply before pushing the palette. A home-manager link there is
    # read-only, which made that write, and so the live push, fail. Since it
    # is rewritten each time, the store path in it never goes stale.

    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DisablePocket = true;
      DontCheckDefaultBrowser = true;
      # No about:welcome onboarding on a fresh profile, no "what's new" tab
      # after updates, and none of Mozilla's recommendation pop-ups.
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      UserMessaging = {
        SkipOnboarding = true;
        ExtensionRecommendations = false;
        FeatureRecommendations = false;
        MoreFromMozilla = false;
        UrlbarInterventions = false;
        FirefoxLabs = false;
        Locked = true;
      };
      # Bitwarden fills logins; don't offer to save them twice.
      PasswordManagerEnabled = false;
      OfferToSaveLogins = false;
      ExtensionSettings = builtins.listToAttrs [
        (addon "uBlock0@raymondhill.net" "ublock-origin")
        (addon "{446900e4-71c2-419f-a6a7-df9c091e268b}" "bitwarden-password-manager")
        (addon "pywalfox@frewacom.org" "pywalfox")
        (addon "sponsorBlocker@ajay.app" "sponsorblock")
        # German UI language pack, from Mozilla's release server for exactly
        # this Firefox version: a language pack only loads on the version it
        # was built for, and AMO's "latest" can run ahead of nixpkgs.
        {
          name = "langpack-de@firefox.mozilla.org";
          value = {
            installation_mode = "force_installed";
            install_url = "https://releases.mozilla.org/pub/firefox/releases/${config.programs.firefox.package.version}/linux-x86_64/xpi/de.xpi";
          };
        }
      ];

      # uBlock Origin's filter lists, applied on every start (lists toggled
      # in its dashboard are reset). toOverwrite replaces the selection, so
      # the defaults are restated. IDs are the keys of uBlock's assets.json.
      "3rdparty".Extensions."uBlock0@raymondhill.net".toOverwrite.filterLists = [
        # Defaults. EasyList covers English sites.
        "user-filters"
        "ublock-filters"
        "ublock-badware"
        "ublock-privacy"
        "ublock-unbreak"
        "ublock-quick-fixes"
        "easylist"
        "easyprivacy"
        "urlhaus-1"
        "plowe-0"
        # Cookie notices.
        "ublock-cookies-easylist"
        "ublock-cookies-adguard"
        "fanboy-cookiemonster"
        "adguard-cookies"
        # Annoyances: pop-up overlays, "open in app" banners, chat and
        # newsletter widgets, notification prompts.
        "ublock-annoyances"
        "easylist-annoyances"
        "easylist-chat"
        "easylist-newsletters"
        "easylist-notifications"
        "adguard-popup-overlays"
        "adguard-mobile-app-banners"
        "adguard-other-annoyances"
        "adguard-widgets"
        # Social widgets.
        "fanboy-social"
        "adguard-social"
        # Regional: RU AdList (ru/kz sites) and EasyList Germany.
        "RUS-0"
        "DEU-0"
      ];
    };

    profiles.default = {
      isDefault = true;
      # home-manager owns search.json.mozlz4 (force), so engines changed in
      # Settings → Search are reset on the next switch.
      search = {
        force = true;
        default = "ddg";
        privateDefault = "ddg";
        engines = {
          google.metaData.hidden = true;
          bing.metaData.hidden = true;
          perplexity.metaData.hidden = true;
        };
      };
      settings = {
        # VA-API video decode, like the AcceleratedVideoDecodeLinuxGL flag
        # Brave gets from nixpkgs.
        "media.ffmpeg.vaapi.enabled" = true;
        # Follow the system language (i18n.defaultLocale; de_DE on
        # work-laptop) instead of the en-US the build ships with: an empty
        # list means "use the OS locales", falling back to English where no
        # language pack is installed. Dates and numbers follow it as well.
        "intl.locale.requested" = "";
        "intl.regional_prefs.use_os_locales" = true;
        # Skip the language prompt and the privacy-notice tab on first start.
        "intl.multilingual.aboutWelcome.languageMismatchEnabled" = false;
        "datareporting.policy.dataSubmissionPolicyBypassNotification" = true;
        "toolkit.telemetry.reportingpolicy.firstRun" = false;
        # Restore the previous session and keep the new tab page plain.
        "browser.startup.page" = 3;
        "browser.newtabpage.activity-stream.showSponsored" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
        "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
        "browser.urlbar.suggest.quicksuggest.sponsored" = false;
        # Follow the GTK theme (noctalia's gtk3 template) for light/dark.
        "layout.css.prefers-color-scheme.content-override" = 2;

        # Stricter privacy: strict tracking protection (may break the odd
        # site; the shield in the address bar turns it off per site),
        # built-in cookie-banner rejection where uBlock misses one, and the
        # Global Privacy Control signal.
        "browser.contentblocking.category" = "strict";
        "cookiebanners.service.mode" = 1;
        "cookiebanners.service.mode.privateBrowsing" = 1;
        "privacy.globalprivacycontrol.enabled" = true;
        # HTTPS-only: plain-HTTP sites show a "Continue to HTTP site" page.
        "dom.security.https_only_mode" = true;

        # Certificate errors (expired, self-signed) open with the technical
        # details already expanded, so "Accept the risk and continue" is one
        # click. Firefox never skips the page by itself, and HSTS sites can't
        # be overridden at all.
        "browser.xul.error_pages.expert_bad_cert" = true;

        # Closing the last tab leaves an empty window instead of closing it.
        "browser.tabs.closeWindowWithLastTab" = false;
      };
    };
  };
}
