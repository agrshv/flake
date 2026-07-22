{
  # NocoDB — Airtable-style no-code database / smart-spreadsheet UI. Run as a
  # podman OCI container (podman is enabled in ./forgejo-runner.nix): the
  # upstream NixOS module in nocodb's own flake is unmaintained, and the official
  # image is the supported way to run it.
  #
  # Backed by the shared PostgreSQL in ./postgresql.nix. Rather than open a TCP
  # port, the host's Postgres socket dir (/run/postgresql) is bind-mounted into
  # the container and NocoDB connects over it. NC_DB's pg://… URL can't express a
  # socket path, so we use NC_DB_JSON (a Knex connection config) with `host` set
  # to the socket directory — node-postgres then dials .../.s.PGSQL.5432.
  #
  # Auth is `local nocodb nocodb trust` (see ./postgresql.nix): peer auth can't
  # match because the container process's uid isn't `nocodb`, and trust — scoped
  # to just this role+db over the local socket — keeps it secret-free, in line
  # with the other socket-authed services here. The `nocodb` role + db are
  # provisioned declaratively, so there's no manual bootstrap.
  #
  # The data volume still holds NocoDB's attachments and local files; only the
  # metadata/app tables live in Postgres.
  virtualisation.oci-containers = {
    backend = "podman";
    containers.nocodb = {
      image = "nocodb/nocodb:latest";
      autoStart = true;
      # Loopback only; nginx terminates TLS and applies the country gate.
      ports = [ "127.0.0.1:8083:8080" ];
      volumes = [
        "/var/lib/nocodb:/usr/app/data"
        # Postgres socket, so NocoDB can talk to the shared instance without TCP.
        "/run/postgresql:/run/postgresql"
      ];
      environment = {
        NC_PUBLIC_URL = "https://nocodb.agrshv.dev";
        NC_DB_JSON = builtins.toJSON {
          client = "pg";
          connection = {
            host = "/run/postgresql";
            port = 5432;
            user = "nocodb";
            database = "nocodb";
          };
        };
      };
    };
  };

  # Don't start the container before the database (and its socket) exist.
  systemd.services.podman-nocodb = {
    after = [ "postgresql.service" ];
    wants = [ "postgresql.service" ];
  };

  services.nginx.virtualHosts."nocodb.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/" = {
      proxyPass = "http://127.0.0.1:8083";
      proxyWebsockets = true;
    };
  };
}
