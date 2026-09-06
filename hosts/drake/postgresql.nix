{
  # No databases yet — enabled ahead of the services that will want it.
  # Add them with ensureDatabases/ensureUsers as on home-server.
  services.postgresql.enable = true;

  # Nightly cluster dump (pg_dumpall) into /var/backup/postgresql, an hour
  # before the restic run picks it up — same rhythm as home-server.
  services.postgresqlBackup = {
    enable = true;
    compression = "zstd";
    startAt = "*-*-* 02:00:00";
  };

  systemd.services.postgresqlBackup.onFailure = [ "ntfy-alert@postgresqlBackup.service" ];
}
