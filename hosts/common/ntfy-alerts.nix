{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ntfyAlerts;

  # A top-level `service.d/` drop-in applies to every system service, so any
  # unit that ends up failed triggers ntfy-alert@<its name> without having to
  # list it. Units entering "failed" is the trigger: a service with Restart=
  # only gets there once its restart limit is exhausted, so flapping is one
  # alert, not one per attempt.
  #
  # The second drop-in keeps the handler from alerting about itself. systemd
  # reads all drop-ins in file-name order regardless of directory, so the
  # empty `OnFailure=` in 20-* resets the list that 10-* just added.
  dropins = pkgs.runCommand "ntfy-alert-dropins" { } ''
    mkdir -p $out/lib/systemd/system/service.d $out/lib/systemd/system/ntfy-alert@.service.d
    cat > $out/lib/systemd/system/service.d/10-ntfy-alert.conf <<'EOF'
    [Unit]
    OnFailure=ntfy-alert@%N.service
    EOF
    cat > $out/lib/systemd/system/ntfy-alert@.service.d/20-no-recursion.conf <<'EOF'
    [Unit]
    OnFailure=
    EOF
  '';
in
{
  options.ntfyAlerts = {
    url = lib.mkOption {
      type = lib.types.str;
      example = "https://ntfy.agrshv.dev:2443/alerts";
      description = "ntfy publish URL, topic included.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.str;
      description = "File providing NTFY_TOKEN=<access token> for the publish.";
    };
  };

  config = {
    systemd.packages = [ dropins ];

    # The instance (%i) is the failed unit's name without the .service suffix.
    systemd.services."ntfy-alert@" = {
      description = "ntfy failure alert: %i";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = cfg.environmentFile;
      };
      scriptArgs = "%i";
      script = ''
        status=$(${pkgs.systemd}/bin/systemctl status --no-pager -n 12 "$1" 2>&1 | tail -12 || true)
        # A failure at boot can come before the network is fully usable, and
        # one lost alert is the failure mode this exists to prevent: retry.
        ${pkgs.curl}/bin/curl -fsS -m 15 --retry 5 --retry-delay 5 --retry-connrefused \
          -H "Authorization: Bearer $NTFY_TOKEN" \
          -H "Title: $1 failed on ${config.networking.hostName}" \
          -H "Priority: high" \
          -H "Tags: rotating_light" \
          -d "$status" \
          ${cfg.url}
      '';
    };
  };
}
