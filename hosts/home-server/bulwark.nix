{
  # Bulwark — modern JMAP webmail client (mail/calendar/contacts/files) for a
  # Stalwart Mail Server. Run as a podman OCI container (podman is enabled in
  # ./forgejo-runner.nix), matching how the other containerised services here are
  # deployed. Served at webmail.agrshv.dev, behind nginx + the KZ GeoIP gate.
  #
  # Bulwark is a stateless front-end: it holds no mailbox data of its own but
  # talks JMAP to the mail server. JMAP_SERVER_URL points at our Stalwart at
  # mail.agrshv.dev — Bulwark probes its JMAP session resource
  # (https://mail.agrshv.dev/.well-known/jmap) and proxies the browser's
  # authenticated JMAP calls through to it. The container listens on 3000; we map
  # it to loopback 3456 (host :3000/:3002 are already taken) and let nginx
  # terminate TLS.
  #
  # SESSION_SECRET encrypts session cookies / stored credentials and MUST be
  # stable across restarts (a changing secret invalidates every login). It's
  # supplied out-of-band via /root/bulwark.env — the same host-file pattern used
  # by slskd here — rather than being committed. Create it once on the host:
  #   echo "SESSION_SECRET=$(openssl rand -base64 32)" > /root/bulwark.env
  #   chmod 600 /root/bulwark.env
  # (or move it into sops via the sops.templates env-file pattern noted in
  # ./homepage.nix if you'd rather keep it in the repo).
  #
  # First launch: with JMAP_SERVER_URL preset, Bulwark still runs a one-time
  # web setup wizard (server probe, auth mode, admin account). Visit
  # https://webmail.agrshv.dev and complete it; the wizard writes config + an
  # admin password hash into the /app/data/admin volume below.
  virtualisation.oci-containers = {
    backend = "podman";
    containers.bulwark = {
      image = "ghcr.io/bulwarkmail/webmail:latest";
      autoStart = true;
      # Loopback only; nginx terminates TLS and applies the country gate.
      ports = [ "127.0.0.1:3456:3000" ];
      environment = {
        HOSTNAME = "0.0.0.0";
        PORT = "3000";
        # Our Stalwart mailserver — Bulwark discovers JMAP at /.well-known/jmap.
        JMAP_SERVER_URL = "https://mail.agrshv.dev";
      };
      # SESSION_SECRET (and any other secrets) live here, off the repo.
      environmentFiles = [ "/root/bulwark.env" ];
      volumes = [
        # Admin config: config.json, policy.json, admin.json (passwordHash),
        # themes, branding uploads — written by the first-launch wizard.
        "/var/lib/bulwark/admin:/app/data/admin"
        # Admin runtime state: login timestamps, audit.log, setup token.
        "/var/lib/bulwark/admin-state:/app/data/admin-state"
        # Encrypted per-user settings (only used if settings sync is enabled).
        "/var/lib/bulwark/settings:/app/data/settings"
      ];
    };
  };

  # The bind-mount host paths must exist before podman starts the container,
  # otherwise it fails with `statfs ...: no such file`. The image runs as the
  # non-root `nextjs` user (uid/gid 1001); these are rootful podman containers
  # with no userns remap, so uid 1001 in the container is uid 1001 on the host —
  # own the dirs by it or Bulwark hits EACCES writing its registries/config.
  systemd.tmpfiles.rules = [
    "d /var/lib/bulwark             0750 1001 1001 -"
    "d /var/lib/bulwark/admin       0750 1001 1001 -"
    "d /var/lib/bulwark/admin-state 0750 1001 1001 -"
    "d /var/lib/bulwark/settings    0750 1001 1001 -"
  ];

  services.nginx.virtualHosts."webmail.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/" = {
      proxyPass = "http://127.0.0.1:3456";
      proxyWebsockets = true;
    };
  };
}
