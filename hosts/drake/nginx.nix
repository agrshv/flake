{ config, lib, ... }:
let
  # Stalwart's HTTPS listener (JMAP, web admin, autoconfig/autodiscover,
  # MTA-STS), moved off :443. It still terminates TLS itself with its own ACME
  # certificate; nginx only routes the raw TLS stream to it.
  stalwartHttps = "127.0.0.1:10443";
  # nginx's own TLS-terminating vhosts (http block), reached only through the
  # SNI router below.
  nginxHttps = "127.0.0.1:9443"; # not 8443: xray (./xray.nix) has it

  # Every vhost nginx terminates itself; any other SNI (mail.*, autoconfig.*,
  # clients connecting by IP or without SNI) falls through to Stalwart, so
  # mail keeps behaving exactly as it did when Stalwart owned :443.
  nginxHosts = lib.filter (h: h != "_") (lib.attrNames config.services.nginx.virtualHosts);
in
{
  # nginx owns :80 and :443 on drake.
  #
  #   :443 ─ stream, ssl_preread ─┬─ SNI of an nginx vhost ─> 127.0.0.1:9443 (http block, TLS here)
  #                                └─ anything else ────────> Stalwart 127.0.0.1:10443 (TLS passthrough)
  #
  # Both hops carry the PROXY protocol so the real client address survives:
  # Stalwart needs it for auto-ban and rate limits (without it every client is
  # 127.0.0.1, and one bad login run bans everyone), nginx for allow/deny.
  #
  # ── Stalwart side (in its DB, not here; web admin via
  #    `ssh -L 8080:127.0.0.1:8080 drake` → http://localhost:8080/admin) ─────────
  #   Listener "https": bind 127.0.0.1:10443 (was [::]:443), and
  #   overrideProxyTrustedNetworks = 127.0.0.1/32 so it reads the PROXY header.
  #   Listener-level on purpose: the global proxyTrustedNetworks would demand a
  #   PROXY header on every loopback connection to every listener (SMTP too).
  #   Restart podman-stalwart, then deploy: nginx can't bind :443 until
  #   Stalwart lets go of it, and a failed activation rolls the deploy back.
  # ────────────────────────────────────────────────────────────────────────────

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  users.users.nginx.extraGroups = [ "acme" ];

  # Shared by every cert on drake (ntfy, the nginx vhosts). DNS-01 against
  # Cloudflare: nothing needs to be reachable for issuance.
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "acme@agrshv.dev";
      dnsProvider = "cloudflare";
      environmentFile = config.sops.secrets."acme/env".path;
      # lego finds the zone by walking up SOA records. The host resolver is
      # NetBird's, whose own agrshv.dev zone answers our names authoritatively
      # (CNAMEs to *.netbird.cloud) but has no SOA, so lego walks past
      # agrshv.dev to "dev." and Cloudflare has no such zone. Ask public DNS.
      dnsResolver = "1.1.1.1:53";
    };
  };

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # Vhosts listen on :80 publicly (redirects only, via forceSSL) and on the
    # loopback TLS port behind the SNI router.
    defaultListen = [
      {
        addr = "0.0.0.0";
        port = 80;
        ssl = false;
      }
      {
        addr = "[::]";
        port = 80;
        ssl = false;
      }
      {
        addr = "127.0.0.1";
        port = 9443;
        ssl = true;
        proxyProtocol = true;
      }
    ];

    # Restore the client address from the router's PROXY header.
    appendHttpConfig = ''
      set_real_ip_from 127.0.0.1;
      real_ip_header proxy_protocol;
    '';

    streamConfig = ''
      map $ssl_preread_server_name $sni_upstream {
        default ${stalwartHttps};
      ${lib.concatMapStrings (h: "  ${h} ${nginxHttps};\n") nginxHosts}}

      server {
        listen 443;
        listen [::]:443;
        ssl_preread on;
        proxy_pass $sni_upstream;
        proxy_protocol on;
        # JMAP push (EventSource/WebSocket) holds connections open for long.
        proxy_timeout 1h;
      }
    '';

    # Requests on :80 for a name we don't serve get dropped.
    virtualHosts."_" = {
      default = true;
      listen = [
        {
          addr = "0.0.0.0";
          port = 80;
        }
        {
          addr = "[::]";
          port = 80;
        }
      ];
      locations."/".return = "444";
    };
  };
}
