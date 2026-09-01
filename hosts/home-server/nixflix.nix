{
  config,
  lib,
  pkgs,
  ...
}:
let
  # qBittorrent keeps its WebUI password as a PBKDF2 hash in serverConfig, which
  # nixpkgs renders into a world-readable /nix/store file. Keep the hash in sops
  # instead: serverConfig carries a placeholder and an ExecStartPre swaps in the
  # real value. `mkAfter` is what puts that step *after* the module's own
  # install of the config file — a plain preStart runs before it and would be
  # overwritten (nixpkgs qbittorrent.nix:176).
  qbtPasswordPlaceholder = "QBITTORRENT_PASSWORD_PBKDF2_PLACEHOLDER";
  qbtSetPassword = pkgs.writeShellScript "qbittorrent-set-password" ''
    ${lib.getExe pkgs.replace-secret} '${qbtPasswordPlaceholder}' \
      ${config.sops.secrets."nixflix/qbittorrent/password_hash".path} \
      /var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf
  '';
  # The *arr services read their own API key at start-up as their own user, and
  # recyclarr reads all three of sonarr/sonarr-anime/radarr. Everything else
  # here is read by a root oneshot, so it keeps the sops default of 0400 root.
  arrReaders = {
    group = "nixflix-secrets";
    mode = "0440";
  };
in
{
  users.groups.nixflix-secrets = { };
  users.users = builtins.listToAttrs (
    map
      (u: {
        name = u;
        value.extraGroups = [ "nixflix-secrets" ];
      })
      [
        "prowlarr"
        "sonarr"
        "sonarr-anime"
        "radarr"
        "recyclarr"
      ]
  );

  # Runs with `+` (full privileges) so the hash can stay 0400 root, and after the
  # upstream install step that would otherwise clobber the substitution.
  systemd.services.qbittorrent.serviceConfig.ExecStartPre = lib.mkAfter [ "+${qbtSetPassword}" ];

  sops.secrets = {
    "nixflix/qbittorrent/webui_password" = { };
    "nixflix/qbittorrent/password_hash".restartUnits = [ "qbittorrent.service" ];

    "nixflix/jellyfin/api_key" = { };
    "nixflix/jellyfin/admin_password" = { };
    "nixflix/jellyfin/opensubtitles_password" = { };
    "nixflix/jellyfin/opensubtitles_api_key" = { };
    "nixflix/seerr/api_key" = { };
    "nixflix/prowlarr/api_key" = arrReaders;
    "nixflix/prowlarr/admin_password" = { };
    "nixflix/prowlarr/milkie_api_key" = { };
    "nixflix/prowlarr/rutracker_password" = { };
    "nixflix/sonarr/api_key" = arrReaders;
    "nixflix/sonarr/admin_password" = { };
    "nixflix/sonarr-anime/api_key" = arrReaders;
    "nixflix/sonarr-anime/admin_password" = { };
    "nixflix/radarr/api_key" = arrReaders;
    "nixflix/radarr/admin_password" = { };
  };

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
      password._secret = config.sops.secrets."nixflix/qbittorrent/webui_password".path;
      serverConfig.Preferences.WebUI = {
        Username = "d3spair";
        # Substituted at start-up from sops by qbtSetPassword above; the store
        # only ever sees this placeholder.
        Password_PBKDF2 = "@ByteArray(${qbtPasswordPlaceholder})";
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
      apiKey._secret = config.sops.secrets."nixflix/jellyfin/api_key".path;
      users.d3spair = {
        mutable = false;
        policy.isAdministrator = true;
        password._secret = config.sops.secrets."nixflix/jellyfin/admin_password".path;
      };

      # Subtitle plugins. Requires an opensubtitles.com account: put the
      # account password and REST API key in the referenced secret files.
      plugins = {
        subbuzz = {
          enable = true;
          config = {
            OpenSubUserName = "prescribe2222"; # must match your opensubtitles.com login
            OpenSubPassword._secret = config.sops.secrets."nixflix/jellyfin/opensubtitles_password".path;
            OpenSubApiKey._secret = config.sops.secrets."nixflix/jellyfin/opensubtitles_api_key".path;
            EnableOpenSubtitles = true;
            EnableYifySubtitles = true;
            Cache.SubLifeInMinutes = "Always"; # Default is "1 week"
          };
        };

        "Open Subtitles" = {
          enable = true;
          config = {
            Username = "prescribe2222";
            Password._secret = config.sops.secrets."nixflix/jellyfin/opensubtitles_password".path;
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
      apiKey._secret = config.sops.secrets."nixflix/seerr/api_key".path;
      externalUrlScheme = "https";
      jellyfin = {
        adminUsername = "d3spair";
        adminPassword._secret = config.sops.secrets."nixflix/jellyfin/admin_password".path;
      };
    };

    prowlarr = {
      enable = true;
      config = {
        apiKey._secret = config.sops.secrets."nixflix/prowlarr/api_key".path;
        hostConfig = {
          username = "d3spair";
          password._secret = config.sops.secrets."nixflix/prowlarr/admin_password".path;
        };
        indexers = [
          {
            name = "Milkie";
            baseUrl = "https://milkie.cc/";
            apikey._secret = config.sops.secrets."nixflix/prowlarr/milkie_api_key".path;
          }
          {
            name = "RuTracker.org";
            enable = false;
            baseUrl = "https://rutracker.org/";
            username = "MadAndSlowly";
            password._secret = config.sops.secrets."nixflix/prowlarr/rutracker_password".path;
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
        apiKey._secret = config.sops.secrets."nixflix/sonarr/api_key".path;
        hostConfig = {
          username = "d3spair";
          password._secret = config.sops.secrets."nixflix/sonarr/admin_password".path;
        };
      };
    };

    sonarr-anime = {
      enable = true;
      config = {
        apiKey._secret = config.sops.secrets."nixflix/sonarr-anime/api_key".path;
        hostConfig = {
          username = "d3spair";
          password._secret = config.sops.secrets."nixflix/sonarr-anime/admin_password".path;
        };
      };
    };

    radarr = {
      enable = true;
      config = {
        apiKey._secret = config.sops.secrets."nixflix/radarr/api_key".path;
        hostConfig = {
          username = "d3spair";
          password._secret = config.sops.secrets."nixflix/radarr/admin_password".path;
        };
      };
    };
  };
}
