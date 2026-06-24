{
  # CrowdSec security engine + firewall bouncer.
  #
  # The engine parses logs (sshd via journald, nginx access logs from file),
  # detects abuse with the hub scenarios, and writes ban decisions into its
  # embedded Local API (LAPI). The firewall-bouncer polls the LAPI and drops
  # banned IPs at the host firewall (iptables, since nftables isn't enabled).
  #
  # Credentials are bootstrapped automatically on first start:
  #   - `cscli machine add --auto` writes local_api_credentials.yaml
  #   - `cscli capi register`      writes online_api_credentials.yaml (enrols in
  #                                the community blocklist / CTI pull)
  #   - the bouncer self-registers via registerBouncer (default: on when the
  #     engine is enabled), so no API key has to be managed by hand.
  #
  # Inspect with `cscli` on the host: `cscli metrics`, `cscli decisions list`,
  # `cscli alerts list`, `cscli bouncers list`.
  services.crowdsec = {
    enable = true;

    settings = {
      # Run the embedded Local API. Required for machine/bouncer registration
      # and for the bouncer to fetch decisions. Listens on 127.0.0.1:8080.
      general.api.server.enable = true;
      lapi.credentialsFile = "/var/lib/crowdsec/local_api_credentials.yaml";
      # Enrol with the Central API for the community blocklist.
      capi.credentialsFile = "/var/lib/crowdsec/online_api_credentials.yaml";
    };

    # Collections bundle the parsers + scenarios for each data source.
    hub.collections = [
      "crowdsecurity/linux"
      "crowdsecurity/sshd"
      "crowdsecurity/nginx"
    ];

    localConfig.acquisitions = [
      {
        source = "journalctl";
        journalctl_filter = [ "_SYSTEMD_UNIT=sshd.service" ];
        labels.type = "syslog";
      }
      {
        source = "file";
        filenames = [ "/var/log/nginx/access.log" ];
        labels.type = "nginx";
      }
    ];
  };

  # The engine runs as the `crowdsec` user; nginx writes its access log 0640
  # nginx:nginx, so grant read access via the nginx group.
  users.users.crowdsec.extraGroups = [ "nginx" ];

  # Ban enforcement: polls the LAPI and drops decisions at the firewall.
  services.crowdsec-firewall-bouncer.enable = true;
}
