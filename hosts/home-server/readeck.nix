{ config, ... }:
{
  sops.secrets."readeck/env".restartUnits = [ "readeck.service" ];

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
    environmentFile = config.sops.secrets."readeck/env".path;
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
