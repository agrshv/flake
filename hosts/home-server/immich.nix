{ config, pkgs-unstable, ... }:
{
  services.immich = {
    enable = true;

    # nixos-26.05 is stuck on immich 2.7.5, which upstream marked insecure
    # (CVE-2026-59258, CVE-2026-82272) and will not patch further — 3.x only
    # lands in 26.11. The 26.05 module drives it unchanged: between the two
    # channels it gained only a `database.package` option and dropped an env
    # var, nothing version-gated, and the machine-learning unit runs
    # `cfg.package.machine-learning`, so this one override moves both services.
    # VectorChord is 1.1.1 either way, so the extension the module loads into
    # Postgres still matches what this build expects.
    package = pkgs-unstable.immich;

    settings.backup.database.enabled = false;
  };

  services.nginx.virtualHosts."immich.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/" = {
      proxyPass = "http://[::1]:${toString config.services.immich.port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = ''
        client_max_body_size 50000M;
        proxy_read_timeout   600s;
        proxy_send_timeout   600s;
        send_timeout         600s;
      '';
    };
  };
}
