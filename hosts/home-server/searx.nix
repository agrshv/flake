{ config, ... }:
{
  sops.secrets."searx/env".restartUnits = [ "searx.service" ];

  services.searx = {
    enable = true;
    environmentFile = config.sops.secrets."searx/env".path;
    settings = {
      server = {
        bind_address = "127.0.0.1";
        port = 8888;
        base_url = "https://search.agrshv.dev";
        secret_key = "$SEARX_SECRET_KEY";
      };
    };
  };
}
