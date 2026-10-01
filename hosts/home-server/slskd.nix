{
  config,
  lib,
  pkgs,
  authelia,
  ...
}:
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
  sops.secrets."slskd/env".restartUnits = [ "slskd.service" ];

  services.slskd = {
    enable = true;
    environmentFile = config.sops.secrets."slskd/env".path;
    settings = {
      shares.directories = [ "/var/lib/navidrome/music" ];
      # Drop slskd's built-in login: access is gated by Authelia forward-auth on
      # the nginx vhost below instead (see authelia.nix). The post-download hook
      # and any other localhost callers hit 127.0.0.1:5030 directly, unaffected.
      web.authentication.disabled = true;
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

  # Gate the public slskd vhost behind Authelia forward-auth (see authelia.nix).
  # The slskd module defines this vhost (domain + nginx options above); these
  # definitions merge into it — the internal authz endpoint and the auth_request
  # guard layered onto the proxied "/" location it already sets up. Access is
  # further restricted to user d3spair / group admins by the access_control rule
  # in authelia.nix.
  services.nginx.virtualHosts."slskd.agrshv.dev" = {
    locations."/internal/authelia/authz" = authelia.authzLocation;
    # The slskd module already defines this vhost's "/" proxyPass; only layer
    # the forward-auth guard onto it.
    locations."/".extraConfig = authelia.guard;
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

    # Default ACL on the library root, so new entries are group-writable no
    # matter who creates them or with what umask (with a default ACL present,
    # the umask is not applied). Without it, a directory made outside the
    # wrtagweb unit — a manual copy, a root CLI run, a restore — comes out
    # e.g. navidrome:navidrome 2750, and later imports into it fail with
    # "mkdir …: permission denied" since slskd only writes via the group.
    # Inheritance happens at creation, so this covers new trees only; the
    # oneshot below repairs what already exists.
    "/var/lib/navidrome/music"."A+".argument = "d:u::rwx,d:g::rwx,d:g:navidrome:rwx,d:m::rwx,d:o::---";
  };

  # Repairs entries that lost group write: anything that predates the ACL above,
  # and anything a restic restore brings back with its old modes. Additive and
  # idempotent — only wrong entries are touched, and "other" bits are left as
  # they are — so normally it walks the tree and changes nothing. Ordered before
  # the writers so an import never races a half-repaired library.
  systemd.services.navidrome-music-perms = {
    description = "Keep the music library group-writable for navidrome group members";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    before = [
      "wrtagweb.service"
      "slskd.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      music=/var/lib/navidrome/music
      find "$music" -mindepth 1 ! -group navidrome -exec chgrp navidrome {} +
      find "$music" -mindepth 1 -type d ! -perm -2070 -exec chmod g+rwxs {} +
      find "$music" -type f ! -perm -0060 -exec chmod g+rw {} +
    '';
  };

  networking.firewall.allowedTCPPorts = [ 50300 ];
}
