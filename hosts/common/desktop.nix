{ pkgs, inputs, ... }:
let
  me = import ./me.nix;
in
{
  imports = [
    inputs.noctalia-greeter.nixosModules.default
  ];
  sops.age.keyFile = "/home/${me.user}/.config/sops/age/keys.txt";

  catppuccin = {
    enable = true;
    cache.enable = true;
  };

  nixpkgs.config = {
    allowUnfree = true;
    # bitwarden-desktop (programs/bitwarden.nix) is pinned upstream to an Electron
    # release nixpkgs marks insecure; permit exactly that build. Revisit on bumps.
    permittedInsecurePackages = [ "electron-39.8.10" ];
  };

  time.timeZone = "Asia/Almaty";

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
      extra-substituters = [ "https://noctalia.cachix.org" ];
      extra-trusted-public-keys = [
        "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
    channel.enable = false;
    registry.nixpkgs-unstable.flake = inputs.nixpkgs-unstable;
  };

  networking.networkmanager.enable = true;

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraPackages = [ ];
  };
  programs.niri.enable = true;
  programs.mangowc.enable = true;
  programs.labwc.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-wlr ];
  };

  programs.noctalia-greeter = {
    enable = true;
    package = inputs.noctalia-greeter.packages.${pkgs.stdenv.hostPlatform.system}.default;
    settings = {
      cursor = {
        theme = "Adwaita";
        size = 24;
        package = pkgs.adwaita-icon-theme;
      };
    };
  };

  hardware.graphics.enable = true;

  # SSH_AUTH_SOCK is Bitwarden Desktop's agent (programs/bitwarden.nix); the
  # system ssh-agent would shadow it.
  programs.ssh.startAgent = false;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    nerd-fonts.jetbrains-mono
    jetbrains-mono
    nerd-fonts.symbols-only
  ];

  services.syncthing = {
    enable = true;
    user = me.user;
    dataDir = "/home/${me.user}";
    openDefaultPorts = true;
    settings = {
      devices."phone".id = "ERU7IIB-SSIQSQB-F242ET4-WG6TYCY-NSXQ5KZ-ET7PZZX-HYDMHLA-TNYP3AF";
      folders = {
        "tyd4h-e2mdp" = {
          path = "/home/${me.user}/Documents/Obsidian Vault";
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

  services.udisks2.enable = true;

  services.gnome = {
    gnome-keyring.enable = true;
    gcr-ssh-agent.enable = false;
  };

  services.upower.enable = true;

  # Opens firewall ports 1714-1764 (TCP/UDP) for device discovery; the daemon
  # runs as a user service (programs/noctalia.nix) and Noctalia is the UI.
  programs.kdeconnect.enable = true;
}
