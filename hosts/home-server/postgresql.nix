{
  services.postgresql = {
    enable = true;

    # NocoDB and Grist both run in podman containers (see ./nocodb.nix and
    # ./grist.nix) with the Postgres socket dir bind-mounted in. Peer auth can't
    # match — the container process's uid isn't `nocodb`/`grist` — so allow each
    # role trust access to its own db over the local socket. Scoped to that
    # role+db, local-only, no TCP, no password. User `authentication` lines are
    # matched before the module's defaults, so these specific rules win.
    authentication = ''
      local nocodb nocodb trust
      local grist grist trust
    '';

    ensureDatabases = [
      "nocodb"
      "grist"
    ];
    ensureUsers = [
      {
        name = "nocodb";
        ensureDBOwnership = true;
      }
      {
        name = "grist";
        ensureDBOwnership = true;
      }
    ];
  };
}
