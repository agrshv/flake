{ lib, pkgs, ... }:
let
  # Fires on slskd's DownloadDirectoryComplete event. slskd stringifies the
  # event to JSON in $SLSKD_SCRIPT_DATA; we pull out the finished folder and
  # hand it to wrtagweb (see wrtag.nix) over its local HTTP API.
  wrtag-hook = pkgs.writeShellApplication {
    name = "slskd-wrtag-hook";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      dir=$(jq -er '.localDirectoryName' <<<"''${SLSKD_SCRIPT_DATA:-}") || {
        echo "slskd-wrtag-hook: no .localDirectoryName in SLSKD_SCRIPT_DATA" >&2
        exit 1
      }

      echo "slskd-wrtag-hook: queueing $dir"
      # confirm=false: perfect matches import automatically, low-confidence ones
      # wait in the wrtagweb queue for manual review. WRTAG_WEB_API_KEY comes
      # from slskd's environmentFile.
      curl --fail --silent --show-error \
        -u ":''${WRTAG_WEB_API_KEY}" \
        --data-urlencode "path=$dir" \
        --data-urlencode "confirm=false" \
        http://127.0.0.1:7373/op/move
    '';
  };
in
{
  services.slskd = {
    enable = true;
    environmentFile = "/root/slskd.env";
    settings = {
      shares.directories = [ "/var/lib/navidrome/music" ];
      integration.scripts.wrtag = {
        on = [ "DownloadDirectoryComplete" ];
        run.executable = lib.getExe wrtag-hook;
      };
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
    # navidrome:navidrome 2770: slskd/wrtagweb write via the navidrome group,
    # and setgid makes every imported dir/file inherit group navidrome so
    # Navidrome (in that group) can read them. The group MUST be navidrome, not
    # slskd — otherwise setgid propagates slskd down the tree and navidrome,
    # which isn't in the slskd group, gets locked out as "other".
    # mkForce overrides the navidrome module's ":"-prefixed rule (which only
    # applies on creation, so it never fixed the pre-existing slskd group).
    "/var/lib/navidrome/music"."d" = {
      user = lib.mkForce "navidrome";
      group = lib.mkForce "navidrome";
      mode = lib.mkForce "2770";
    };
    "/var/lib/navidrome"."d".mode = lib.mkForce "0710";
  };

  networking.firewall.allowedTCPPorts = [ 50300 ];
}
