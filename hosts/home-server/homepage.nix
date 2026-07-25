{
  # Homepage — a single landing page linking every service on the box. Bound to
  # 127.0.0.1:8082 and fronted by nginx at home.agrshv.dev (behind the KZ GeoIP
  # gate — see the guardedHosts list in ./nginx.nix).
  #
  # This first pass is links + system resource widgets only. The upstream module
  # runs the service under `DynamicUser = true`, so it CANNOT read the existing
  # /root/nixflix/**/api_key secret files — live *arr/Jellyfin widgets need their
  # own reachable secret. See the commented block at the bottom for how to wire
  # those in via sops once you want them.
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;

    # Requests arrive proxied, so the Host header is the public name. Homepage
    # rejects anything not listed here.
    allowedHosts = "agrshv.dev,localhost:8082,127.0.0.1:8082";

    settings = {
      title = "agrshv.dev";
      headerStyle = "clean";
      # No native Catppuccin, but violet-on-dark is the closest built-in match to
      # the mocha/mauve theme used everywhere else. Refine with customCSS later.
      theme = "dark";
      color = "violet";
      # Group order + rendering. Keys must match the group names below.
      layout = {
        "Media" = {
          style = "row";
          columns = 4;
        };
        "Downloads" = {
          style = "row";
          columns = 3;
        };
        "Photos & Personal" = {
          style = "row";
          columns = 4;
        };
        "Read & Docs" = {
          style = "row";
          columns = 3;
        };
        "Infrastructure" = {
          style = "row";
          columns = 3;
        };
      };
    };

    # Top-of-page info widgets.
    widgets = [
      {
        resources = {
          label = "home-server";
          cpu = true;
          memory = true;
          cputemp = true;
          uptime = true;
          disk = "/";
        };
      }
      {
        # Search box wired to the self-hosted SearXNG instance.
        search = {
          provider = "custom";
          url = "https://search.agrshv.dev/search?q=";
          target = "_blank";
        };
      }
      {
        openmeteo = {
          label = "Almaty";
          latitude = "43.2380";
          longitude = "76.8829";
          timezone = "Asia/Almaty";
          units = "metric";
          cache = 5;
        };
      }
      {
        datetime = {
          text_size = "xl";
          format = {
            timeStyle = "short";
            dateStyle = "long";
            hourCycle = "h23";
          };
        };
      }
    ];

    services = [
      {
        "Media" = [
          { "Jellyfin" = { href = "https://jellyfin.agrshv.dev"; description = "Movies, shows & anime"; icon = "jellyfin.png"; }; }
          { "Jellyseerr" = { href = "https://seerr.agrshv.dev"; description = "Request & discover"; icon = "jellyseerr.png"; }; }
          { "Navidrome" = { href = "https://music.agrshv.dev"; description = "Music streaming"; icon = "navidrome.png"; }; }
          { "slskd" = { href = "https://slskd.agrshv.dev"; description = "Soulseek"; icon = "slskd.png"; }; }
        ];
      }
      {
        "Downloads" = [
          { "Sonarr" = { href = "https://sonarr.agrshv.dev"; description = "TV"; icon = "sonarr.png"; }; }
          { "Sonarr (Anime)" = { href = "https://sonarr-anime.agrshv.dev"; description = "Anime"; icon = "sonarr.png"; }; }
          { "Radarr" = { href = "https://radarr.agrshv.dev"; description = "Movies"; icon = "radarr.png"; }; }
          { "Prowlarr" = { href = "https://prowlarr.agrshv.dev"; description = "Indexers"; icon = "prowlarr.png"; }; }
          { "qBittorrent" = { href = "https://qbittorrent.agrshv.dev"; description = "Torrent client"; icon = "qbittorrent.png"; }; }
          { "wrtag" = { href = "https://wrtag.agrshv.dev"; description = "Music tagging"; icon = "mdi-music-note-plus"; }; }
        ];
      }
      {
        "Photos & Personal" = [
          { "Immich" = { href = "https://immich.agrshv.dev"; description = "Photos"; icon = "immich.png"; }; }
          { "Dawarich" = { href = "https://dawarich.agrshv.dev"; description = "Location history"; icon = "dawarich.png"; }; }
          { "Monica" = { href = "https://monica.agrshv.dev"; description = "Personal CRM"; icon = "monica.png"; }; }
          { "Actual" = { href = "https://budget.agrshv.dev"; description = "Budget"; icon = "actual-budget.png"; }; }
        ];
      }
      {
        "Read & Docs" = [
          { "Miniflux" = { href = "https://news.agrshv.dev"; description = "RSS reader"; icon = "miniflux.png"; }; }
          { "Readeck" = { href = "https://read.agrshv.dev"; description = "Read later"; icon = "readeck.png"; }; }
          { "Paperless" = { href = "https://docs.agrshv.dev"; description = "Documents"; icon = "paperless-ngx.png"; }; }
        ];
      }
      {
        "Infrastructure" = [
          { "Forgejo" = { href = "https://git.agrshv.dev"; description = "Git forge"; icon = "forgejo.png"; }; }
          { "NocoDB" = { href = "https://nocodb.agrshv.dev"; description = "No-code database"; icon = "nocodb.png"; }; }
          { "Grist" = { href = "https://grist.agrshv.dev"; description = "Spreadsheet database"; icon = "grist.png"; }; }
          { "Authelia" = { href = "https://auth.agrshv.dev"; description = "SSO / auth"; icon = "authelia.png"; }; }
          { "SearXNG" = { href = "https://search.agrshv.dev"; description = "Metasearch"; icon = "searxng.png"; }; }
        ];
      }
    ];

    bookmarks = [
      {
        "Nix" = [
          { "NixOS Options" = [ { href = "https://search.nixos.org/options"; icon = "nixos.png"; } ]; }
          { "Home Manager" = [ { href = "https://home-manager-options.extranix.com"; icon = "nixos.png"; } ]; }
          { "nixflix" = [ { href = "https://github.com/kiriwalawren/nixflix"; icon = "github.png"; } ]; }
        ];
      }
    ];
  };

  # nginx front — apex domain, served off the same agrshv.dev cert (its primary
  # name, not the wildcard). Remember to keep "agrshv.dev" in guardedHosts in
  # ./nginx.nix so the country gate applies here too.
  services.nginx.virtualHosts."agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/".proxyPass = "http://127.0.0.1:8082";
  };

  # ── Live service widgets (opt-in, requires secret plumbing) ────────────────
  # Homepage can show queue depth / library counts by calling each service's API,
  # but the widget config needs the API key inline. Because the unit is a
  # DynamicUser it can't read /root/nixflix/**, so:
  #   1. Add the keys to secrets/workstation.yaml (sops) as e.g. HOMEPAGE_VAR_SONARR.
  #   2. sops.templates."homepage.env".content = "HOMEPAGE_VAR_SONARR=${...}";
  #      with owner = "homepage-dashboard" (or mode 0440 + supplementary group).
  #   3. services.homepage-dashboard.environmentFiles = [ config.sops.templates."homepage.env".path ];
  #   4. In each service entry above add e.g.
  #        widget = { type = "sonarr"; url = "https://sonarr.agrshv.dev"; key = "{{HOMEPAGE_VAR_SONARR}}"; };
}
