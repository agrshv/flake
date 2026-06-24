{
  # Self-hosted git forge (Gitea fork). Single-user instance reachable at
  # git.agrshv.dev over HTTPS, with git-over-SSH on the host's OpenSSH (port
  # 22). Forgejo runs as the `forgejo` user (login shell enabled by the module)
  # and writes forced-command entries into its own authorized_keys; the module
  # also adds `AcceptEnv GIT_PROTOCOL` to sshd. So clone URLs are
  # `forgejo@git.agrshv.dev:owner/repo.git`.
  services.forgejo = {
    enable = true;

    # Use the local PostgreSQL that's already running. createDatabase (default
    # true) provisions the `forgejo` role + db and authenticates over the unix
    # socket via peer auth — no password/secret to manage.
    database.type = "postgres";

    settings = {
      server = {
        DOMAIN = "git.agrshv.dev";
        ROOT_URL = "https://git.agrshv.dev/";
        # Behind nginx only. 3000 is taken by paperless's gotenberg sidecar.
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = 3001;
        # Use the host's OpenSSH on 22 (the module default: built-in server off,
        # SSH_PORT 22). Stated explicitly for clarity.
        SSH_PORT = 22;
      };
      service = {
        DISABLE_REGISTRATION = true;
        DISABLE_HTTP_GIT = true;
        REQUIRE_SIGNIN_VIEW = true;
      };
      repository = {
        FORCE_PRIVATE = true;
        DEFAULT_BRANCH = "master";
      };
    };
  };

  services.nginx.virtualHosts."git.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/".proxyPass = "http://127.0.0.1:3001";
  };
}
