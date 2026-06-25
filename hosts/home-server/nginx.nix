{
  config,
  pkgs,
  lib,
  ...
}:
let
  # MaxMind GeoLite2 country DB, refreshed by services.geoipupdate below.
  geoipDb = "${config.services.geoipupdate.settings.DatabaseDirectory}/GeoLite2-Country.mmdb";

  # Per-vhost guard: drop anything that isn't allowed. 444 closes the
  # connection with no response (stealthier than 403 for scanners); swap to
  # `return 403;` if you'd rather send an explicit refusal.
  geoGuard = ''
    if ($geo_allowed = block) { return 444; }
  '';

  # Every public vhost we serve. Listed explicitly so the country gate is
  # applied uniformly, including to vhosts defined by other modules
  # (paperless, slskd, immich, …). extraConfig is `types.lines`, so this
  # merges with each vhost's own definition rather than clobbering it.
  guardedHosts = [
    "read.agrshv.dev"
    "docs.agrshv.dev"
    "search.agrshv.dev"
    "git.agrshv.dev"
    "immich.agrshv.dev"
    "news.agrshv.dev"
    "music.agrshv.dev"
    "budget.agrshv.dev"
    "slskd.agrshv.dev"
    "wrtag.agrshv.dev"
    "auth.agrshv.dev"
  ];
in
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

  # ── GeoIP allow-listing (Kazakhstan only) ───────────────────────────────────
  # Replaces CrowdSec's role of keeping hostile traffic off the web stack.
  # MaxMind GeoLite2 needs a (free) account: sign up, create a license key, then
  #   1. set AccountID below to your numeric MaxMind account ID,
  #   2. write the license key to /root/maxmind on the host (root-only),
  #   3. run `systemctl start geoipupdate` once so the DB exists before nginx
  #      starts (nginx fails to load if the .mmdb is missing — see ordering
  #      below). After that the timer refreshes it weekly.
  services.geoipupdate = {
    enable = true;
    settings = {
      AccountID = 1368186;
      LicenseKey = "/root/maxmind";
      EditionIDs = [ "GeoLite2-Country" ];
    };
  };

  # nginx's geoip2 module opens the .mmdb at startup, so make sure the DB has
  # been fetched first. `wants` (not `requires`) so a failed update doesn't hard
  # block nginx — but note nginx will still fail to start if the DB is absent.
  systemd.services.nginx = {
    after = [ "geoipupdate.service" ];
    wants = [ "geoipupdate.service" ];
  };

  services.nginx = lib.mkMerge [
    {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      additionalModules = [ pkgs.nginxModules.geoip2 ];

      appendHttpConfig = ''
        # Resolve the visitor's country from the MaxMind DB. Unknown / private
        # addresses resolve to an empty string. NOTE: this keys off
        # $remote_addr — if you ever put these behind Cloudflare's proxy you'll
        # need real-IP restoration first, or every client looks like Cloudflare.
        geoip2 ${geoipDb} {
          auto_reload 60m;
          $geoip2_country_iso source=$remote_addr country iso_code;
        }

        # Loopback + RFC1918 are always allowed (the DB returns no country for
        # them), so local and LAN access is never geo-blocked. The NetBird
        # overlay (wt0, 100.78.0.0/16) is likewise trusted so VPN peers aren't
        # dropped by the country gate (MaxMind returns no country for it).
        geo $geo_internal {
          default        block;
          127.0.0.0/8    allow;
          ::1/128        allow;
          10.0.0.0/8     allow;
          172.16.0.0/12  allow;
          192.168.0.0/16 allow;
          100.78.0.0/16  allow;
        }

        map $geoip2_country_iso $geo_country_allowed {
          default block;
          KZ      allow;
        }

        # Allowed when the request is internal OR from Kazakhstan, i.e. when
        # either input above said "allow".
        map "$geo_internal$geo_country_allowed" $geo_allowed {
          default  block;
          "~allow" allow;
        }
      '';

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
    }

    # Apply the country gate to every public vhost.
    {
      virtualHosts = lib.genAttrs guardedHosts (_: { extraConfig = geoGuard; });
    }
  ];
}
