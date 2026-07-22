{
  services.postgresql = {
    enable = true;

    # NocoDB runs in a podman container (see ./nocodb.nix) with the Postgres
    # socket dir bind-mounted in. Peer auth can't match — the container process's
    # uid isn't `nocodb` — so allow the nocodb role trust access to its own db
    # over the local socket. Scoped to that role+db, local-only, no TCP, no
    # password. User `authentication` lines are matched before the module's
    # defaults, so this specific rule wins for nocodb.
    authentication = ''
      local nocodb nocodb trust
    '';

    ensureDatabases = [ "nocodb" ];
    ensureUsers = [
      {
        name = "nocodb";
        ensureDBOwnership = true;
      }
    ];
  };
}
