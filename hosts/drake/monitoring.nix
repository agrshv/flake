{
  config,
  lib,
  pkgs,
  ...
}:
let
  grafanaDir = config.services.grafana.dataDir;

  homeServerJobs = [
    {
      name = "smartctl";
      port = 9633;
    }
    {
      name = "postgres";
      port = 9187;
    }
    {
      name = "blocky";
      port = 9110;
    }
  ];
  drakeJobs = [
    {
      name = "vmalert";
      port = 8880;
    }
    {
      name = "alertmanager";
      port = 9093;
    }
    {
      name = "grafana";
      port = 3000;
    }
  ];

  # Node Exporter Full (grafana.com/grafana/dashboards/1860). Its datasource is
  # a template variable, so it picks up the provisioned VictoriaMetrics one.
  dashboards = pkgs.linkFarm "grafana-dashboards" [
    {
      name = "node-exporter-full.json";
      path = pkgs.fetchurl {
        url = "https://grafana.com/api/dashboards/1860/revisions/46/download";
        hash = "sha256-5Y3cXcU11MkB+U2pZIvD49Wue2946Y4YW86LKJlhzqM=";
      };
    }
  ];
in
{
  # Monitoring for both hosts, kept off home-server so it still reports when
  # home-server is the thing that's down.
  #
  #   node_exporter (both hosts) ──scrape──> VictoriaMetrics ──> vmalert ──> Alertmanager ──> ntfy
  #   journald      (both hosts) ──upload──> VictoriaLogs
  #   Grafana reads both.
  #
  # Grafana: https://grafana.agrshv.dev, through nginx (./nginx.nix) and
  # Authelia on home-server, NetBird peers only. The name exists only in
  # NetBird's agrshv.dev zone (CNAME to drake.netbird.cloud), not in public DNS.
  # Break-glass when home-server (and so Authelia) is down:
  #   ssh -L 3000:127.0.0.1:3000 drake  → http://localhost:3000, user admin,
  #   password from `ssh drake sudo cat /var/lib/grafana/admin-password`.
  # Unit failures still alert directly through ../common/ntfy-alerts.nix; this
  # adds history, search and the alerts that need it (expiry, staleness, disk).

  monitoring.victoriaLogsUrl = "http://127.0.0.1:9428";

  services.victoriametrics = {
    enable = true;
    listenAddress = "127.0.0.1:8428";
    retentionPeriod = "180d";
    prometheusConfig = {
      global.scrape_interval = "30s";
      scrape_configs = [
        {
          job_name = "node";
          static_configs = [
            {
              targets = [ "127.0.0.1:9100" ];
              labels.host = "drake";
            }
            {
              targets = [ "home-server.netbird.cloud:9100" ];
              labels.host = "home-server";
            }
          ];
        }
        {
          job_name = "victoria";
          static_configs = [
            {
              targets = [
                "127.0.0.1:8428"
                "127.0.0.1:9428"
              ];
            }
          ];
        }
      ]
      # Service exporters on home-server (../home-server/metrics.nix).
      ++ map (job: {
        job_name = job.name;
        static_configs = [
          {
            targets = [ "home-server.netbird.cloud:${toString job.port}" ];
            labels.host = "home-server";
          }
        ];
      }) homeServerJobs
      # The alerting path itself, so a broken link shows up as up == 0.
      ++ map (job: {
        job_name = job.name;
        static_configs = [
          {
            targets = [ "127.0.0.1:${toString job.port}" ];
            labels.host = "drake";
          }
        ];
      }) drakeJobs;
    };
  };

  services.victorialogs = {
    enable = true;
    # home-server uploads its journal over NetBird; the firewall below keeps
    # this off the public interface.
    listenAddress = ":9428";
    extraOptions = [ "-retentionPeriod=30d" ];
  };

  services.vmalert.instances.default = {
    enable = true;
    settings = {
      "datasource.url" = "http://127.0.0.1:8428";
      "notifier.url" = [ "http://127.0.0.1:9093" ];
      "httpListenAddr" = "127.0.0.1:8880";
    };
    rules.groups = [
      {
        name = "hosts";
        rules = [
          {
            alert = "HostDown";
            expr = ''up{job="node"} == 0'';
            for = "5m";
            annotations.summary = "{{ $labels.host }} has not answered a scrape for 5 minutes";
          }
          {
            alert = "DiskAlmostFull";
            expr = ''
              1 - node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|overlay|squashfs|vfat"}
                / node_filesystem_size_bytes{fstype!~"tmpfs|ramfs|overlay|squashfs|vfat"} > 0.85
            '';
            for = "30m";
            annotations.summary = "{{ $labels.host }}: {{ $labels.mountpoint }} is {{ $value | humanizePercentage }} full";
          }
          {
            alert = "CertExpiringSoon";
            expr = "acme_cert_not_after_seconds - time() < 14 * 86400";
            annotations.summary = "{{ $labels.domain }} on {{ $labels.host }} expires in {{ $value | humanizeDuration }}; check acme-order-renew-{{ $labels.domain }}";
          }
          {
            # Backups run nightly at 03:00 (+15 min jitter); allow a missed night's slack.
            alert = "BackupStale";
            expr = "time() - restic_last_success_timestamp_seconds > 30 * 3600";
            annotations.summary = "Last successful restic backup {{ $labels.backup }} was {{ $value | humanizeDuration }} ago";
          }
          {
            # Hosts have HostDown; this covers the service exporters.
            alert = "TargetDown";
            expr = ''up{job!="node"} == 0'';
            for = "10m";
            annotations.summary = "{{ $labels.job }} on {{ $labels.host }} has not answered a scrape for 10 minutes";
          }
        ];
      }
      {
        name = "services";
        rules = [
          {
            alert = "PostgresDown";
            expr = "pg_up == 0";
            for = "5m";
            annotations.summary = "Postgres on {{ $labels.host }} is down: Immich, Paperless, Authelia, Forgejo and the *arr apps depend on it";
          }
          {
            alert = "DiskSmartFailing";
            expr = "smartctl_device_smart_status != 1";
            annotations.summary = "{{ $labels.device }} on {{ $labels.host }} reports SMART failure: replace it, check the last backup";
          }
          {
            alert = "DiskWearHigh";
            expr = "smartctl_device_percentage_used > 80";
            annotations.summary = "{{ $labels.device }} on {{ $labels.host }} has used {{ $value }}% of its rated endurance";
          }
          {
            alert = "DiskReallocatedSectors";
            expr = ''smartctl_device_attribute{attribute_name="Reallocated_Sector_Ct",attribute_value_type="raw"} > 0'';
            annotations.summary = "{{ $labels.device }} on {{ $labels.host }} has {{ $value }} reallocated sectors";
          }
        ];
      }
    ];
  };

  # vmalert only speaks the Alertmanager API; Alertmanager hands alerts to ntfy,
  # whose built-in "alertmanager" template turns the webhook JSON into a
  # readable message. Same topic and token as the unit-failure alerts.
  services.prometheus.alertmanager = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9093;
    # Provides NTFY_TOKEN, substituted into the config below with envsubst.
    environmentFile = config.sops.secrets."ntfy/env".path;
    # Single instance: no HA gossip listener on *:9094.
    extraFlags = [ "--cluster.listen-address=" ];
    configuration = {
      route = {
        receiver = "ntfy";
        group_by = [
          "alertname"
          "host"
        ];
        group_wait = "30s";
        group_interval = "5m";
        repeat_interval = "12h";
      };
      receivers = [
        {
          name = "ntfy";
          webhook_configs = [
            {
              url = "http://127.0.0.1:2586/alerts?template=alertmanager&priority=high&tags=chart_with_upwards_trend";
              send_resolved = true;
              http_config.authorization.credentials = "$NTFY_TOKEN";
            }
          ];
        }
      ];
    };
  };

  # Alerts travel vmalert -> Alertmanager -> ntfy, so a break there would be
  # silent. Check it from outside that path: a failing check fails this unit,
  # and ../common/ntfy-alerts.nix posts unit failures to ntfy directly.
  systemd.services.alert-path-check = {
    description = "Check that vmalert and Alertmanager can deliver alerts";
    after = [ "victoriametrics.service" ];
    path = [
      pkgs.curl
      pkgs.jq
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      q() {
        curl -fsS -m 10 http://127.0.0.1:8428/api/v1/query --data-urlencode "query=$1" \
          | jq -r '.data.result[0].value[1] // "missing"'
      }
      up=$(q 'min(up{job=~"vmalert|alertmanager"})')
      failed=$(q 'sum(increase(alertmanager_notifications_failed_total[30m]))')
      echo "vmalert/alertmanager up: $up, failed notifications (30m): $failed"
      [ "$up" = 1 ] || { echo "vmalert or Alertmanager is not being scraped as up"; exit 1; }
      [ "$failed" = missing ] || [ "''${failed%%.*}" = 0 ] || { echo "Alertmanager failed to deliver $failed notifications"; exit 1; }
    '';
  };
  systemd.timers.alert-path-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Relative to the timer starting, not boot: on a deploy OnBootSec has
      # long passed and would fire inside the switch, before the new scrape
      # targets exist, failing the switch (and deploy-rs rolls back).
      OnActiveSec = "15min";
      OnUnitActiveSec = "15min";
    };
  };

  services.grafana = {
    enable = true;
    declarativePlugins = [ pkgs.grafanaPlugins.victoriametrics-logs-datasource ];
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        domain = "grafana.agrshv.dev";
        root_url = "https://grafana.agrshv.dev/";
      };
      security = {
        admin_user = "admin";
        admin_password = "$__file{${grafanaDir}/admin-password}";
        secret_key = "$__file{${grafanaDir}/secret-key}";
      };
      # Authelia identifies the user; nginx passes it as Remote-User. Only
      # nginx on loopback may set it (Grafana listens on loopback only). A
      # request without the header (the break-glass tunnel) gets the normal
      # login form.
      "auth.proxy" = {
        enabled = true;
        header_name = "Remote-User";
        header_property = "username";
        auto_sign_up = true;
        whitelist = "127.0.0.1";
        headers = "Groups:Remote-Groups";
      };
      # Authelia only lets group admins through (see its access_control on
      # home-server), so everyone signed up this way is an admin.
      users.auto_assign_org_role = "Admin";
      analytics = {
        reporting_enabled = false;
        check_for_updates = false;
      };
    };
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "VictoriaMetrics";
          uid = "victoriametrics";
          type = "prometheus";
          url = "http://127.0.0.1:8428";
          isDefault = true;
        }
        {
          name = "VictoriaLogs";
          uid = "victorialogs";
          type = "victoriametrics-logs-datasource";
          url = "http://127.0.0.1:9428";
        }
      ];
      dashboards.settings.providers = [
        {
          name = "default";
          options.path = dashboards;
        }
      ];
    };
  };

  # Generated once and kept in Grafana's state dir instead of sops: nothing
  # outside Grafana needs them, and losing them only means a new password.
  systemd.services.grafana.preStart = lib.mkBefore ''
    umask 077
    for f in admin-password secret-key; do
      if [ ! -s ${grafanaDir}/$f ]; then
        ${pkgs.openssl}/bin/openssl rand -base64 33 | tr -d '\n/+=' > ${grafanaDir}/$f
      fi
    done
  '';

  # VictoriaLogs ingest from home-server.
  networking.firewall.interfaces.wt0.allowedTCPPorts = [ 9428 ];

  security.acme.certs."grafana.agrshv.dev".reloadServices = [ "nginx.service" ];
  sops.secrets."acme/env".restartUnits = [ "acme-grafana.agrshv.dev.service" ];

  services.nginx.virtualHosts."grafana.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "grafana.agrshv.dev";
    extraConfig = ''
      # NetBird peers only (the address comes from the SNI router's PROXY header).
      allow 100.78.0.0/16;
      deny all;
    '';
    # Forward-auth against Authelia on home-server, over NetBird. By address,
    # not name: nginx resolves proxy_pass hosts once at startup, and NetBird's
    # resolver may not be up yet at boot. home-server's nginx admits the
    # overlay range through its country gate.
    locations."/internal/authelia/authz" = {
      proxyPass = "https://100.78.44.236/api/authz/auth-request";
      recommendedProxySettings = false;
      extraConfig = ''
        internal;
        proxy_ssl_server_name on;
        proxy_ssl_verify on;
        # The default depth of 1 rejects Let's Encrypt's leaf -> intermediate -> root.
        proxy_ssl_verify_depth 2;
        proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;
        proxy_ssl_name auth.agrshv.dev;
        proxy_set_header Host auth.agrshv.dev;
        proxy_set_header Cookie $http_cookie;
        proxy_set_header X-Original-Method $request_method;
        proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Content-Length "";
        proxy_pass_request_body off;
      '';
    };
    locations."/" = {
      proxyPass = "http://127.0.0.1:3000";
      proxyWebsockets = true; # Grafana Live
      extraConfig = ''
        auth_request /internal/authelia/authz;
        auth_request_set $user   $upstream_http_remote_user;
        auth_request_set $groups $upstream_http_remote_groups;
        proxy_set_header Remote-User   $user;
        proxy_set_header Remote-Groups $groups;
        error_page 401 =302 https://auth.agrshv.dev/?rd=$scheme://$http_host$request_uri;
      '';
    };
  };
}
