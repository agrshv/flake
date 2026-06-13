{
  services.miniflux = {
    enable = true;
    config = {
      CREATE_ADMIN = false;
      BASE_URL = "https://news.agrshv.dev";
    };
  };

  services.nginx.virtualHosts."news.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/".proxyPass = "http://127.0.0.1:8080";
  };
}
