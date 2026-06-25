{
  pkgs,
  ...
}:
{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ../common/nixos.nix

    ./actual.nix
    ./authelia.nix
    ./dawarich.nix
    ./forgejo.nix
    ./immich.nix
    ./miniflux.nix
    ./monica.nix
    ./navidrome.nix
    ./nginx.nix
    ./paperless.nix
    ./postgresql.nix
    ./readeck.nix
    ./redis.nix
    ./restic.nix
    ./searx.nix
    ./slskd.nix
    ./wrtag.nix
  ];

  sops = {
    defaultSopsFile = ../../secrets/workstation.yaml;
    age.keyFile = "/home/d3spair/.config/sops/age/keys.txt";
  };

  catppuccin = {
    enable = true;
    cache.enable = true;
  };

  nixpkgs.config.allowUnfree = true;

  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
    # Hard-link identical files in the store to reclaim space after each build.
    optimise.automatic = true;
    channel.enable = false;
  };

  # Scheduled `nixos-rebuild switch --flake` against the remote repo, so the
  # server only ever builds what's committed and lockfile bumps stay deliberate
  # (run `nix flake update` + push to actually advance package versions).
  #
  # Disabled for now: flip `enable = true` to activate. Keep `allowReboot =
  # false` until the headless LUKS box has remote/TPM unlock — an auto-reboot
  # would otherwise strand it at the passphrase prompt.
  system.autoUpgrade = {
    enable = false;
    # Self-hosted Forgejo repo. The unit runs as root, so root needs an SSH key
    # authorized for the `forgejo` user (the repo is private + signin-required).
    # Alternatively point this at a local checkout path on the host.
    flake = "git+ssh://forgejo@git.agrshv.dev/d3spair/flake.git#home-server";
    dates = "04:00";
    randomizedDelaySec = "45min";
    allowReboot = false;
  };

  boot = {
    initrd = {
      systemd.enable = true;
      luks.devices."cryptroot" = {
        device = "/dev/disk/by-partlabel/disk-main-luks";
        allowDiscards = true;
      };
      # availableKernelModules = [ "r8169" ];
      # network = {
      #   enable = true;
      #   ssh = {
      #     enable = true;
      #   };
      # };
    };
    loader = {
      efi.canTouchEfiVariables = true;
      limine = {
        enable = true;
        # secureBoot.enable = true;
      };
    };
  };

  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "home-server";
  };

  time.timeZone = "Asia/Almaty";

  users.users.d3spair = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
    ];
    initialPassword = "changeme";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFoJfwlfB0GAnaPFj2oLVK0HA9uGWPwoTfsfTrIPHpgb @personal_key"
    ];
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    btop
  ];

  nix.settings.trusted-users = [
    "root"
    "@wheel"
    "d3spair"
  ];

  system.stateVersion = "25.11";
}
