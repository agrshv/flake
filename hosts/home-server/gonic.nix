{ lib, ... }:
let
  stateDir = "/var/lib/gonic";
in
{
  # Second Subsonic server over the same library Navidrome serves, browsed by
  # folder rather than by tags. Read-only: gonic never writes to music-path, so
  # slskd/wrtag stay the only writers.
  #
  # First start creates an `admin` user with password `admin`. Change it in the
  # web UI before moving this out of internalHosts (./nginx.nix).
  services.gonic = {
    enable = true;
    settings = {
      music-path = [ "/var/lib/navidrome/music" ];
      podcast-path = "${stateDir}/podcasts";
      playlists-path = "${stateDir}/playlists";
      # Rescan hourly, and pick up wrtag's imports as they land in between.
      scan-interval = 60;
      scan-watcher-enabled = true;
    };
  };

  # The module runs gonic as root with no capabilities in a private user
  # namespace, where every group but the unit's own maps to nobody, so it can't
  # read the library (navidrome:navidrome 2770, see ./slskd.nix). Running as a
  # real user whose *primary* group is navidrome is what survives that mapping
  # (SupplementaryGroups wouldn't).
  users.users.gonic = {
    isSystemUser = true;
    group = "navidrome";
  };
  systemd.services.gonic.serviceConfig = {
    User = "gonic";
    Group = "navidrome";
  };

  # The module bind-mounts these into gonic's root directory, which fails if
  # they don't exist yet.
  systemd.tmpfiles.settings.gonicDirs =
    lib.genAttrs
      [
        "${stateDir}/podcasts"
        "${stateDir}/playlists"
      ]
      (_: {
        d = {
          user = "gonic";
          group = "navidrome";
          mode = "0750";
        };
      });

  services.nginx.virtualHosts."gonic.agrshv.dev" = {
    forceSSL = true;
    useACMEHost = "agrshv.dev";
    locations."/".proxyPass = "http://127.0.0.1:4747";
  };
}
