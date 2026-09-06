{ config, ... }:
{
  sops.secrets = {
    "restic/repository" = { };
    "restic/password" = { };
    "restic/env" = { };
  };

  services.restic.backups.drake = {
    initialize = true;

    # Same B2 bucket and credentials as home-server (see its restic.nix for
    # the format), under the /drake prefix, and the same repo password — one
    # thing to keep off-box (Bitwarden) for disaster recovery.
    repositoryFile = config.sops.secrets."restic/repository".path;
    passwordFile = config.sops.secrets."restic/password".path;
    environmentFile = config.sops.secrets."restic/env".path;

    paths = [
      "/var/backup/postgresql" # nightly pg_dumpall (see ./postgresql.nix)
      "/var/lib/stalwart" # the mail store — accounts, mail, certs, DKIM
      "/var/lib/netbird" # peer identity: keeps the overlay address across reinstalls
      "/etc/ssh" # host keys — sops decrypts with them
      "/var/lib/nixos" # uid/gid maps
      "/root"
    ];

    exclude = [ "/root/.cache" ];

    # Stalwart's RocksDB can't be copied while it writes (torn sst files), and
    # there is no dump tool short of the DB's own snapshots — stop the
    # container for the run, exactly like home-server pauses its sqlite
    # writers. Senders retry; a few quiet minutes at 03:00 cost nothing.
    backupPrepareCommand = ''
      systemctl stop podman-stalwart.service
    '';
    backupCleanupCommand = ''
      systemctl start podman-stalwart.service
    '';

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
    ];

    # Verify the repo after each run: structural check + a random 5% of pack
    # data re-read, as on home-server.
    checkOpts = [ "--read-data-subset=5%" ];

    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;
      RandomizedDelaySec = "15min";
    };
  };

  systemd.services.restic-backups-drake = {
    onFailure = [ "ntfy-alert@restic-backups-drake.service" ];
    onSuccess = [ "ntfy-ok@restic-backups-drake.service" ];
  };
}
