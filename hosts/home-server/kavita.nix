{ config, ... }:
{
  # Signs Kavita's login JWTs; rotating it logs every client out. The file is
  # the bare key (no KEY= prefix), e.g. `head -c 64 /dev/urandom | base64 -w0`.
  sops.secrets."kavita/token-key".restartUnits = [ "kavita.service" ];

  # Kavita — ebook / comic / manga library with a web reader, OPDS feed and
  # KOReader progress sync. Deliberately NOT behind Authelia forward-auth: OPDS
  # readers and KOReader talk to the API directly and can't follow a login
  # redirect, so Kavita's own accounts are the gate (as with vaultwarden). The
  # country gate in ./nginx.nix still applies.
  #
  # Books go in /var/lib/kavita/library (owned by kavita; uploaded through
  # ./dufs.nix); add its subfolders as libraries in the web UI. Each book or
  # series needs a folder of its own — files loose in a library's top level
  # are skipped by the scanner.
  services.kavita = {
    enable = true;
    tokenKeyFile = config.sops.secrets."kavita/token-key".path;
    settings = {
      IpAddresses = "127.0.0.1";
      Port = 5000;
    };
  };

  systemd.tmpfiles.settings."10-kavita"."/var/lib/kavita/library".d = {
    mode = "0750";
    user = "kavita";
    group = "kavita";
  };

  services.nginx.virtualHosts."books.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.kavita.settings.Port}";
      # The web reader and live library updates use a SignalR websocket.
      proxyWebsockets = true;
    };
  };
}
