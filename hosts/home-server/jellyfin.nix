{ lib, ... }:
{
  # Jellyfin — libraries are /data/media/{tv,anime,movies} (./arr.nix). Users,
  # libraries and plugins are configured in the web UI and live in
  # /var/lib/jellyfin (backed up, see ./restic.nix).
  services.jellyfin = {
    enable = true;
    # Reads the library and, with subtitles saved next to the media, writes
    # into it.
    group = "media";

    # VAAPI on the Ryzen 5 4600G (Vega 7, VCN 2.1) through Mesa's radeonsi;
    # hardware.graphics is enabled in ./default.nix. AMF is Windows-only.
    hardwareAcceleration = {
      enable = true;
      type = "vaapi";
      device = "/dev/dri/renderD128";
    };
    # encoding.xml is owned by this config; the UI's transcoding page is
    # overwritten on restart (the old file is kept as a backup).
    forceEncodingConfig = true;
    transcoding = {
      enableHardwareEncoding = true;
      # What VCN 2.1 decodes. No AV1 — Renoir has no AV1 decoder.
      hardwareDecodingCodecs = {
        h264 = true;
        hevc = true;
        mpeg2 = true;
        vc1 = true;
        vp9 = true;
      };
      # It encodes H.264 and HEVC; no AV1.
      hardwareEncodingCodecs.hevc = true;
    };
  };

  users.users.jellyfin.extraGroups = [
    "render"
    "video"
  ];

  # Upstream sets 0077; let the media group work with what Jellyfin writes into
  # the library while keeping its state closed to everyone else.
  systemd.services.jellyfin.serviceConfig.UMask = lib.mkForce "0007";

  services.nginx.virtualHosts."jellyfin.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/" = {
      proxyPass = "http://127.0.0.1:8096";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_buffering off;
      '';
    };
  };
}
