{ ... }:
{
  # Consistent SQL dumps of the whole Postgres cluster (immich, paperless,
  # readeck, miniflux all live here) so restic captures a coherent snapshot
  # instead of a live, possibly-inconsistent data directory.
  # Dumps land in /var/backup/postgresql/all.sql.zstd.
  services.postgresqlBackup = {
    enable = true;
    compression = "zstd";
    startAt = "*-*-* 02:00:00";
  };

  services.restic.backups.home-server = {
    # Create the repo on first run if it doesn't exist yet.
    initialize = true;

    # Credentials live outside the repo, matching the other services here.
    #   /root/restic-repository : repo URL, e.g. "b2:my-bucket:home-server"
    #   /root/restic-password   : the repo encryption password
    #   /root/restic.env        : backend creds, e.g.
    #                               B2_ACCOUNT_ID=...
    #                               B2_ACCOUNT_KEY=...
    repositoryFile = "/root/restic-repository";
    passwordFile = "/root/restic-password";
    environmentFile = "/root/restic.env";

    paths = [
      "/var/backup/postgresql" # Postgres dumps (covers immich/paperless/readeck/miniflux DBs)
      "/var/lib/immich" # photo/video originals
      "/var/lib/navidrome" # music library + navidrome.db
      "/var/lib/paperless" # document archive + originals
      "/var/lib/readeck" # saved articles + assets
    ];

    # Regenerable caches — immich rebuilds these from originals, no need to ship them off-site.
    exclude = [
      "/var/lib/immich/thumbs"
      "/var/lib/immich/encoded-video"
    ];

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
    ];

    timerConfig = {
      # Run after the Postgres dump (02:00). Persistent catches up after downtime.
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;
      RandomizedDelaySec = "15min";
    };
  };
}
