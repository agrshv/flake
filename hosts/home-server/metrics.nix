{ config, ... }:
let
  # Blocky's HTTP port also serves its control API (e.g. disabling blocking),
  # so peers get /metrics only, through nginx.
  blockyMetricsPort = 9110;
in
{
  # Service metrics for VictoriaMetrics on drake (../drake/monitoring.nix),
  # which scrapes them over NetBird. node_exporter itself comes from
  # ../common/monitoring-agent.nix.

  # SSD health. Everything lives on one SATA SSD, so wear and reallocated
  # sectors are the early warning before the box dies.
  services.prometheus.exporters.smartctl.enable = true;

  # Postgres backs Immich, Paperless, Authelia, Forgejo, NocoDB and the *arr
  # stack. Peer auth as the postgres superuser over the local socket.
  services.prometheus.exporters.postgres = {
    enable = true;
    runAsLocalSuperUser = true;
  };

  services.blocky.settings.prometheus.enable = true;
  services.nginx.virtualHosts."blocky-metrics" = {
    listen = [
      {
        addr = "0.0.0.0";
        port = blockyMetricsPort;
      }
    ];
    locations."= /metrics".proxyPass = "http://${config.services.blocky.settings.ports.http}/metrics";
    locations."/".return = "404";
  };

  networking.firewall.interfaces.wt0.allowedTCPPorts = [
    config.services.prometheus.exporters.smartctl.port
    config.services.prometheus.exporters.postgres.port
    blockyMetricsPort
  ];

  # Paperless' Gotenberg pushes OpenTelemetry metrics to an OTLP collector on
  # localhost:4318 by default and logs a failure every minute without one.
  systemd.services.gotenberg.environment = {
    OTEL_METRICS_EXPORTER = "none";
    OTEL_TRACES_EXPORTER = "none";
    OTEL_LOGS_EXPORTER = "none";
  };
}
