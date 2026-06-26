{ ... }:
let
  # Where Authelia keeps its runtime state. systemd's StateDirectory creates
  # this as authelia-main:authelia-main 0700 on start.
  stateDir = "/var/lib/authelia-main";
in
{
  # Reusable nginx forward-auth wiring, consumed by any vhost that opts into
  # SSO (see slskd.nix / wrtag.nix). Exposed as a module arg so protected
  # modules just splice these in rather than re-deriving the snippets — see the
  # "How to protect a service" note at the bottom of this file.
  _module.args.authelia = {
    # Internal endpoint nginx queries to decide whether a request is authorized.
    # Splice into a vhost as `locations."/internal/authelia/authz" = ...`.
    authzLocation = {
      proxyPass = "http://127.0.0.1:9091/api/authz/auth-request";
      extraConfig = ''
        internal;
        proxy_set_header X-Original-Method $request_method;
        proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
        proxy_set_header Content-Length "";
        proxy_pass_request_body off;
      '';
    };

    # Guard for a protected location's extraConfig: require a passing
    # auth_request, forward the resolved identity upstream, and bounce
    # unauthenticated browsers to the portal.
    guard = ''
      auth_request /internal/authelia/authz;
      auth_request_set $user   $upstream_http_remote_user;
      auth_request_set $groups $upstream_http_remote_groups;
      proxy_set_header Remote-User   $user;
      proxy_set_header Remote-Groups $groups;
      error_page 401 =302 https://auth.agrshv.dev/?rd=$scheme://$http_host$request_uri;
    '';
  };

  # Authelia SSO / forward-auth portal, reachable at auth.agrshv.dev.
  #
  # Single instance, file-based user database, PostgreSQL storage backend and
  # Redis-backed sessions, one-factor auth. It protects nothing by itself — a
  # vhost opts in via the nginx auth_request wiring at the bottom of this file.
  #
  # ── One-time bootstrap on the server (before the first deploy) ──────────────
  # The three secret files and the user database must exist before Authelia
  # starts (preStart runs `validate-config`). Run on the host as root:
  #
  #   install -d -o authelia-main -g authelia-main -m 700 /var/lib/authelia-main
  #   for s in jwt-secret session-secret storage-encryption-key; do
  #     openssl rand -base64 64 > /var/lib/authelia-main/$s
  #   done
  #   # Create a user (interactive prompt for the password):
  #   HASH=$(authelia crypto hash generate argon2 --password 'CHANGEME' | sed 's/^Digest: //')
  #   cat > /var/lib/authelia-main/users.yml <<EOF
  #   users:
  #     d3spair:
  #       disabled: false
  #       displayname: "d3spair"
  #       password: "$HASH"
  #       email: d3spair@agrshv.dev
  #       groups: [admins]
  #   EOF
  #   chown -R authelia-main:authelia-main /var/lib/authelia-main
  #   chmod 600 /var/lib/authelia-main/{jwt-secret,session-secret,storage-encryption-key,users.yml}
  # ────────────────────────────────────────────────────────────────────────────
  #
  # ── OIDC provider bootstrap (for the identity_providers.oidc clients) ───────
  #   authelia crypto rand --length 64 > /var/lib/authelia-main/oidc-hmac-secret
  #   authelia crypto pair rsa generate --directory /tmp/oidc \
  #     && mv /tmp/oidc/private.pem /var/lib/authelia-main/oidc-issuer.pem
  #   # Per client: keep the plaintext for the relying party, put the HASH here.
  #   SECRET=$(authelia crypto rand --length 72 --charset rfc3986)
  #   echo "plaintext (give to the client): $SECRET"
  #   authelia crypto hash generate pbkdf2 --variant sha512 --password "$SECRET"
  #   chown authelia-main:authelia-main /var/lib/authelia-main/oidc-*
  #   chmod 600 /var/lib/authelia-main/oidc-*
  # ────────────────────────────────────────────────────────────────────────────
  services.authelia.instances.main = {
    enable = true;

    secrets = {
      jwtSecretFile = "${stateDir}/jwt-secret";
      sessionSecretFile = "${stateDir}/session-secret";
      storageEncryptionKeyFile = "${stateDir}/storage-encryption-key";
      # OIDC provider secrets (see the OIDC bootstrap note below). The module
      # turns the issuer private key into the JWKS config automatically.
      oidcHmacSecretFile = "${stateDir}/oidc-hmac-secret";
      oidcIssuerPrivateKeyFile = "${stateDir}/oidc-issuer.pem";
    };

    settings = {
      theme = "dark";
      server.address = "tcp://127.0.0.1:9091";
      log.level = "info";

      authentication_backend.file.path = "${stateDir}/users.yml";

      # ── OIDC provider ─────────────────────────────────────────────────────
      # Lets services delegate login to Authelia. Each client below trusts
      # Authelia for SSO. `client_secret` is the PBKDF2 hash of the plaintext
      # secret (the plaintext is configured on the relying party's side).
      identity_providers.oidc.clients = [
        {
          client_id = "forgejo";
          client_name = "Forgejo";
          client_secret = "$pbkdf2-sha512$310000$D4UjzihhYqjAirDA8JdSwQ$RibLaLsf9SKiJL8zRv8YgZm9J8b8cp0ZbnTB.LKRpuN6HYTi1LahJP9gnLnMPyPQSazWEE.CPw0EB4GGI7I42w";
          public = false;
          authorization_policy = "two_factor";
          # The last path segment ("authelia") must match the auth-source name
          # created in Forgejo (Site Admin → Authentication Sources).
          redirect_uris = [ "https://git.agrshv.dev/user/oauth2/Authelia/callback" ];
          scopes = [
            "openid"
            "email"
            "profile"
            "groups"
          ];
          token_endpoint_auth_method = "client_secret_basic";
        }
      ];

      access_control = {
        default_policy = "deny";
        # Rules are first-match-wins, so the narrow slskd rule must precede the
        # catch-all below. Only user d3spair may reach slskd; the subject list
        # is OR'd, so add e.g. "group:admins" here to widen access.
        rules = [
          {
            domain = "slskd.agrshv.dev";
            policy = "one_factor";
            subject = [
              "user:d3spair"
            ];
          }
          {
            domain = "*.agrshv.dev";
            policy = "one_factor";
          }
        ];
      };

      session.cookies = [
        {
          domain = "agrshv.dev";
          authelia_url = "https://auth.agrshv.dev";
        }
      ];

      # Persist sessions in Redis (over a unix socket; provisioned below) so
      # they survive Authelia restarts. sessionSecretFile encrypts this data.
      session.redis = {
        host = "/run/redis-authelia/redis.sock";
        port = 0;
      };

      regulation = {
        max_retries = 3;
        find_time = "2m";
        ban_time = "5m";
      };

      # PostgreSQL storage backend over the local socket (peer auth, role
      # authelia-main — provisioned below). Authelia creates its schema on
      # first start. If validation insists on a password, set one on the role
      # and pass environmentVariables.AUTHELIA_STORAGE_POSTGRES_PASSWORD_FILE.
      storage.postgres = {
        address = "unix:///run/postgresql";
        # DB name matches the role (peer auth maps OS user authelia-main -> role
        # authelia-main; ensureDBOwnership requires the db to share that name).
        database = "authelia-main";
        username = "authelia-main";
      };
      notifier.filesystem.filename = "${stateDir}/notification.txt";
    };
  };

  # Dedicated Redis for Authelia sessions (socket-only, no TCP). Runs as
  # user/group redis-authelia; authelia-main joins that group to read the
  # socket.
  services.redis.servers.authelia = {
    enable = true;
    port = 0;
    unixSocket = "/run/redis-authelia/redis.sock";
    unixSocketPerm = 660;
  };
  users.users.authelia-main.extraGroups = [ "redis-authelia" ];

  # Storage backend database, peer-authenticated over the local socket.
  services.postgresql = {
    ensureDatabases = [ "authelia-main" ];
    ensureUsers = [
      {
        name = "authelia-main";
        ensureDBOwnership = true;
      }
    ];
  };

  # Don't start Authelia before its datastores are up.
  systemd.services.authelia-main = {
    after = [
      "postgresql.service"
      "redis-authelia.service"
    ];
    wants = [
      "postgresql.service"
      "redis-authelia.service"
    ];
  };

  # The Authelia portal itself.
  services.nginx.virtualHosts."auth.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/" = {
      proxyPass = "http://127.0.0.1:9091";
      extraConfig = ''
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Uri $request_uri;
      '';
    };
  };

  # ── How to protect a service ────────────────────────────────────────────────
  # Take the `authelia` module arg (defined via _module.args at the top of this
  # file) and splice its two pieces into the vhost you want behind SSO:
  #
  #   { authelia, ... }:
  #   {
  #     services.nginx.virtualHosts."app.agrshv.dev" = {
  #       forceSSL = true;
  #       useACMEHost = "agrshv.dev";
  #       locations."/internal/authelia/authz" = authelia.authzLocation;
  #       locations."/" = {
  #         proxyPass = "http://127.0.0.1:PORT";
  #         extraConfig = authelia.guard;
  #       };
  #     };
  #   }
  #
  # When another module already defines the vhost's "/" proxyPass (e.g. the
  # slskd module), only add the guard: `locations."/".extraConfig = authelia.guard;`
  #
  # Note: don't gate services with mobile apps or API clients that can't follow
  # the redirect (e.g. Immich, Forgejo git/API) unless you add bypass rules.
}
