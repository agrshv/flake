{ pkgs, ... }:
let
  # config.json is only a bootstrap pointer at the RocksDB — every real
  # setting (accounts, listeners, ACME certs, DKIM keys) lives in the DB
  # itself, so the file can be a read-only store path. The container never
  # writes it.
  #
  # 1.0 can't open a 0.16 store: stalwart-migrate copied /var/lib/stalwart
  # (0.16.27, kept read-only as the rollback source) into this new one.
  dataDir = "/var/lib/stalwart-v1";
  bootstrapConfig = pkgs.writeText "stalwart-config.json" ''
    {
      "@type": "RocksDb",
      "path": "${dataDir}"
    }
  '';
in
{
  # Carried over from the AlmaLinux quadlet: digest-pinned image, host
  # networking, data mounted at the same path as on the host (stalwart-migrate
  # expects that). Bump the pin deliberately — minor releases may migrate the
  # store. Migrating to the native services.stalwart-mail module is a separate
  # step.
  virtualisation.oci-containers = {
    backend = "podman";
    containers.stalwart = {
      image = "docker.io/stalwartlabs/stalwart:v1.0.2-alpine@sha256:a8b055bcc655cc69a335319eb178ae9c600f62c1faa8b506cb5b69cdccf656f3";
      volumes = [
        "${dataDir}:${dataDir}"
        "${bootstrapConfig}:/etc/stalwart/config.json"
      ];
      environment = {
        TZ = "Asia/Almaty";
        STALWART_PUBLIC_URL = "https://mail.agrshv.dev";
      };
      extraOptions = [ "--network=host" ];
    };
  };

  # An empty or missing store would boot 1.0 into bootstrap mode — a fresh,
  # accountless server answering on :25. Refuse to start instead.
  systemd.services.podman-stalwart.unitConfig.ConditionPathExists = "${dataDir}/CURRENT";

  # SMTP, submissions, submission, IMAPS, sieve. HTTPS (JMAP/web-admin) is
  # reached through nginx's SNI router on :443 (./nginx.nix), which forwards
  # to Stalwart's https listener on 127.0.0.1:10443. POP3 (110/995) and the
  # plain-HTTP 8080 stay closed; the OCI security list gates these again upstream.
  networking.firewall.allowedTCPPorts = [
    25
    465
    587
    993
    4190
  ];
}
