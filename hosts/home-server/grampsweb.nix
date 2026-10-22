let
  # Pinned rather than :latest so an upgrade (which may migrate the tree or the
  # user db) only happens when this line changes.
  image = "ghcr.io/gramps-project/grampsweb:26.10.2";
  dataDir = "/var/lib/grampsweb";
  redisSocket = "/run/redis-grampsweb/redis.sock";

  # Shared by the web app and its Celery worker: the worker runs the same image
  # against the same tree, user db and media, and the two talk through Redis.
  common = {
    inherit image;
    autoStart = true;
    volumes = [
      "${dataDir}/users:/app/users" # user accounts (SQLite)
      "${dataDir}/grampsdb:/root/.gramps/grampsdb" # the family tree (SQLite)
      "${dataDir}/media:/app/media" # uploaded photos and documents
      "${dataDir}/secret:/app/secret" # Flask secret, generated on first start
      "${dataDir}/indexdir:/app/indexdir" # search index, rebuildable
      "${dataDir}/thumbnail_cache:/app/thumbnail_cache"
      "${dataDir}/cache:/app/cache" # request cache, reports, exports
      # Redis socket dir, so no TCP port or podman network is needed.
      "/run/redis-grampsweb:/run/redis-grampsweb"
    ];
    environment = {
      # Created on first start if no tree by that name exists yet.
      GRAMPSWEB_TREE = "Family";
      GRAMPSWEB_BASE_URL = "https://gramps.agrshv.dev";
      GRAMPSWEB_CELERY_CONFIG__broker_url = "redis+socket://${redisSocket}";
      GRAMPSWEB_CELERY_CONFIG__result_backend = "redis+socket://${redisSocket}";
    };
  };
in
{
  # Gramps Web — the web front end for a Gramps genealogy tree. Not in nixpkgs
  # (only desktop Gramps is), so it runs as the official image under podman
  # (enabled in ./forgejo-runner.nix), like ./nocodb.nix. Accounts are its own:
  # the first visit to the site creates the owner/admin account.
  virtualisation.oci-containers.containers = {
    grampsweb = common // {
      # Loopback only; nginx terminates TLS and applies the country gate.
      ports = [ "127.0.0.1:8086:5000" ];
    };
    # Imports, exports, reports and media processing run here, off the request
    # path.
    grampsweb-celery = common // {
      cmd = [
        "celery"
        "-A"
        "gramps_webapi.celery"
        "worker"
        "--loglevel=INFO"
        "--concurrency=2"
      ];
    };
  };

  # Celery broker and result backend. Socket-only like Authelia's; the
  # containers run as root (rootful podman), so they can open the 0660 socket.
  services.redis.servers.grampsweb = {
    enable = true;
    port = 0;
    unixSocket = redisSocket;
    unixSocketPerm = 660;
  };

  systemd.services =
    let
      afterRedis = {
        after = [ "redis-grampsweb.service" ];
        requires = [ "redis-grampsweb.service" ];
      };
    in
    {
      podman-grampsweb = afterRedis;
      podman-grampsweb-celery = afterRedis;
    };

  # podman refuses to bind-mount a host path that doesn't exist.
  systemd.tmpfiles.rules = map (d: "d ${dataDir}/${d} 0700 root root -") [
    ""
    "users"
    "grampsdb"
    "media"
    "secret"
    "indexdir"
    "thumbnail_cache"
    "cache"
  ];

  services.nginx.virtualHosts."gramps.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/" = {
      proxyPass = "http://127.0.0.1:8086";
      # Media uploads and GEDCOM / Gramps XML imports; nginx's 1 MB default
      # would reject most of them.
      extraConfig = ''
        client_max_body_size 500M;
      '';
    };
  };
}
