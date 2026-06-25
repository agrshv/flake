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
    # Internal endpoint nginx queries to decide whether a request is authorized.
    locations."/internal/authelia/authz" = {
      proxyPass = "http://127.0.0.1:9091/api/authz/auth-request";
      extraConfig = ''
        internal;
        proxy_set_header X-Original-Method $request_method;
        proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
        proxy_set_header Content-Length "";
        proxy_pass_request_body off;
      '';
    };

    locations."/".extraConfig = ''
      auth_request /internal/authelia/authz;
      auth_request_set $user   $upstream_http_remote_user;
      auth_request_set $groups $upstream_http_remote_groups;
      proxy_set_header Remote-User   $user;
      proxy_set_header Remote-Groups $groups;
      error_page 401 =302 https://auth.agrshv.dev/?rd=$scheme://$http_host$request_uri;
    '';
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
