{
  config,
  lib,
  pkgs,
  ...
}:
let
  # qBittorrent keeps its WebUI password as a PBKDF2 hash in serverConfig, which
  # nixpkgs renders into a world-readable /nix/store file. Instead serverConfig
  # carries a placeholder, and an ExecStartPre hashes the plaintext password
  # from sops (fresh salt each start, qBittorrent's own PBKDF2-SHA512 scheme)
  # and swaps it in. `mkAfter` is what puts that step *after* the module's own
  # install of the config file — a plain preStart runs before it and would be
  # overwritten (nixpkgs qbittorrent.nix:176). Python reads the password from
  # the file, so it never shows up in a process's argv.
  passwordPlaceholder = "QBITTORRENT_PASSWORD_PBKDF2_PLACEHOLDER";
  setPassword = pkgs.writers.writePython3 "qbittorrent-set-password" { } ''
    import base64
    import hashlib
    import os

    secret = "${config.sops.secrets."nixflix/qbittorrent/webui_password".path}"
    conf = "${config.services.qbittorrent.profileDir}/qBittorrent/config/qBittorrent.conf"

    with open(secret) as f:
        password = f.read().rstrip("\n")
    salt = os.urandom(16)
    key = hashlib.pbkdf2_hmac("sha512", password.encode(), salt, 100000)
    hashed = ":".join(base64.b64encode(b).decode() for b in (salt, key))

    with open(conf) as f:
        text = f.read()
    # Rewritten in place, so the file keeps its owner and mode.
    with open(conf, "w") as f:
        f.write(text.replace("${passwordPlaceholder}", hashed))
  '';
in
{
  sops.secrets."nixflix/qbittorrent/webui_password".restartUnits = [ "qbittorrent.service" ];

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
        # Filled in at start-up by setPassword above; the store only ever
        # sees this placeholder.
        Password_PBKDF2 = "@ByteArray(${passwordPlaceholder})";
        AlternativeUIEnabled = true;
        RootFolder = "${pkgs.vuetorrent}/share/vuetorrent";
      };
    };
  };

  systemd.services.qbittorrent.serviceConfig = {
    # Runs with `+` (full privileges) so the password can stay 0400 root, and
    # after the upstream install step that would otherwise clobber the
    # substitution.
    ExecStartPre = lib.mkAfter [ "+${setPassword}" ];
    # Downloads need to be group-writable for the arr hardlinks, but
    # qBittorrent also rewrites its own config (with the password hash) under
    # this umask, so nothing for other users.
    UMask = "0007";
  };

  # LAN/NetBird only: in internalHosts in ./nginx.nix.
  services.nginx.virtualHosts."qbittorrent.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/".proxyPass = "http://127.0.0.1:${toString config.services.qbittorrent.webuiPort}";
  };
}
