{
  services.postgresql = {
    ensureDatabases = [ "readeck" ];
    ensureUsers = [
      {
        name = "readeck";
        ensureDBOwnership = true;
      }
    ];
  };

  systemd.services.readeck = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
  };

  services.readeck = {
    enable = true;
    environmentFile = "/root/readeck.env";
    settings = {
      server = {
        host = "127.0.0.1";
        port = 8000;
        trusted_proxies = [ "127.0.0.1" ];
        base_url = "https://read.agrshv.dev";
      };
      database = {
        source = "postgres://readeck@/readeck?host=/run/postgresql";
      };
    };
  };
}
