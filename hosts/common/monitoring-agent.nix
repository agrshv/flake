{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.monitoring;

  # node_exporter's textfile collector reads every *.prom file in here; the
  # writers below drop their metrics into it.
  textfileDir = "/var/lib/node-exporter-textfile";

  # Write a .prom file atomically: node_exporter must never read a half-written one.
  writeProm = name: body: ''
    tmp=$(mktemp ${textfileDir}/.${name}.XXXXXX)
    {
    ${body}
    } > "$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" ${textfileDir}/${name}.prom
  '';

  acmeCerts = lib.attrNames config.security.acme.certs;
  resticBackups = lib.attrNames config.services.restic.backups;
in
{
  # Everything a host needs to be watched by the stack on drake
  # (../drake/monitoring.nix): metrics are scraped from node_exporter over
  # NetBird, logs are pushed with systemd-journal-upload.
  options.monitoring.victoriaLogsUrl = lib.mkOption {
    type = lib.types.str;
    default = "http://drake.netbird.cloud:9428";
    description = "VictoriaLogs base URL that this host's journal is uploaded to.";
  };

  config = lib.mkMerge [
    {
      services.prometheus.exporters.node = {
        enable = true;
        port = 9100;
        # systemd: per-unit state, so failed units are graphable/alertable.
        enabledCollectors = [ "systemd" ];
        extraFlags = [ "--collector.textfile.directory=${textfileDir}" ];
      };
      # Only the overlay: drake scrapes over NetBird, nothing else needs it.
      networking.firewall.interfaces.wt0.allowedTCPPorts = [ 9100 ];

      systemd.tmpfiles.rules = [ "d ${textfileDir} 0755 root root -" ];

      # Ship the whole journal to VictoriaLogs, which takes journald's native
      # upload format at /insert/journald (journal-upload appends /upload).
      # The first run uploads the existing journal too; VictoriaLogs drops what
      # is older than its retention.
      services.journald.upload = {
        enable = true;
        settings.Upload.URL = "${cfg.victoriaLogsUrl}/insert/journald";
      };
      # If drake is unreachable (reboot, deploy), keep retrying quietly instead
      # of hitting the start limit and firing a failure alert for a log shipper.
      #
      # journal-upload exits whenever drake is unreachable (down, rebooting,
      # not yet deployed). switch-to-configuration counts any unit that fails
      # during a switch, even one Restart= is about to retry, and exits 4;
      # deploy-rs then rolls the whole deploy back. So retry inside the unit
      # instead: the loop never exits, the unit never fails, nothing alerts.
      # Upload errors still land in the journal.
      systemd.services.systemd-journal-upload = {
        serviceConfig = {
          Type = lib.mkForce "simple";
          ExecStart = [
            ""
            (pkgs.writeShellScript "journal-upload-loop" ''
              while true; do
                # No NOTIFY_SOCKET: on exit the uploader sends STOPPING=1,
                # which would make systemd tear the whole unit down.
                ${pkgs.coreutils}/bin/env -u NOTIFY_SOCKET \
                  ${config.systemd.package}/lib/systemd/systemd-journal-upload --save-state || true
                ${pkgs.coreutils}/bin/sleep 30
              done
            '')
          ];
          RestartSec = lib.mkForce "30s";
          # Upstream sets WatchdogSec=3min, kept alive by the uploader's
          # sd_notify pings, which the loop withholds (no NOTIFY_SOCKET).
          WatchdogSec = 0;
        };
        unitConfig.StartLimitIntervalSec = 0;
      };
    }

    # Certificate expiry, read from the certs on disk: acme_cert_not_after_seconds.
    (lib.mkIf (acmeCerts != [ ]) {
      systemd.services.acme-expiry-metrics = {
        description = "Export ACME certificate expiry for node_exporter";
        path = [
          pkgs.openssl
          pkgs.coreutils
        ];
        serviceConfig.Type = "oneshot";
        script = writeProm "acme" ''
          echo "# HELP acme_cert_not_after_seconds Expiry of the certificate on disk."
          echo "# TYPE acme_cert_not_after_seconds gauge"
          ${lib.concatMapStrings (domain: ''
            f=/var/lib/acme/${domain}/cert.pem
            if [ -f "$f" ]; then
              end=$(openssl x509 -noout -enddate -in "$f" | cut -d= -f2)
              echo "acme_cert_not_after_seconds{domain=\"${domain}\"} $(date -d "$end" +%s)"
            fi
          '') acmeCerts}
        '';
      };
      systemd.timers.acme-expiry-metrics = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "1h";
        };
      };
    })

    # Time of the last successful backup: restic_last_success_timestamp_seconds.
    # ExecStartPost only runs when every ExecStart (backup, prune, check) succeeded.
    {
      systemd.services = lib.genAttrs (map (n: "restic-backups-${n}") resticBackups) (unit: {
        serviceConfig.ExecStartPost = [
          (pkgs.writeShellScript "${unit}-metrics" (
            writeProm unit ''
              echo "# TYPE restic_last_success_timestamp_seconds gauge"
              echo "restic_last_success_timestamp_seconds{backup=\"${lib.removePrefix "restic-backups-" unit}\"} $(${pkgs.coreutils}/bin/date +%s)"
            ''
          ))
        ];
      });
    }
  ];
}
