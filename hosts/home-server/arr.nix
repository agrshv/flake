{ config, lib, ... }:
let
  # Arr API keys are pinned from sops through each service's environment file,
  # so recyclarr (and anything else wired up by hand) keeps working across
  # reinstalls. The files are read by systemd as root, so the secrets keep the
  # sops default of 0400 root.
  apiKeyEnv = name: secret: ''
    ${name}__AUTH__APIKEY=${config.sops.placeholder."nixflix/${secret}/api_key"}
  '';

  # Sonarr, Radarr and Prowlarr keep their databases in the shared Postgres
  # (pg_dumpall'd nightly, see ./restic.nix) over the local socket with peer
  # auth. The separate log database is off: logs go to files only.
  postgres = db: {
    postgres = {
      host = "/run/postgresql";
      port = 5432;
      user = db;
      maindb = db;
    };
    log.dbEnabled = false;
  };

  vhost = port: {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
    };
  };
in
{
  # TRaSH layout: torrents and the library on one filesystem under /data, so
  # Sonarr/Radarr import with hardlinks instead of copies. Everything that
  # writes there runs with `media` as its primary group (PrivateUsers on the
  # arr units maps only the primary group) and UMask 0002 (forced: upstream
  # sets 0022); setgid on the directories keeps new files in `media`.
  users.groups.media = { };

  systemd.tmpfiles.settings."10-media" =
    let
      shared = {
        d = {
          mode = "2775";
          user = "root";
          group = "media";
        };
      };
    in
    {
      "/data".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      "/data/torrents" = shared;
      "/data/media" = shared;
      # Sonarr root folders: series, and anime (series type "Anime").
      "/data/media/tv" = shared;
      "/data/media/anime" = shared;
      "/data/media/movies" = shared;
    };

  sops.secrets = {
    "nixflix/sonarr/api_key" = { };
    "nixflix/radarr/api_key" = { };
    "nixflix/prowlarr/api_key" = { };
  };
  sops.templates = {
    "sonarr.env" = {
      content = apiKeyEnv "SONARR" "sonarr";
      restartUnits = [ "sonarr.service" ];
    };
    "radarr.env" = {
      content = apiKeyEnv "RADARR" "radarr";
      restartUnits = [ "radarr.service" ];
    };
    "prowlarr.env" = {
      content = apiKeyEnv "PROWLARR" "prowlarr";
      restartUnits = [ "prowlarr.service" ];
    };
  };

  services.postgresql = {
    ensureDatabases = [
      "sonarr"
      "radarr"
      "prowlarr"
    ];
    ensureUsers =
      map
        (name: {
          inherit name;
          ensureDBOwnership = true;
        })
        [
          "sonarr"
          "radarr"
          "prowlarr"
        ];
  };

  # Indexers, download client, root folders and the anime series type are
  # configured in the web UIs; their state lives in Postgres and the config.xml
  # in each data dir.
  services.sonarr = {
    enable = true;
    group = "media";
    dataDir = "/var/lib/sonarr";
    environmentFiles = [ config.sops.templates."sonarr.env".path ];
    settings = postgres "sonarr";
  };

  services.radarr = {
    enable = true;
    group = "media";
    dataDir = "/var/lib/radarr";
    environmentFiles = [ config.sops.templates."radarr.env".path ];
    settings = postgres "radarr";
  };

  # DynamicUser upstream; the dynamic user is still named `prowlarr`, which
  # is what peer auth matches on.
  services.prowlarr = {
    enable = true;
    environmentFiles = [ config.sops.templates."prowlarr.env".path ];
    settings = postgres "prowlarr";
  };

  # For Cloudflare-fronted indexers (1337x); Prowlarr reaches it as an indexer
  # proxy on 127.0.0.1:8191, applied by the `flaresolverr` tag.
  services.flaresolverr.enable = true;

  # Russian/English subtitles, written next to the media. SQLite state, so it
  # is stopped for the nightly backup (./restic.nix).
  services.bazarr = {
    enable = true;
    group = "media";
  };

  systemd.services =
    let
      afterPostgres = {
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
      };
    in
    {
      sonarr = afterPostgres // {
        serviceConfig = {
          UMask = lib.mkForce "0002";
          # Upstream only creates the data dir when it's left at the default
          # (/var/lib/sonarr/.config/NzbDrone); unlike radarr it has no tmpfiles
          # rule for a custom one.
          StateDirectory = "sonarr";
        };
      };
      radarr = afterPostgres // {
        serviceConfig.UMask = lib.mkForce "0002";
      };
      prowlarr = afterPostgres;
      bazarr.serviceConfig.UMask = lib.mkForce "0002";
    };

  # TRaSH quality profiles, custom formats and naming pushed into Sonarr and
  # Radarr daily. Anime shares the Sonarr instance, so it gets the anime
  # profile alongside the series one; only one quality definition fits per
  # instance, and the series one wins.
  services.recyclarr = {
    enable = true;
    configuration = {
      sonarr.sonarr = {
        base_url = "http://127.0.0.1:${toString config.services.sonarr.settings.server.port}";
        api_key._secret = config.sops.secrets."nixflix/sonarr/api_key".path;
        delete_old_custom_formats = true;
        quality_definition.type = "series";
        quality_profiles = [
          {
            # WEB-1080p
            trash_id = "9d142234e45d6143785ac55f5a9e8dc9";
            reset_unmatched_scores.enabled = true;
          }
          {
            # [Anime] Remux-1080p
            trash_id = "20e0fc959f1f1704bed501f23bdae76f";
            reset_unmatched_scores.enabled = true;
          }
        ];
        media_naming = {
          series = "jellyfin-tvdb";
          season = "default";
          episodes = {
            rename = true;
            standard = "default";
            daily = "default";
            anime = "default";
          };
        };
      };
      radarr.radarr = {
        base_url = "http://127.0.0.1:${toString config.services.radarr.settings.server.port}";
        api_key._secret = config.sops.secrets."nixflix/radarr/api_key".path;
        delete_old_custom_formats = true;
        # The standard size table, which HD Bluray + WEB is meant for. The SQP
        # one rejected most encodes of older films outright (1080p Bluray under
        # 3.1 GB), and there is only one table per instance.
        quality_definition.type = "movie";
        quality_profiles = [
          {
            # HD Bluray + WEB: TRaSH's general-purpose 1080p profile, minimum
            # score 0, so decent public-tracker releases get through while LQ
            # groups and junk are still scored out. The default in Radarr/Seerr.
            trash_id = "d1d67249d3890e49bc12e275d989a7e9";
            reset_unmatched_scores.enabled = true;
          }
          {
            # [SQP] SQP-1 (1080p). Kept for titles worth waiting on a premium
            # encode; on public trackers older films often have no release
            # that passes, and it grabbed a dead one for The Breadwinner.
            trash_id = "0896c29d74de619df168d23b98104b22";
            min_format_score = 180;
            reset_unmatched_scores.enabled = true;
          }
        ];
        media_naming = {
          folder = "jellyfin-tmdb";
          movie = {
            rename = true;
            standard = "standard";
          };
        };
      };
    };
  };

  # LAN/NetBird only: these are in internalHosts in ./nginx.nix.
  services.nginx.virtualHosts = {
    "sonarr.agrshv.dev" = vhost config.services.sonarr.settings.server.port;
    "radarr.agrshv.dev" = vhost config.services.radarr.settings.server.port;
    "prowlarr.agrshv.dev" = vhost config.services.prowlarr.settings.server.port;
    "bazarr.agrshv.dev" = vhost config.services.bazarr.listenPort;
  };
}
