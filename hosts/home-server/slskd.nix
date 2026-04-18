{ lib, ... }:
{
  services.slskd = {
    enable = true;
    environmentFile = "/root/slskd.env";
    settings = {
      shares.directories = [ "/var/lib/navidrome/music" ];
    };
    domain = "slskd.agrshv.dev";
    nginx = {
      addSSL = true;
      useACMEHost = "agrshv.dev";
    };
  };

  users.users.slskd.extraGroups = [ "navidrome" ];

  # kinda hack, probably better to relocate music away from /var/lib
  systemd.tmpfiles.settings.navidromeDirs = {
    "/var/lib/navidrome/music"."d".mode = lib.mkForce "0750";
    "/var/lib/navidrome"."d".mode = lib.mkForce "0710";
  };
}
