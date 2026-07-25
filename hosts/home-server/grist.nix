{
  # Grist — open-source spreadsheet/database hybrid (Airtable-style). Run as a
  # podman OCI container (podman is enabled in ./forgejo-runner.nix): the
  # official image is the supported way to self-host it, matching how the other
  # containerised services here are deployed.
  #
  # Backed by the shared PostgreSQL in ./postgresql.nix. Rather than open a TCP
  # port, the host's Postgres socket dir (/run/postgresql) is bind-mounted into
  # the container and Grist connects over it. Grist uses TypeORM (node-postgres
  # under the hood); node-postgres treats a `host` that starts with `/` as a
  # socket directory and dials .../.s.PGSQL.5432, so TYPEORM_HOST points at the
  # socket dir instead of a hostname.
  #
  # Auth is `local grist grist trust` (see ./postgresql.nix): peer auth can't
  # match because the container process's uid isn't `grist`, and trust — scoped
  # to just this role+db over the local socket — keeps it secret-free, in line
  # with the other socket-authed services here. The `grist` role + db are
  # provisioned declaratively, so there's no manual bootstrap.
  #
  # Only Grist's home database (orgs/workspaces/users/ACLs) lives in Postgres.
  # The actual documents (one SQLite file per doc) plus attachments live on the
  # data volume at /persist.
  virtualisation.oci-containers = {
    backend = "podman";
    containers.grist = {
      image = "gristlabs/grist:latest";
      autoStart = true;
      # Loopback only; nginx terminates TLS and applies the country gate.
      ports = [ "127.0.0.1:8484:8484" ];
      volumes = [
        "/var/lib/grist:/persist"
        # Postgres socket, so Grist can talk to the shared instance without TCP.
        "/run/postgresql:/run/postgresql"
      ];
      environment = {
        APP_HOME_URL = "https://grist.agrshv.dev";
        PORT = "8484";
        # gvisor is bundled in the official image and is the safe default for
        # sandboxing untrusted formulas. If the sandbox fails to start under
        # podman, fall back to GRIST_SANDBOX_FLAVOR = "unsandboxed".
        GRIST_SANDBOX_FLAVOR = "gvisor";
        # Home database in the shared Postgres, over the bind-mounted socket.
        TYPEORM_TYPE = "postgres";
        TYPEORM_HOST = "/run/postgresql";
        TYPEORM_PORT = "5432";
        TYPEORM_DATABASE = "grist";
        TYPEORM_USERNAME = "grist";
        # To pin an admin account, set GRIST_DEFAULT_EMAIL here. To persist login
        # sessions across restarts, set GRIST_SESSION_SECRET via a sops secret
        # (see homepage.nix for the sops.templates env-file pattern); left unset,
        # Grist uses a built-in default and prints a warning at startup.
      };
    };
  };

  # The data volume's host path must exist before podman bind-mounts it,
  # otherwise the container fails with `statfs /var/lib/grist: no such file`.
  systemd.tmpfiles.rules = [
    "d /var/lib/grist 0700 root root -"
  ];

  # Don't start the container before the database (and its socket) exist.
  systemd.services.podman-grist = {
    after = [ "postgresql.service" ];
    wants = [ "postgresql.service" ];
  };

  services.nginx.virtualHosts."grist.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/" = {
      proxyPass = "http://127.0.0.1:8484";
      proxyWebsockets = true;
    };
  };
}
