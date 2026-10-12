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
  #
  # The secret is the bare `base64(salt):base64(key)` (PBKDF2-SHA512, 100000
  # rounds, 16-byte salt), without the @ByteArray() wrapper. Generate it with:
  #   nix run nixpkgs#python3 -- -c 'import base64,getpass,hashlib,os; s=os.urandom(16); k=hashlib.pbkdf2_hmac("sha512",getpass.getpass().encode(),s,100000); print(base64.b64encode(s).decode()+":"+base64.b64encode(k).decode())'
  # The plaintext lives only in the password manager (and in Sonarr/Radarr's
  # download client settings).
  passwordPlaceholder = "QBITTORRENT_PASSWORD_PBKDF2_PLACEHOLDER";
  passwordHash = config.sops.secrets."nixflix/qbittorrent/password_hash".path;
  setPassword = pkgs.writeShellScript "qbittorrent-set-password" ''
    # Anything else makes qBittorrent reject every login with no hint why.
    if ! ${lib.getExe pkgs.gnugrep} -Eqx '[A-Za-z0-9+/]{22}==:[A-Za-z0-9+/]{86}==' ${passwordHash}; then
      echo "${passwordHash} is not a qBittorrent PBKDF2 hash (base64(salt):base64(key))" >&2
      exit 1
    fi
    ${lib.getExe pkgs.replace-secret} '${passwordPlaceholder}' ${passwordHash} \
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
    # Incoming peer connections, TCP and UDP (uTP). Forwarded from the
    # MikroTik to 192.168.88.23 by a fixed dst-nat rule; without it peers can't
    # connect in and less popular torrents crawl. Unset, qBittorrent picks a
    # random port on every start.
    torrentingPort = 50413;
    serverConfig = {
      # The forward is a static router rule, so no UPnP/NAT-PMP mapping.
      Network.PortForwardingEnabled = false;
      # Sonarr/Radarr set a category per download; with automatic torrent
      # management each lands in /data/torrents/<category>, next to the
      # library it gets hardlinked into (./arr.nix).
      BitTorrent.Session = {
        DefaultSavePath = "/data/torrents";
        DisableAutoTMMByDefault = false;

        # Stop seeding at ratio 2 or after 14 days, whichever comes first.
        # Sonarr/Radarr ("Remove Completed" on their download client) then drop
        # the stopped torrent and its /data/torrents copy; the library hardlink
        # stays. Without this, replaced or deleted episodes stay on disk via
        # the torrent's link. Nyaa/1337x are public; Milkie has no seeding rule.
        GlobalMaxRatio = "2";
        GlobalMaxSeedingMinutes = 14 * 24 * 60;
        ShareLimitAction = "Stop";

        # The defaults (3 down, 3 up, 5 total) let a couple of seeding torrents
        # starve downloads, so a season trickled in three at a time. Stalled
        # torrents don't hold a slot.
        QueueingSystemEnabled = true;
        MaxActiveDownloads = 6;
        MaxActiveUploads = 10;
        MaxActiveTorrents = 15;
        IgnoreSlowTorrentsForQueueing = true;
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
    # Runs with `+` (full privileges) so the hash can stay 0400 root, and after
    # the upstream install step that would otherwise clobber the substitution.
    ExecStartPre = lib.mkAfter [ "+${setPassword}" ];
    # Downloads need to be group-writable for the arr hardlinks, but
    # qBittorrent also rewrites its own config (with the password hash) under
    # this umask, so nothing for other users.
    UMask = "0007";
  };

  # Not openFirewall: that would also open the WebUI port, and only for TCP.
  networking.firewall = {
    allowedTCPPorts = [ config.services.qbittorrent.torrentingPort ];
    allowedUDPPorts = [ config.services.qbittorrent.torrentingPort ];
  };

  # LAN/NetBird only: in internalHosts in ./nginx.nix.
  services.nginx.virtualHosts."qbittorrent.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/".proxyPass = "http://127.0.0.1:${toString config.services.qbittorrent.webuiPort}";
  };
}
