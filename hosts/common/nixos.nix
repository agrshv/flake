{ lib, pkgs-unstable, ... }:
{
  # security.lockKernelModules = true;

  # Distrust these roots system-wide. Names must match the certificate labels
  # in the cacert bundle exactly; a typo is silently ignored.
  security.pki.caCertificateBlacklist = [
    "Comodo AAA Services root"
    "emSign ECC Root CA - G3"
  ];

  # Shared by every host; per-host additions (extra substituters, the flake
  # registry pin) live next to the host that needs them. NB: @wheel is trusted
  # rather than just root, which is what lets remote `--target-host` / `--build-host`
  # deploys and `nh` run without sudo-ing the nix daemon calls.
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        "@wheel"
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
    # Hard-link identical files in the store to reclaim space after each build.
    optimise.automatic = true;
    channel.enable = false;
  };

  services.netbird = {
    enable = true;
    # nixos-26.05 ships netbird 0.71.4, which predates the protocol change that
    # carries account-managed DNS zones: the management server now sends them in
    # NetworkMap.account_zones (field 16), a field 0.71.4's protobuf doesn't know
    # and therefore silently discards. Symptom is that peer FQDNs
    # (*.netbird.cloud, delivered the old way via custom_zones) resolve fine
    # while records from a zone managed in the NetBird dashboard never arrive —
    # `netbird status` reports "Nameservers: 0/0" and the local resolver
    # forwards those names straight to the upstream LAN DNS. Track unstable
    # until stable catches up.
    package = pkgs-unstable.netbird;
  };

  services.openssh = {
    enable = true;
    startWhenNeeded = true;
    settings = {
      # Both, not just the first: with only PasswordAuthentication off, sshd
      # still offers keyboard-interactive, which PAM answers with the account
      # password — password logins would keep working.
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      # No host authorizes a root key: deploys log in as me.user and sudo
      # (@wheel is a trusted nix user, so remote builds work without root).
      PermitRootLogin = "no";
    };
  };

  # Show asterisks while typing the sudo password.
  security.sudo.extraConfig = ''
    Defaults pwfeedback
  '';

  # Hosts with a desktop may override (work-laptop is German).
  i18n.defaultLocale = lib.mkDefault "en_GB.UTF-8";
}
