{
  inputs,
  pkgs-unstable,
  config,
  ...
}:
{
  # RomM — self-hosted ROM library manager: scans a ROM collection, scrapes
  # metadata/artwork (IGDB, ScreenScraper, MobyGames), syncs saves and save
  # states, and plays games in the browser through EmulatorJS. Served at
  # roms.agrshv.dev.
  #
  # nixos-26.05 ships neither the `romm` package nor a services.romm module, so
  # both come from nixpkgs-unstable:
  #
  #   * the module file is imported straight out of the input below, and
  #   * the two packages it hardcodes by name — `romm` itself and `rahasher`,
  #     which it puts on the units' PATH to compute Redump/No-Intro checksums —
  #     are grafted into pkgs by the overlay. Neither attribute exists in
  #     stable, so the overlay only adds; nothing else in the closure changes.
  #
  # `rahasher` has to go through pkgs (the module reads `pkgs.rahasher`
  # directly, with no option to override), and once the overlay is there the
  # module's own `package` default (pkgs.romm) resolves too — hence no explicit
  # services.romm.package below. Drop the import and the overlay when a stable
  # nixpkgs picks the module up.
  imports = [
    "${inputs.nixpkgs-unstable}/nixos/modules/services/web-apps/romm.nix"
  ];

  nixpkgs.overlays = [
    (_: _: { inherit (pkgs-unstable) romm rahasher; })
  ];

  services.romm = {
    enable = true;

    # 8080 is miniflux and 8083 nocodb, so the API lands on 8084. Only nginx
    # talks to it (loopback is the module default).
    port = 8084;

    # database.createLocally and redis.createLocally are left at their defaults:
    #   * the `romm` role + database are added to the shared PostgreSQL in
    #     ./postgresql.nix and reached over the local socket with peer auth
    #     (the DB_PASSWD the app insists on is a dummy — see the module), and
    #   * a dedicated instance for the RQ job queue that drives scans and
    #     scraping, services.redis.servers.romm on loopback TCP 6379. RomM
    #     cannot speak to Redis over a unix socket, which is why this one is
    #     the only Redis here on TCP; it still runs Valkey like the rest
    #     (see ./redis.nix).
    nginx.virtualHost = "roms.agrshv.dev";

    # Metadata providers need API credentials — see the bootstrap note below.
    environmentFile = config.sops.secrets."romm/env".path;
  };

  # The module builds the vhost itself: it serves the frontend from the store,
  # hands out ROM downloads via X-Accel-Redirect / mod_zip, and sets the
  # cross-origin isolation headers EmulatorJS' threaded cores need. Only TLS is
  # left to do here. NB: roms.agrshv.dev also has to be listed in guardedHosts
  # in ./nginx.nix or the build fails the geo-gate assertion.
  services.nginx.virtualHosts."roms.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
  };

  # RomM has its own user database and session cookies, so it is exposed
  # directly like Immich and Forgejo rather than behind Authelia's forward auth
  # — its REST API is what the Playnite/handheld clients use, and they cannot
  # follow the portal redirect. The country gate in ./nginx.nix still applies.
  #
  # ── First run ───────────────────────────────────────────────────────────────
  # 1. ROMs live under /var/lib/romm/library (the path is fixed by upstream),
  #    laid out per platform using its folder slugs:
  #
  #      /var/lib/romm/library/roms/gbc/…      # one dir per platform
  #      /var/lib/romm/library/bios/psx/…      # optional BIOS files
  #
  #    The dirs are created 0750 romm:romm by tmpfiles; drop files in as root
  #    and `chown -R romm:romm /var/lib/romm/library`. To keep the collection
  #    on another disk, bind-mount it at that path instead. Uploading through
  #    the web UI works too and gets the ownership right by itself.
  # 2. Open https://roms.agrshv.dev and create the account — the first user
  #    registered becomes the admin.
  # 3. romm-watcher rescans on filesystem changes; a manual scan is under
  #    Settings → Library.
  #
  # ── Metadata providers (optional) ───────────────────────────────────────────
  # Without credentials RomM only shows filenames. IGDB is the main source:
  # register an application at https://dev.twitch.tv/console/apps to get a
  # client id/secret, then add them to secrets/home-server.yaml
  #
  #   sops secrets/home-server.yaml     # add a `romm: env: |` block holding
  #                                     #   IGDB_CLIENT_ID=…
  #                                     #   IGDB_CLIENT_SECRET=…
  #                                     #   SCREENSCRAPER_USER=…      (optional)
  #                                     #   SCREENSCRAPER_PASSWORD=…  (optional)
  #
  # and uncomment both the sops.secrets line and services.romm.environmentFile
  # above. ROMM_AUTH_SECRET_KEY is *not* needed there: the module generates one
  # on first start and persists it in /var/lib/romm/.auth-secret.env (which is
  # in the restic path set, so sessions survive a rebuild).
  sops.secrets."romm/env".restartUnits = [
    "romm.service"
    "romm-worker.service"
    "romm-scheduler.service"
    "romm-watcher.service"
  ];
}
