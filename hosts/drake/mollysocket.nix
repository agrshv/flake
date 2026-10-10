{ config, pkgs, ... }:
let
  # The module's DynamicUser is named after the unit; a transient unit asking
  # for the same User= shares its UID while the service runs, so admin
  # commands can touch the database without root-owned files ending up in the
  # state dir (or systemd re-chowning it to some other dynamic UID).
  mollysocket-admin = pkgs.writeShellScriptBin "mollysocket-admin" ''
    exec ${config.systemd.package}/bin/systemd-run --pipe --wait --quiet \
      -p DynamicUser=yes -p User=mollysocket \
      -p StateDirectory=mollysocket -p WorkingDirectory=/var/lib/mollysocket \
      -p EnvironmentFile=${config.sops.secrets."mollysocket/env".path} \
      /run/current-system/sw/bin/mollysocket "$@"
  '';
in
{
  # MOLLY_VAPID_PRIVKEY=<key>, from `mollysocket vapid generate`. Molly is
  # given the matching public key via the air-gapped QR code; rotating the key
  # means re-linking Molly.
  sops.secrets."mollysocket/env".restartUnits = [ "mollysocket.service" ];

  # Signal push for Molly via UnifiedPush, delivered through ./ntfy.nix.
  # Air-gapped: no web server, so nothing to expose next to stalwart on 443.
  # Linking is manual, as root on drake:
  #   mollysocket-admin qrcode airgapped     # scan in Molly (light theme!)
  #   mollysocket-admin connection add ...   # the command Molly then shows
  #   mollysocket-admin connection ping <account id>
  services.mollysocket = {
    enable = true;
    environmentFile = config.sops.secrets."mollysocket/env".path;
    settings = {
      webserver = false;
      # Absolute, so the admin wrapper can never open a stray db in its cwd.
      db = "/var/lib/mollysocket/db.sqlite";
      allowed_endpoints = [ "https://ntfy.agrshv.dev:2443" ];
      # Only root can add connections without the web server, so the account
      # allowlist would add nothing.
      allowed_uuids = [ "*" ];
    };
  };

  environment.systemPackages = [ mollysocket-admin ];
}
