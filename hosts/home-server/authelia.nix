{ config, ... }:
let
  # Where Authelia keeps its runtime state. systemd's StateDirectory creates
  # this as authelia-main:authelia-main 0700 on start.
  stateDir = "/var/lib/authelia-main";
in
{
  # Authelia SSO / forward-auth portal, reachable at auth.agrshv.dev.
  #
  # Single instance, file-based user database, local SQLite storage, one-factor
  # auth. It protects nothing by itself — a vhost opts in via the nginx
  # auth_request wiring at the bottom of this file.
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
  services.authelia.instances.main = {
    enable = true;

    secrets = {
      jwtSecretFile = "${stateDir}/jwt-secret";
      sessionSecretFile = "${stateDir}/session-secret";
      storageEncryptionKeyFile = "${stateDir}/storage-encryption-key";
    };

    settings = {
      theme = "dark";
      server.address = "tcp://127.0.0.1:9091";
      log.level = "info";

      authentication_backend.file.path = "${stateDir}/users.yml";

      access_control = {
        default_policy = "deny";
        rules = [
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

      regulation = {
        max_retries = 3;
        find_time = "2m";
        ban_time = "5m";
      };

      storage.local.path = "${stateDir}/db.sqlite3";
      notifier.filesystem.filename = "${stateDir}/notification.txt";
    };
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
  # Add the auth_request endpoint + guard to any vhost you want behind SSO.
  # Reusable snippets, then an example applied to a (commented) vhost.
  #
  #   # internal endpoint that asks Authelia whether the request is allowed
  #   locations."/internal/authelia/authz" = {
  #     proxyPass = "http://127.0.0.1:9091/api/authz/auth-request";
  #     extraConfig = ''
  #       internal;
  #       proxy_set_header X-Original-Method $request_method;
  #       proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
  #       proxy_set_header Content-Length "";
  #       proxy_pass_request_body off;
  #     '';
  #   };
  #   # guard placed in the protected location's extraConfig:
  #   locations."/" = {
  #     proxyPass = "http://127.0.0.1:PORT";
  #     extraConfig = ''
  #       auth_request /internal/authelia/authz;
  #       auth_request_set $user  $upstream_http_remote_user;
  #       auth_request_set $groups $upstream_http_remote_groups;
  #       proxy_set_header Remote-User  $user;
  #       proxy_set_header Remote-Groups $groups;
  #       error_page 401 =302 https://auth.agrshv.dev/?rd=$scheme://$http_host$request_uri;
  #     '';
  #   };
  #
  # Note: don't gate services with mobile apps or API clients that can't follow
  # the redirect (e.g. Immich, Forgejo git/API) unless you add bypass rules.
}
