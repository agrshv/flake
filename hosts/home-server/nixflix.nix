{ pkgs, ... }: {
  nixflix = {
    enable = true;
    theme = {
      enable = true;
      name = "catppuccin-mocha";
    };
    nginx = {
      enable = true;
      domain = "agrshv.dev";
      forceSSL = true;
      enableACME = true;
    };
    postgres.enable = true;
    torrentClients.qbittorrent = {
      enable = true;
      password._secret = "/root/nixflix/qbittorrent/webui_password";
      serverConfig.Preferences.WebUI = {
        Username = "d3spair";
        AlternativeUIEnabled = true;
        RootFolder = "${pkgs.vuetorrent}/share/vuetorrent";
      };
    };
    recyclarr = {
      enable = true;
      cleanupUnmanagedProfiles.enable = true;
    };
    flaresolverr.enable = true;
    jellyfin = {
      enable = true;
      apiKey._secret = "/root/nixflix/jellyfin/api_key";
      users.d3spair = {
        mutable = false;
        policy.isAdministrator = true;
        password._secret = "/root/nixflix/jellyfin/d3spair_password";
      };

      # Subtitle plugins. Requires an opensubtitles.com account: put the
      # account password and REST API key in the referenced secret files.
      plugins = {
        subbuzz = {
          enable = true;
          config = {
            OpenSubUserName = "prescribe2222"; # must match your opensubtitles.com login
            OpenSubPassword._secret = "/root/nixflix/jellyfin/opensubtitles_password";
            OpenSubApiKey._secret = "/root/nixflix/jellyfin/opensubtitles_api_key";
            EnableOpenSubtitles = true;
            EnableYifySubtitles = true;
            Cache.SubLifeInMinutes = "Always"; # Default is "1 week"
          };
        };

        "Open Subtitles" = {
          enable = true;
          config = {
            Username = "prescribe2222";
            Password._secret = "/root/nixflix/jellyfin/opensubtitles_password";
          };
        };

        "Subtitle Extract" = {
          enable = true;
          config.ExtractionDuringLibraryScan = true;
        };
      };

      # Per-library subtitle behaviour. Keys must match your actual Jellyfin
      # library display names.
      libraries =
        let
          subtitleSettings = {
            subtitleFetcherOrder = [
              "Open Subtitles"
              "subbuzz"
            ];
            subtitleDownloadLanguages = [
              "eng"
              "rus"
            ];
            saveSubtitlesWithMedia = true;
            allowEmbeddedSubtitles = "AllowAll";
            requirePerfectSubtitleMatch = true;
            skipSubtitlesIfAudioTrackMatches = false;
            skipSubtitlesIfEmbeddedSubtitlesPresent = true;
          };
        in
        {
          Shows = subtitleSettings;
          # Anime rarely has a "perfect" release match on OpenSubtitles, and
          # often ships embedded soft-subs; relax both so fetching actually runs.
          Anime = subtitleSettings // {
            requirePerfectSubtitleMatch = false;
            skipSubtitlesIfEmbeddedSubtitlesPresent = false;
          };
          Movies = subtitleSettings;
        };
      # Hardware transcoding on the Ryzen 5 4600G (Vega 7, VCN 2.1) via VAAPI.
      encoding = {
        enableHardwareEncoding = true;
        hardwareAccelerationType = "vaapi"; # AMF is Windows-only; do not use it
        vaapiDevice = "/dev/dri/renderD128";
        # Codecs the VCN 2.1 engine can decode. No AV1 — Renoir has no AV1 decoder.
        hardwareDecodingCodecs = [
          "h264"
          "hevc"
          "mpeg2video"
          "vc1"
          "vp9"
        ];
        # VCN 2.1 can encode H.264 and HEVC. No AV1 encode on this hardware.
        allowHevcEncoding = true;
        allowAv1Encoding = false;
        enableDecodingColorDepth10Hevc = true;
        enableDecodingColorDepth10Vp9 = true;
      };
    };
    # Media discovery & request frontend. sonarr/radarr/jellyfin instances are
    # auto-configured from the nixflix config above. Exposed at seerr.agrshv.dev.
    seerr = {
      enable = true;
      apiKey._secret = "/root/nixflix/seerr/api_key";
      externalUrlScheme = "https";
      jellyfin = {
        adminUsername = "d3spair";
        adminPassword._secret = "/root/nixflix/jellyfin/d3spair_password";
      };
    };

    prowlarr = {
      enable = true;
      config = {
        apiKey._secret = "/root/nixflix/prowlarr/api_key";
        hostConfig = {
          username = "d3spair";
          password._secret = "/root/nixflix/prowlarr/d3spair_password";
        };
        indexers = [
          {
            name = "Milkie";
            baseUrl = "https://milkie.cc/";
            apikey._secret = "/root/nixflix/prowlarr/milkie_api_key";
          }
          {
            name = "RuTracker.org";
            enable = false;
            baseUrl = "https://rutracker.org/";
            username = "MadAndSlowly";
            password._secret = "/root/nixflix/prowlarr/rutracker_password";
          }
          {
            name = "Nyaa.si";
            baseUrl = "https://nyaa.si/";
          }
          {
            name = "1337x";
            baseUrl = "https://1337x.st/";
            tags = [ "flaresolverr" ];
          }
        ];
      };
    };

    sonarr = {
      enable = true;
      config = {
        apiKey._secret = "/root/nixflix/sonarr/api_key";
        hostConfig = {
          username = "d3spair";
          password._secret = "/root/nixflix/sonarr/d3spair_password";
        };
      };
    };

    sonarr-anime = {
      enable = true;
      config = {
        apiKey._secret = "/root/nixflix/sonarr-anime/api_key";
        hostConfig = {
          username = "d3spair";
          password._secret = "/root/nixflix/sonarr-anime/d3spair_password";
        };
      };
    };

    radarr = {
      enable = true;
      config = {
        apiKey._secret = "/root/nixflix/radarr/api_key";
        hostConfig = {
          username = "d3spair";
          password._secret = "/root/nixflix/radarr/d3spair_password";
        };
      };
    };
  };
}
