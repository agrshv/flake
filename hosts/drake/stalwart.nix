{ pkgs, ... }:
let
  # Stalwart 0.16's config.json is only a bootstrap pointer at the RocksDB —
  # every real setting (accounts, listeners, ACME certs, DKIM keys) lives in
  # the DB itself, so the file can be a read-only store path. The container
  # never writes it.
  bootstrapConfig = pkgs.writeText "stalwart-config.json" ''
    {
      "@type": "RocksDb",
      "path": "/var/lib/stalwart"
    }
  '';
in
{
  # Carried over verbatim from the AlmaLinux quadlet: same digest-pinned image
  # (the DB was last written by v0.16.19 — bump the pin deliberately, stalwart
  # migrates the store on upgrade), same host networking and data mount.
  # Migrating to the native services.stalwart-mail module is a separate step.
  virtualisation.oci-containers = {
    backend = "podman";
    containers.stalwart = {
      image = "docker.io/stalwartlabs/stalwart:v0.16.19-alpine@sha256:36796c685f491d4af82b8a2d4eeaf16208661de8a92dc69311c82c0837d3b1fd";
      volumes = [
        "/var/lib/stalwart:/var/lib/stalwart"
        "${bootstrapConfig}:/etc/stalwart/config.json"
      ];
      environment = {
        TZ = "Asia/Almaty";
        STALWART_PUBLIC_URL = "https://mail.agrshv.dev";
      };
      extraOptions = [ "--network=host" ];
    };
  };

  # Mail going down is the one failure worth waking up for (see ./ntfy.nix).
  systemd.services.podman-stalwart.onFailure = [ "ntfy-alert@podman-stalwart.service" ];

  # SMTP, HTTPS (JMAP/web-admin/ACME), submissions, submission, IMAPS, sieve.
  # POP3 (110/995) and the plain-HTTP 8080 stay closed; the OCI security list
  # gates these again upstream.
  networking.firewall.allowedTCPPorts = [
    25
    443
    465
    587
    993
    4190
  ];
}
