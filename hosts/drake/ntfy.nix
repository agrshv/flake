{ config, pkgs, ... }:
{
  sops.secrets = {
    "acme/env".restartUnits = [ "acme-ntfy.agrshv.dev.service" ];
    # NTFY_AUTH_USERS / NTFY_AUTH_TOKENS (declarative auth db entries) plus
    # NTFY_TOKEN, which only the ntfy-alert@/ntfy-ok@ units below use. The
    # user password's plaintext lives in Bitwarden ("drake ntfy").
    "ntfy/env".restartUnits = [ "ntfy-sh.service" ];
  };

  # DNS-01 like home-server, so no port 80 is needed and issuance works even
  # while ntfy.agrshv.dev has no A record yet (clients need the record, the
  # challenge doesn't).
  security.acme = {
    acceptTerms = true;
    defaults.email = "acme@agrshv.dev";
    certs."ntfy.agrshv.dev" = {
      dnsProvider = "cloudflare";
      environmentFile = config.sops.secrets."acme/env".path;
      reloadServices = [ "ntfy-sh.service" ];
    };
  };

  services.ntfy-sh = {
    enable = true;
    environmentFile = config.sops.secrets."ntfy/env".path;
    settings = {
      # 2443 because stalwart owns 443. The module's default listen-http on
      # 127.0.0.1:2586 stays too — the alert units publish there, so local
      # notifications never depend on the certificate or the firewall.
      base-url = "https://ntfy.agrshv.dev:2443";
      listen-https = ":2443";
      key-file = "/run/credentials/ntfy-sh.service/key.pem";
      cert-file = "/run/credentials/ntfy-sh.service/cert.pem";
      # Not an open relay: only the declarative users above may read or write.
      auth-default-access = "deny-all";
      # Lets the iOS app get instant delivery from a self-hosted server.
      upstream-base-url = "https://ntfy.sh";
    };
  };

  systemd.services.ntfy-sh = {
    # The cert is acme-owned under /var/lib/acme; LoadCredential (set up by
    # PID 1) hands it to the DynamicUser sandbox without loosening ownership.
    # Order after the issuing unit itself: this nixpkgs has no
    # acme-finished-<domain>.target, and naming a unit that doesn't exist
    # silently drops the ordering — which is how the first deploy raced ACME
    # and died at step CREDENTIALS.
    after = [ "acme-ntfy.agrshv.dev.service" ];
    wants = [ "acme-ntfy.agrshv.dev.service" ];
    serviceConfig.LoadCredential = [
      "cert.pem:/var/lib/acme/ntfy.agrshv.dev/fullchain.pem"
      "key.pem:/var/lib/acme/ntfy.agrshv.dev/key.pem"
    ];
  };

  # Attach to any unit via onFailure/onSuccess, e.g.
  #   onFailure = [ "ntfy-alert@restic-backups-drake.service" ];
  # The instance (%i) is the failed unit's name without the .service suffix.
  systemd.services."ntfy-alert@" = {
    description = "ntfy failure alert: %i";
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.sops.secrets."ntfy/env".path;
    };
    scriptArgs = "%i";
    script = ''
      status=$(${pkgs.systemd}/bin/systemctl status --no-pager -n 12 "$1" 2>&1 | tail -12 || true)
      ${pkgs.curl}/bin/curl -fsS -m 15 \
        -H "Authorization: Bearer $NTFY_TOKEN" \
        -H "Title: $1 failed on drake" \
        -H "Priority: high" \
        -H "Tags: rotating_light" \
        -d "$status" \
        http://127.0.0.1:2586/alerts
    '';
  };

  systemd.services."ntfy-ok@" = {
    description = "ntfy success ping: %i";
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.sops.secrets."ntfy/env".path;
    };
    scriptArgs = "%i";
    script = ''
      ${pkgs.curl}/bin/curl -fsS -m 15 \
        -H "Authorization: Bearer $NTFY_TOKEN" \
        -H "Title: $1 completed on drake" \
        -H "Priority: low" \
        -H "Tags: white_check_mark" \
        -d "ok" \
        http://127.0.0.1:2586/alerts
    '';
  };

  networking.firewall.allowedTCPPorts = [ 2443 ];
}
