{
  # Dawarich — self-hosted Google Location History / Timeline replacement. The
  # module provisions its own PostgreSQL database (with the PostGIS extension,
  # which composes with immich's pgvector/vectorchord on the shared instance),
  # a dedicated Redis, the Sidekiq job workers and the Rails web service, and
  # builds the nginx vhost — we only add TLS + the wildcard ACME cert.
  #
  # NOT behind Authelia on purpose: the companion mobile apps (Overland /
  # OwnTracks / GPSLogger) push location points to Dawarich's HTTP API and can't
  # follow a forward-auth login redirect. Access is gated by Dawarich's own
  # accounts + per-user API keys (plus the country gate in nginx.nix).
  #
  # No manual secrets: secret_key_base is generated on first start under
  # /var/lib/dawarich/secrets, and the DB uses local socket (peer) auth.
  services.dawarich = {
    enable = true;
    localDomain = "dawarich.agrshv.dev";
    # Default webPort is 3000, which collides with paperless's gotenberg sidecar
    # (also binds 127.0.0.1:3000). 3001 is forgejo; use 3002.
    webPort = 3002;
    # nginx terminates TLS; tell Dawarich to emit https URLs (default is http).
    environment.APPLICATION_PROTOCOL = "https";
  };

  services.nginx.virtualHosts."dawarich.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
  };
}
