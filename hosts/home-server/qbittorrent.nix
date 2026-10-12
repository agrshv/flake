{
  config,
  lib,
  pkgs,
  ...
}:
let
  # qBittorrent keeps its WebUI password as a PBKDF2 hash in serverConfig, which
  # nixpkgs renders into a world-readable /nix/store file. Keep the hash in sops
  # instead: serverConfig carries a placeholder and an ExecStartPre swaps in the
  # real value. `mkAfter` is what puts that step *after* the module's own
  # install of the config file — a plain preStart runs before it and would be
  # overwritten (nixpkgs qbittorrent.nix:176).
  passwordPlaceholder = "QBITTORRENT_PASSWORD_PBKDF2_PLACEHOLDER";
  setPassword = pkgs.writeShellScript "qbittorrent-set-password" ''
    ${lib.getExe pkgs.replace-secret} '${passwordPlaceholder}' \
      ${config.sops.secrets."nixflix/qbittorrent/password_hash".path} \
      ${config.services.qbittorrent.profileDir}/qBittorrent/config/qBittorrent.conf
  '';
in
{
  sops.secrets."nixflix/qbittorrent/password_hash".restartUnits = [ "qbittorrent.service" ];

  # No VPN for now: it goes out over the home connection.
  services.qbittorrent = {
    enable = true;
    group = "media";
    webuiPort = 8282;
    serverConfig = {
      # Sonarr/Radarr set a category per download; with automatic torrent
      # management each lands in /data/torrents/<category>, next to the
      # library it gets hardlinked into (./arr.nix).
      BitTorrent.Session = {
        DefaultSavePath = "/data/torrents";
        DisableAutoTMMByDefault = false;
      };
      Preferences.WebUI = {
        Address = "127.0.0.1";
        Username = "agrshv";
        # Substituted at start-up from sops by setPassword above; the store
        # only ever sees this placeholder.
        Password_PBKDF2 = "@ByteArray(${passwordPlaceholder})";
        AlternativeUIEnabled = true;
        RootFolder = "${pkgs.vuetorrent}/share/vuetorrent";
      };
    };
  };

  systemd.services.qbittorrent.serviceConfig = {
    # Runs with `+` (full privileges) so the hash can stay 0400 root, and after
    # the upstream install step that would otherwise clobber the substitution.
    ExecStartPre = lib.mkAfter [ "+${setPassword}" ];
    UMask = "0002";
  };

  # LAN/NetBird only: in internalHosts in ./nginx.nix.
  services.nginx.virtualHosts."qbittorrent.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/".proxyPass = "http://127.0.0.1:${toString config.services.qbittorrent.webuiPort}";
  };
}
