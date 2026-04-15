{
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  users.users.nginx.extraGroups = [ "acme" ];

  security.acme = {
    acceptTerms = true;
    defaults.email = "acme@agrshv.dev";
    certs."agrshv.dev" = {
      extraDomainNames = [ "*.agrshv.dev" ];
      dnsProvider = "cloudflare";
      environmentFile = "/root/acme.env";
    };
  };

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts = {
      "read.agrshv.dev" = {
        forceSSL = true;
        useACMEHost = "agrshv.dev";
        locations."/".proxyPass = "http://127.0.0.1:8000";
      };
      "docs.agrshv.dev" = {
        forceSSL = true;
        useACMEHost = "agrshv.dev";
      };
      "search.agrshv.dev" = {
        forceSSL = true;
        useACMEHost = "agrshv.dev";
        locations."/".proxyPass = "http://127.0.0.1:8888";
      };
    };
  };
}
