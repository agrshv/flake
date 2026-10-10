{ pkgs, authelia, ... }:
{
  # dufs — browser uploads into Kavita's library (./kavita.nix), which has no
  # way to add books itself. Runs as kavita so uploaded files already have the
  # owner Kavita needs; its library watcher picks them up. No accounts or
  # database of its own: Authelia in front is the only gate. (Replaced File
  # Browser, archived upstream on 2026-09-01.) No NixOS module, hence the unit.
  systemd.services.dufs = {
    description = "dufs file server for the Kavita library";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      # 8080 is miniflux, 8083/8084 nocodb and romm.
      ExecStart = "${pkgs.dufs}/bin/dufs --bind 127.0.0.1 --port 8085 --allow-upload --allow-delete --allow-search /var/lib/kavita/library";
      User = "kavita";
      Group = "kavita";
      Restart = "on-failure";

      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/kavita/library" ];
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
      RestrictNamespaces = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
    };
  };

  # Behind Authelia forward-auth: browser-only, so the login redirect is fine
  # (unlike Kavita's OPDS/KOReader clients). Who may reach it is set in
  # ./authelia.nix.
  services.nginx.virtualHosts."files.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    # The global 10m default would reject bigger books with a 413.
    extraConfig = ''
      client_max_body_size 500m;
    '';
    locations."/internal/authelia/authz" = authelia.authzLocation;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8085";
      extraConfig = authelia.guard;
    };
  };
}
