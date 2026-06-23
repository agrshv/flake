{ inputs, pkgs, ... }:
let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };

  # Shared with the slskd post-download hook (see slskd.nix). Defines how
  # releases are laid out in the Navidrome library and what extra metadata
  # wrtag writes.
  wrtagEnv = {
    # Path-format syntax is for wrtag v0.30+ (running v0.31.x). v0.30.0 changed
    # the template data model; old v0.2x configs error with e.g.
    # `function "disambiguation" not defined`. What moved from functions to
    # precomputed fields on the template data:
    #   disambiguation .Release   -> .ReleaseDisambiguation
    #   isCompilation .Release.ReleaseGroup -> .IsCompilation
    #   .TrackNum -> .Track.Position;  len .Tracks -> .Media.TrackCount
    #   .Tracks -> .Media;  .Media.Position is the disc number
    # Still functions: artists, artistsString, safepath, pad0, sort, join.
    WRTAG_PATH_FORMAT = "/var/lib/navidrome/music/{{ artists .Release.Artists | sort | join \"; \" | safepath }}/({{ .Release.ReleaseGroup.FirstReleaseDate.Year }}) {{ .Release.Title | safepath }}{{ with .ReleaseDisambiguation }} ({{ . | safepath }}){{ end }}/{{ if gt (len .Release.Media) 1 }}d{{ pad0 2 .Media.Position }} {{ end }}{{ pad0 2 .Track.Position }}.{{ .Media.TrackCount | pad0 2 }} {{ if .IsCompilation }}{{ artistsString .Track.Artists | safepath }} - {{ end }}{{ .Track.Title | safepath }}{{ .Ext }}";
    WRTAG_ADDON = "replaygain true-peak,lyrics lrclib";
    WRTAG_COVER_UPGRADE = "true";
    WRTAG_TAG_CONFIG = "drop COMMENT";
  };
in
{
  # Long-running importer with a job queue and a web UI for resolving
  # low-confidence MusicBrainz matches. slskd POSTs finished download dirs to
  # it; perfect matches import automatically, the rest wait for review.
  systemd.services.wrtagweb = {
    description = "wrtag web importer";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = wrtagEnv // {
      WRTAG_WEB_LISTEN_ADDR = "127.0.0.1:7373";
      WRTAG_WEB_DB_PATH = "/var/lib/wrtag/wrtag.db";
    };

    path = [ pkgs-unstable.rsgain ]; # wrtag's replaygain addon shells out to it

    serviceConfig = {
      # Reuse the slskd identity: already owns the downloads dir (so `move` can
      # remove the source) and is in the navidrome group (so it can write the
      # music library).
      User = "slskd";
      Group = "slskd";
      SupplementaryGroups = [ "navidrome" ];
      # Provides WRTAG_WEB_API_KEY=... (create this file out of band).
      EnvironmentFile = "/root/wrtag.env";
      StateDirectory = "wrtag";
      # wrtag's go-taglib-wasm backend extracts a wazero runtime into
      # /tmp/go-taglib-wasm; a private /tmp avoids clashing with a copy left
      # there by another user (e.g. a `nix shell` run as root/d3spair), which
      # otherwise causes "permission denied" on that path.
      PrivateTmp = true;
      # Create dirs 2775 and files 0664 so any navidrome-group member can write
      # into a path another one made. The default 0022 yields dirs 2755 (group
      # r-x, no write), so a release dir created by one import blocks the next
      # one that lands inside it. Combined with the setgid on music/ (which
      # forces group navidrome), new paths become navidrome:navidrome 2775.
      UMask = "0002";
      ExecStart = "${pkgs-unstable.wrtag}/bin/wrtagweb";
      Restart = "on-failure";
    };
  };

  services.nginx.virtualHosts."wrtag.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/".proxyPass = "http://127.0.0.1:7373";
  };
}
