{
  # Mealie — self-hosted recipe manager & meal planner. Native NixOS service
  # (the module runs it under a dedicated `mealie` user), bound to loopback and
  # fronted by nginx at recipes.agrshv.dev behind the KZ GeoIP gate.
  #
  # `database.createLocally = true` switches Mealie off its default SQLite onto
  # the shared PostgreSQL in ./postgresql.nix: the module provisions the `mealie`
  # role + db and points Mealie at postgresql://mealie:@/mealie?host=/run/postgresql,
  # i.e. peer auth over the local socket (the service runs as user `mealie`, so
  # no password or trust rule is needed — this is the socket pattern used by
  # readeck here, not the container trust pattern used by nocodb/grist). It also
  # adds the postgresql ordering to the unit, so no extra systemd wiring here.
  #
  # Uploaded recipe images and backups live under DATA_DIR (/var/lib/mealie).
  services.mealie = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9000;
    database.createLocally = true;
    settings = {
      BASE_URL = "https://recipes.agrshv.dev";
      TZ = "Asia/Almaty";
      # Private instance — no open registration. A default admin
      # (changeme@example.com / MyPassword) is created on first start; log in and
      # change those credentials immediately.
      ALLOW_SIGNUP = "false";
    };
  };

  services.nginx.virtualHosts."recipes.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/" = {
      proxyPass = "http://127.0.0.1:9000";
      proxyWebsockets = true;
    };
  };
}
