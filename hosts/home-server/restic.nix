{ config, ... }:
let
  # Units whose on-disk SQLite databases are in the restic path set; paused
  # while the backup runs (see backupPrepareCommand below).
  sqliteServices = builtins.concatStringsSep " " [
    "navidrome.service" # /var/lib/navidrome/navidrome.db
    "podman-grist.service" # /var/lib/grist/docs/*.grist, grist-sessions.db
    "wrtagweb.service" # /var/lib/wrtag/wrtag.db
    "paperless-scheduler.service" # /var/lib/paperless/celerybeat-schedule.db
  ];
in
{
  # Consistent SQL dumps of the whole Postgres cluster (pg_dumpall: immich,
  # paperless, readeck, miniflux, authelia, forgejo, grist, nocodb, mealie, …)
  # so restic captures a coherent snapshot instead of a live, possibly-
  # inconsistent data directory. Dumps land in /var/backup/postgresql/all.sql.zstd.
  services.postgresqlBackup = {
    enable = true;
    compression = "zstd";
    startAt = "*-*-* 02:00:00";
  };

  # Same for Monica's MariaDB (the only non-Postgres database on the box).
  # Runs as the `mysql` user over the local socket; lands in
  # /var/backup/mysql/monica.gz.
  services.mysqlBackup = {
    enable = true;
    databases = [ "monica" ];
    calendar = "02:00:00";
  };

  sops.secrets = {
    "restic/repository" = { };
    "restic/password" = { };
    "restic/env" = { };
  };

  services.restic.backups.home-server = {
    # Create the repo on first run if it doesn't exist yet.
    initialize = true;

    # Credentials come from secrets/home-server.yaml. Backblaze B2 via its
    # S3-compatible API (not the native b2: backend):
    #   restic/repository : repo URL, e.g.
    #       "s3:https://s3.us-west-004.backblazeb2.com/my-bucket/home-server"
    #       (use the endpoint host B2 shows for the bucket; region varies)
    #   restic/password   : the repo encryption password
    #   restic/env        : S3 creds — the B2 application key, e.g.
    #                         AWS_ACCESS_KEY_ID=<keyID>
    #                         AWS_SECRET_ACCESS_KEY=<applicationKey>
    # Keep an off-box copy of restic/password: recovering the box needs it
    # before sops can be of any help.
    repositoryFile = config.sops.secrets."restic/repository".path;
    passwordFile = config.sops.secrets."restic/password".path;
    environmentFile = config.sops.secrets."restic/env".path;

    # NOTE: restic does not follow symlinks. Services with DynamicUser=true
    # (readeck, mealie, gitea-runner) expose /var/lib/<name> only as a symlink
    # into /var/lib/private/<name> — always list the real path, or the snapshot
    # contains a 0-byte link and nothing else.
    paths = [
      # Database dumps
      "/var/backup/postgresql" # all Postgres DBs (see services.postgresqlBackup)
      "/var/backup/mysql" # Monica (MariaDB)

      # Bulk user data
      "/var/lib/immich" # photo/video originals + in-flight uploads
      "/var/lib/navidrome" # music library + navidrome.db
      "/var/lib/paperless" # document archive, originals, search index
      "/var/lib/private/readeck" # saved articles + assets
      "/var/lib/forgejo" # git repositories, LFS, generated app secrets
      "/var/lib/grist" # Grist documents (SQLite per doc) — PG only holds the home DB
      "/var/lib/nocodb" # attachments
      "/var/lib/private/mealie" # recipe images + app secrets
      "/var/lib/monica" # uploads + APP_KEY (encrypts data in the DB dump)
      "/var/lib/wrtag" # import queue db

      # Secrets / identity that can't be regenerated
      "/var/lib/authelia-main" # storage-encryption-key, jwt/session secrets, OIDC key, users.yml
      "/var/lib/bulwark" # admin config + password hash from the setup wizard
      "/var/lib/private/gitea-runner" # registration token + .runner identity
      "/root" # anything left out-of-band; service creds now live in sops
      "/etc/ssh" # host keys — Forgejo clone URLs pin them AND sops decrypts with them
      "/var/lib/nixos" # uid/gid maps — restored files must land on the same numeric ids
    ];

    exclude = [
      # Regenerable caches — immich rebuilds these from originals, no need to ship them off-site.
      "/var/lib/immich/thumbs"
      "/var/lib/immich/encoded-video"
      "/var/lib/navidrome/cache"
      "/var/lib/private/gitea-runner/home-server/.cache"
      "/root/.cache"
    ];

    # Several services keep SQLite databases inside the paths above (navidrome.db,
    # Grist documents, wrtag.db, paperless' celerybeat schedule). Restic copies
    # files live with no filesystem snapshot, so a write landing mid-read would
    # leave a torn copy. Stop those writers for the duration of the run and bring
    # them back afterwards — the cleanup hook runs even if the backup fails.
    # (The SQL databases are not affected: they're captured via pg_dumpall /
    # mysqldump, which are consistent by themselves.)
    backupPrepareCommand = ''
      systemctl stop ${sqliteServices}
    '';
    backupCleanupCommand = ''
      systemctl start ${sqliteServices}
    '';

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
    ];

    timerConfig = {
      # Run after the DB dumps (02:00). Persistent catches up after downtime.
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;
      RandomizedDelaySec = "15min";
    };
  };
}
