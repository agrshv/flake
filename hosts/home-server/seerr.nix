{ config, lib, ... }:
{
  # Seerr — the request UI, signing in with Jellyfin accounts. Jellyfin,
  # Sonarr and Radarr connections are set in its web UI and stored in
  # settings.json; requests and users are in Postgres.
  services.seerr = {
    enable = true;
    # Upstream picks /var/lib/jellyseerr/config below stateVersion 26.05. Keep
    # the existing /var/lib/seerr instead: on first start under DynamicUser,
    # systemd moves it to /var/lib/private/seerr and chowns it.
    configDir = "/var/lib/seerr";
  };

  services.postgresql = {
    ensureDatabases = [ "seerr" ];
    ensureUsers = [
      {
        name = "seerr";
        ensureDBOwnership = true;
      }
    ];
  };

  systemd.services.seerr = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    # Peer auth over the socket; the dynamic user is named `seerr`.
    environment = {
      DB_TYPE = "postgres";
      DB_SOCKET_PATH = "/run/postgresql";
      DB_USER = "seerr";
      DB_NAME = "seerr";
    };
    serviceConfig.StateDirectory = lib.mkForce "seerr";
  };

  services.nginx.virtualHosts."seerr.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/".proxyPass = "http://127.0.0.1:${toString config.services.seerr.port}";
  };
}
