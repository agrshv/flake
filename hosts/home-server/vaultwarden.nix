{ config, ... }:
{
  # Vaultwarden — Rust reimplementation of the Bitwarden server, compatible with
  # the official clients (browser extension, mobile, CLI). Deliberately NOT
  # behind Authelia forward-auth: the clients talk to /api and /identity
  # directly and can't follow an interactive login redirect, so the vault's own
  # authentication is the gate. The country gate in ./nginx.nix still applies.
  #
  # The /admin panel is unlocked by ADMIN_TOKEN, which comes from sops. Generate
  # the Argon2 PHC string vaultwarden expects with
  #   nix shell nixpkgs#vaultwarden -c vaultwarden hash
  # and store the result in secrets/home-server.yaml as `vaultwarden/env`:
  #   ADMIN_TOKEN='$argon2id$v=19$m=65540,t=3,p=4$...'
  # Drop the key entirely to disable the admin panel. SMTP_* can go in the same
  # file later to turn on invite / password-hint mail.
  sops.secrets."vaultwarden/env".restartUnits = [ "vaultwarden.service" ];

  services.vaultwarden = {
    enable = true;

    # Postgres instead of the default SQLite: the cluster is already captured by
    # pg_dumpall for restic (see ./restic.nix), so the vault lands in a
    # consistent backup without stopping the service. `configurePostgres`
    # provisions the role + database and points DATABASE_URL at the local
    # socket, the same shape as the other Postgres-backed services here.
    dbBackend = "postgresql";
    configurePostgres = true;

    # Sets DOMAIN. The module would also write its own nginx vhost via
    # `configureNginx`, but that one has no useACMEHost and would try to get a
    # separate certificate instead of using the agrshv.dev wildcard — so the
    # vhost is hand-rolled below like every other service on the box.
    domain = "vault.agrshv.dev";

    environmentFile = config.sops.secrets."vaultwarden/env".path;

    config = {
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
      # Invite-only. Create the first account from /admin, then flip
      # INVITATIONS_ALLOWED if you want existing users to invite others.
      SIGNUPS_ALLOWED = false;
      INVITATIONS_ALLOWED = false;
      # No SMTP wired up yet, so a hint would have nowhere to go.
      SHOW_PASSWORD_HINT = false;
    };
  };

  services.nginx.virtualHosts."vault.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    # Attachments and Sends go through the same vhost; the global 10m default
    # would reject anything larger with a 413.
    extraConfig = ''
      client_max_body_size 100m;
    '';
    locations = {
      "/".proxyPass = "http://127.0.0.1:8222";
      # Live sync between clients rides a websocket on these two paths.
      "= /notifications/hub" = {
        proxyPass = "http://127.0.0.1:8222";
        proxyWebsockets = true;
      };
      "= /notifications/anonymous-hub" = {
        proxyPass = "http://127.0.0.1:8222";
        proxyWebsockets = true;
      };
    };
  };
}
