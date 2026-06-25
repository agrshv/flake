{
  # Monica personal CRM. The module brings up MariaDB (createLocally, socket
  # auth) and a PHP-FPM pool, and builds its own nginx vhost — we only layer on
  # TLS + the wildcard ACME cert. Users sign in with Monica's own accounts, so
  # it isn't behind Authelia (it stays consistent with the other self-authed
  # apps; only the country gate in nginx.nix fronts it).
  #
  # ── One-time bootstrap on the server (before the first deploy) ──────────────
  # Monica needs a Laravel APP_KEY (32 random bytes, base64). The monica-setup
  # unit reads it as the unprivileged `monica` user (not root), so it must live
  # somewhere that user can read — NOT under /root (mode 0700). Kept inside the
  # dataDir: the key encrypts data in Monica's DB, so it's part of the same
  # backup/restore unit as the rest of Monica's state. Create it once on the
  # host as root, owned by monica:
  #
  #   head -c 32 /dev/urandom | base64 > /var/lib/monica/appkey
  #   chown monica:monica /var/lib/monica/appkey
  #   chmod 600 /var/lib/monica/appkey
  # ────────────────────────────────────────────────────────────────────────────
  services.monica = {
    enable = true;
    hostname = "monica.agrshv.dev";
    appKeyFile = "/var/lib/monica/appkey";
    # Set TLS here (rather than only on the merged vhost below) so the module
    # sees TLS is on and generates an https APP_URL and secure session cookies.
    nginx = {
      forceSSL = true;
      useACMEHost = "agrshv.dev";
    };
  };
}
