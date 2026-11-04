{
  config,
  pkgs,
  inputs,
  ...
}:
let
  me = import ./me.nix;
in
{
  imports = [
    inputs.noctalia-greeter.nixosModules.default
    inputs.umbriel.nixosModules.default
  ];
  sops.age.keyFile = "/home/${me.user}/.config/sops/age/keys.txt";
  # The key lives on /home, which isn't mounted yet when the default activation
  # script decrypts secrets (in the initrd), so system secrets (the Office VPN
  # key, flake-work) never appeared after a boot. As a unit it waits for the
  # key file's mount.
  sops.useSystemdActivation = true;

  nixpkgs.config = {
    allowUnfree = true;
    # bitwarden-desktop (programs/bitwarden.nix) is pinned upstream to an Electron
    # release nixpkgs marks insecure; permit exactly that build. Revisit on bumps.
    permittedInsecurePackages = [ "electron-39.8.10" ];
  };

  time.timeZone = "Asia/Almaty";

  # Kill the worst offender when memory pressure stalls the session, instead of
  # thrashing swap for minutes until the kernel OOM killer finally acts. oomd
  # runs by default but watches no slice until told to: these kill a cgroup
  # stalled on memory >80% of the time for 20s, and the root-slice swap rule
  # kills the biggest swap user once swap is 90% full.
  systemd.oomd = {
    enableRootSlice = true;
    enableUserSlices = true;
  };
  systemd.slices."-".sliceConfig.ManagedOOMSwap = "kill";

  users.users.${me.user} = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    # First-boot password (applies at user creation only; passwd changes stick).
    # Can't come from sops here: the age key is derived from the personal SSH key
    # *after* first login (INSTALL.md), so the hash must be usable before any
    # secret decrypts. A yescrypt hash of a 24-char random password is safe to
    # commit; the plaintext lives in Bitwarden ("workstation bootstrap").
    initialHashedPassword = "$y$j9T$I6iqFqXRI5cRhQN.6/s/71$b3YN8CLgAkP4JcvlDIbmPSvu2rb94aBE87OliZ7MHS1";
    openssh.authorizedKeys.keys = [
      me.sshKey
    ];
  };

  # Root shell in the initrd when boot fails before the disk is unlocked
  # (bad LUKS setup, broken TPM enrolment, ...). Behind the same bootstrap
  # password as above, which can be looked up in Bitwarden from another
  # device; `true` would hand that shell to anyone at the keyboard.
  boot.initrd.systemd.emergencyAccess = config.users.users.${me.user}.initialHashedPassword;

  # Everything shared with the headless hosts is in ../common/nixos.nix; only
  # the desktop-specific bits stay here.
  nix = {
    settings = {
      extra-substituters = [
        "https://noctalia.cachix.org"
        "https://nkl-sofka.cachix.org"
        # umbriel + its portal, built and pushed by .github/workflows/check.yml.
        "https://agrshv.cachix.org"
      ];
      extra-trusted-public-keys = [
        "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
        "nkl-sofka.cachix.org-1:hLg9frFNJynrxe7SSBb/p6pbawlpZmG10bw+wLsTufw="
        "agrshv.cachix.org-1:XiYuLBe6RL8hAgYB8Yi9/7dxk+OJMmOGTs2CGgJrsQQ="
      ];
    };
    registry.nixpkgs-unstable.flake = inputs.nixpkgs-unstable;
  };

  networking.networkmanager.enable = true;
  # Per-link split DNS. Without it netbird falls back to rewriting
  # /etc/resolv.conf and forwards everything to the nameservers it saw at
  # startup, so a VPN connected afterwards (FRHC) never gets its DNS used.
  # NetworkManager picks resolved up automatically.
  services.resolved.enable = true;

  programs.niri.enable = true;
  # Session + portal come from the flake's NixOS module (registers with
  # noctalia-greeter via displayManager.sessionPackages); the user config
  # lives in programs/umbriel.nix (home-manager).
  programs.umbriel.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-wlr ];
  };

  services.displayManager.noctalia-greeter = {
    enable = true;
    package = inputs.noctalia-greeter.packages.${pkgs.stdenv.hostPlatform.system}.default;
    # noctalia's greeter_sync.auto_sync (programs/noctalia.nix) pushes every
    # theme/wallpaper change here; without this each one is a polkit prompt.
    # The passwordless path is appearance-only and never takes a session command.
    passwordless-sync-users = [ me.user ];
    settings = {
      # Start on the password step for the only account, into niri.
      session.default = "Niri";
      user.default = me.user;
      # The password is typed in us; niri's ru/de layouts are session-only.
      keyboard.layout = "us";
      # Monitor positions and modes as niri sets them (programs/niri.nix), so
      # there is no modeset at login and the pointer crosses edges the same
      # way. Declared here rather than left to greeter sync, which only
      # records a layout while several outputs are connected. DP-2, unplaced
      # in niri too, is appended to the right.
      output = {
        layout = "HDMI-A-1:0,0; eDP-1:0,1440";
        refresh_rate = "DP-2:240; HDMI-A-1:100";
      };
      appearance = {
        font_family = "Inter";
        # Cycle glyph shapes in the password field instead of plain dots.
        password_style = "random";
        hide_logo = true;
      };
      cursor = {
        theme = "Adwaita";
        size = 24;
        package = pkgs.adwaita-icon-theme;
      };
    };
  };

  # The greeter shows each user's AccountsService IconFile. With no icon
  # registered, AccountsService falls back to ~/.face — which home.nix does
  # provide, but /home/${me.user} is 0700, so the greeter (its own user) can't
  # read it and draws the placeholder. Registering the same image through
  # SetIconFile makes AccountsService copy it to the world-readable
  # /var/lib/AccountsService/icons/${me.user} and record it in its own user
  # file, which (unlike writing that file directly) leaves the other keys it
  # keeps there alone. Re-run on every boot/switch so a new avatar hash in
  # home.nix lands here too; it is a no-op when nothing changed.
  systemd.services.accountsservice-avatar = {
    description = "Register the user avatar with AccountsService";
    wantedBy = [ "multi-user.target" ];
    after = [ "accounts-daemon.service" ];
    requires = [ "accounts-daemon.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [
      pkgs.systemd
      pkgs.jq
    ];
    script = ''
      user=$(busctl --json=short call org.freedesktop.Accounts /org/freedesktop/Accounts \
        org.freedesktop.Accounts FindUserByName s ${me.user} | jq -r '.data[0]')
      busctl call org.freedesktop.Accounts "$user" org.freedesktop.Accounts.User \
        SetIconFile s "${config.home-manager.users.${me.user}.home.file.".face".source}"
    '';
  };

  hardware.graphics.enable = true;

  # Backend of noctalia's screen_recorder plugin (programs/noctalia.nix). The
  # module adds the capability-wrapped gsr-kms-server that "focused" capture
  # needs; "portal" capture goes through xdg-desktop-portal-gnome from niri.
  programs.gpu-screen-recorder.enable = true;

  # SSH_AUTH_SOCK is Bitwarden Desktop's agent (programs/bitwarden.nix); the
  # system ssh-agent would shadow it.
  programs.ssh.startAgent = false;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  fonts.packages = with pkgs; [
    inter
    noto-fonts
    noto-fonts-cjk-sans
    nerd-fonts.jetbrains-mono
    jetbrains-mono
    nerd-fonts.symbols-only
  ];
  # UI font for noctalia (shell.font_family), the greeter, and anything that
  # asks for plain `sans-serif` — which otherwise resolves to DejaVu Sans.
  fonts.fontconfig.defaultFonts.sansSerif = [
    "Inter"
    "Noto Sans"
  ];

  services.syncthing = {
    enable = true;
    user = me.user;
    dataDir = "/home/${me.user}";
    openDefaultPorts = true;
    settings = {
      devices."phone".id = "ERU7IIB-SSIQSQB-F242ET4-WG6TYCY-NSXQ5KZ-ET7PZZX-HYDMHLA-TNYP3AF";
      folders = {
        # The attribute name is only the label; `id` is what pairs the folder
        # across devices and must match the phone's, which is why it looks
        # generated rather than chosen. The previous id (tyd4h-e2mdp) existed
        # on no other device, so this folder never synced anything — the phone
        # kept logging "Unexpected folder ID in ClusterConfig".
        "obsidian" = {
          id = "hhehl-wc95y";
          path = "/home/${me.user}/Documents/obsidian";
          devices = [ "phone" ];
          ignorePatterns = [ ".obsidian/" ];
        };
      };
    };
  };

  virtualisation.docker = {
    storageDriver = "btrfs";
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };

  # rootless k3d/kind: k3s needs cpuset delegated to the user session
  systemd.services."user@".serviceConfig.Delegate = "cpu cpuset io memory pids";

  services.udisks2.enable = true;

  services.gnome = {
    gnome-keyring.enable = true;
    gcr-ssh-agent.enable = false;
  };

  services.upower.enable = true;

  # Normally pulled in by GNOME/Plasma, which we don't run — niri needs it
  # enabled by hand. Backs Noctalia's power-profile switcher over D-Bus.
  services.power-profiles-daemon.enable = true;

  # Opens firewall ports 1714-1764 (TCP/UDP) for device discovery; the daemon
  # runs as a user service (programs/noctalia.nix) and Noctalia is the UI.
  programs.kdeconnect.enable = true;
}
