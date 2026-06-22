{ config, ... }:
{
  services.actual = {
    enable = true;
    settings = {
      hostname = "127.0.0.1";
      port = 5006;
    };
  };

  services.nginx.virtualHosts."budget.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.actual.settings.port}";
      proxyWebsockets = true;
    };
  };
}
