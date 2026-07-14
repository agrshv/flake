{
  # Pinchflat — "Sonarr for YouTube". Subscribes to channels/playlists, runs
  # yt-dlp on a schedule, and writes videos + NFO/thumbnail sidecars that
  # Jellyfin indexes as a normal library. Bound to 127.0.0.1:8945, fronted by
  # nginx at tube.agrshv.dev (behind the KZ GeoIP gate — see guardedHosts in
  # ./nginx.nix). No player of its own; you watch in Jellyfin.

  # Downloads land inside the nixflix media tree so Jellyfin can pick them up.
  # /data/media is root:media 0775 (see the nixflix module), so add pinchflat to
  # the `media` group and give the subdir setgid (2775) — new files inherit the
  # media group and stay readable by Jellyfin. `extraGroups` is the authoritative
  # forward mapping (nixflix.mediaUsers → groups.media.members doesn't render in
  # this nixpkgs); the `media` group itself is created by the nixflix module.
  users.users.pinchflat.extraGroups = [ "media" ];

  systemd.tmpfiles.settings."10-pinchflat"."/data/media/youtube".d = {
    mode = "2775";
    user = "pinchflat";
    group = "media";
  };

  services.pinchflat = {
    enable = true;
    port = 8945;
    mediaDir = "/data/media/youtube";

    # Real SECRET_KEY_BASE (>= 64 bytes) rather than the weak `selfhosted` dev
    # secret. Create /root/pinchflat.env on the host (root-only), e.g.:
    #   SECRET_KEY_BASE=$(openssl rand -hex 64)
    # Optional HTTP basic auth on top of the geo gate (Pinchflat has no SSO):
    #   BASIC_AUTH_USERNAME=d3spair
    #   BASIC_AUTH_PASSWORD=...
    secretsFile = "/root/pinchflat.env";

    # yt-dlp uses this dir for cookies/config if you need to pass a cookies file
    # for age-gated / members-only content later. Defaults are otherwise fine.
    # extraConfig.YT_DLP_WORKER_CONCURRENCY = 1;
  };

  # Phoenix LiveView UI needs websocket upgrades proxied.
  services.nginx.virtualHosts."tube.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/" = {
      proxyPass = "http://127.0.0.1:8945";
      proxyWebsockets = true;
    };
  };

  # After downloading, add a "YouTube" library in Jellyfin pointing at
  # /data/media/youtube (content type: Shows or Movies — Shows groups by channel
  # nicely). Pinchflat's NFO/thumbnail output makes it index cleanly.
}
