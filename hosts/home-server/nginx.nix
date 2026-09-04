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
    "agrshv.dev"
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
    "monica.agrshv.dev"
    "dawarich.agrshv.dev"
    "tube.agrshv.dev"
    "nocodb.agrshv.dev"
    "recipes.agrshv.dev"
    "webmail.agrshv.dev"
    "vault.agrshv.dev"
    # nixflix-defined vhosts (see ./nixflix.nix) — the module builds these
    # itself, so they're easy to forget here. The assertion below catches that.
    "jellyfin.agrshv.dev"
    "seerr.agrshv.dev"
    "prowlarr.agrshv.dev"
    "qbittorrent.agrshv.dev"
    "radarr.agrshv.dev"
    "sonarr.agrshv.dev"
    "sonarr-anime.agrshv.dev"
  ];

  # Vhosts deliberately outside the country gate.
  exemptHosts = [
    "_" # nixflix's catch-all default server: listens on :80 only, serves nothing
  ];

  # guardedHosts can't be derived from config.services.nginx.virtualHosts —
  # the geo-guard definitions below would make the vhost attribute names depend
  # on themselves (infinite recursion). Reading it in an assertion is fine.
  unguardedHosts = lib.subtractLists (guardedHosts ++ exemptHosts) (
    lib.attrNames config.services.nginx.virtualHosts
  );
in
{
  # Fail closed: any vhost defined anywhere in the config (including by modules
  # like nixflix) must be in guardedHosts or exemptHosts, or the build aborts —
  # a new service can't silently ship without the country gate.
  assertions = [
    {
      assertion = unguardedHosts == [ ];
      message = "nginx vhosts missing the geo gate — add them to guardedHosts (or exemptHosts) in hosts/home-server/nginx.nix: ${lib.concatStringsSep ", " unguardedHosts}";
    }
  ];

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  users.users.nginx.extraGroups = [ "acme" ];

  sops.secrets = {
    "acme/env".restartUnits = [ "acme-agrshv.dev.service" ];
    "maxmind/license_key".restartUnits = [ "geoipupdate.service" ];
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "acme@agrshv.dev";
    certs."agrshv.dev" = {
      extraDomainNames = [ "*.agrshv.dev" ];
      dnsProvider = "cloudflare";
      environmentFile = config.sops.secrets."acme/env".path;
    };
  };

  # ── GeoIP allow-listing (Kazakhstan only) ───────────────────────────────────
  # Replaces CrowdSec's role of keeping hostile traffic off the web stack.
  # MaxMind GeoLite2 needs a (free) account: sign up, create a license key, then
  #   1. set AccountID below to your numeric MaxMind account ID,
  #   2. put the license key in sops as `maxmind/license_key`,
  #   3. run `systemctl start geoipupdate` once so the DB exists before nginx
  #      starts (nginx fails to load if the .mmdb is missing — see ordering
  #      below). After that the timer refreshes it weekly.
  services.geoipupdate = {
    enable = true;
    settings = {
      AccountID = 1368186;
      LicenseKey = config.sops.secrets."maxmind/license_key".path;
      EditionIDs = [ "GeoLite2-Country" ];
    };
  };

  # Workaround for a bug in this nixpkgs' geoipupdate module: its ExecStartPre
  # runs `chown geoip <dbdir>` with full privileges (`+`), but with
  # PrivateUsers = true the dynamically-allocated `geoip` user isn't resolvable
  # by name in that context, so the chown fails with `invalid user: 'geoip'` and
  # the unit aborts. Dropping PrivateUsers for this unit makes the dynamic user
  # host-visible so the chown resolves. (No secrets are handed to this unit.)
  systemd.services.geoipupdate.serviceConfig.PrivateUsers = lib.mkForce false;

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
          # Paperless' nginx vhost inherits the global 10m clientMaxBodySize,
          # which rejects larger scans/PDFs with 413 before they reach the app.
          # Raise it just for this vhost (merges with the geo-guard extraConfig).
          extraConfig = ''
            client_max_body_size 100m;
          '';
        };
        "search.agrshv.dev" = {
          forceSSL = true;
          useACMEHost = "agrshv.dev";
          locations."/".proxyPass = "http://127.0.0.1:8888";
        };
        # The apex used to serve the Homepage dashboard. Kept as an explicit
        # vhost that answers nothing: the catch-all default server only listens
        # on :80, so without this an HTTPS request for agrshv.dev would fall
        # through to whichever SSL vhost nginx orders first.
        "agrshv.dev" = {
          forceSSL = true;
          useACMEHost = "agrshv.dev";
          locations."/".return = "444";
        };
      };
    }

    # Apply the country gate to every public vhost.
    {
      virtualHosts = lib.genAttrs guardedHosts (_: { extraConfig = geoGuard; });
    }
  ];
}
