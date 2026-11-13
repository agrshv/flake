{
  lib,
  pkgs,
  pkgs-unstable,
  ...
}:
{
  # security.lockKernelModules = true;

  # Distrust these roots system-wide. Names must match the certificate labels
  # in the cacert bundle exactly, and cacert's build fails on a name that isn't
  # in the store (emSign ECC Root CA - G3 was dropped upstream in nss 3.131).
  security.pki.caCertificateBlacklist = [
    "Comodo AAA Services root"
  ];

  # Shared by every host; per-host additions (extra substituters, the flake
  # registry pin) live next to the host that needs them. NB: @wheel is trusted
  # rather than just root: deploy-rs copies closures and builds on the servers
  # as the login user, and `nh` runs without sudo-ing the nix daemon calls.
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
    # Builds run in the daemon, so priority has to be set here: idle CPU and
    # IO scheduling keeps the desktop responsive while a build uses every core.
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";
    channel.enable = false;
  };

  # Every host has a disk swapfile (disko). zswap keeps recently swapped pages
  # compressed in RAM and writes only the coldest to disk once its pool fills,
  # so swapping stays cheap. Module defaults: zstd, zsmalloc, 25% pool, shrinker.
  boot.zswap.enable = true;

  # Every host is btrfs (disko). A monthly scrub re-reads all data against its
  # checksums, so silent corruption shows up in the journal while the other
  # copies (restic, syncthing) are still good, not on the day a file is needed.
  services.btrfs.autoScrub.enable = true;

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

  # System-wide rather than home-manager, so the servers (no home-manager) get
  # the same config as the laptop. Mainly for sessions that outlive an SSH
  # connection, and for Claude Code's agent-team split panes, which need tmux.
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    # Windows and panes from 1, like the compositor's tags and the number row.
    baseIndex = 1;
    clock24 = true;
    # The 500ms default makes Esc lag in editors and Claude Code.
    escapeTime = 10;
    historyLimit = 50000;
    extraConfig = ''
      set -g mouse on
      set -g renumber-windows on
      # Editors and Claude Code redraw/refresh on focus changes.
      set -g focus-events on
      # Ghostty does truecolor, and modified keys like Shift+Enter (newline in
      # Claude Code) only get through with extended keys.
      set -as terminal-features ",xterm-ghostty:RGB:extkeys"
      set -s extended-keys on
    '';
  };

  # Ghostty's terminfo, which this ncurses doesn't ship yet. Over SSH from
  # Ghostty, TERM is xterm-ghostty, and without the entry tmux refuses to start
  # ("missing or unsuitable terminal") and other TUIs fall back to dumb.
  environment.systemPackages = [ pkgs.ghostty.terminfo ];

  # One confirmation before removing more than three files or recursing, for
  # every interactive shell on every host, root's included (`sudo rm` and
  # `\rm` skip it). The laptop's own shells trash instead (programs/cli.nix);
  # the servers have no trash, and a prompt is the safer habit there.
  environment.shellAliases.rm = "rm -I";

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

  # Hardware comes from each host's facter report (flake.nix), but not its
  # networking: facter's DHCP module sets useDHCP on every interface the report
  # lists. On the laptop that starts dhcpcd next to NetworkManager; the servers
  # already DHCP every interface by default; and a report taken with a tunnel
  # up (drake's awg0) would put DHCP on the tunnel too.
  hardware.facter.detected.dhcp.enable = false;

  # Show asterisks while typing the sudo password.
  security.sudo.extraConfig = ''
    Defaults pwfeedback
  '';

  # Hosts with a desktop may override (work-laptop is German).
  i18n.defaultLocale = lib.mkDefault "en_GB.UTF-8";
}
