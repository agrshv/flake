{ pkgs, ... }:
let
  me = import ../common/me.nix;
in
{
  imports = [
    ../common/disko.nix
    ./hardware-configuration.nix
    ../common/nixos.nix

    ./actual.nix
    ./authelia.nix
    ./bulwark.nix
    ./dawarich.nix
    ./forgejo.nix
    ./forgejo-runner.nix
    ./nocodb.nix
    ./immich.nix
    ./mealie.nix
    ./miniflux.nix
    ./monica.nix
    ./navidrome.nix
    ./netbird.nix
    ./nginx.nix
    ./nixflix.nix
    ./paperless.nix
    ./pinchflat.nix
    ./postgresql.nix
    ./readeck.nix
    ./redis.nix
    ./restic.nix
    ./searx.nix
    ./slskd.nix
    ./vaultwarden.nix
    ./wrtag.nix
  ];

  disko.devices.disk.main.device = "/dev/disk/by-id/ata-Apacer_AST280_480GB_0E4080B001124";

  # home-server decrypts with its own SSH host key, so no human identity has to
  # live on the box (see .sops.yaml for the derived age recipient). /etc/ssh is
  # in the restic path set precisely so this survives a rebuild.
  sops = {
    defaultSopsFile = ../../secrets/home-server.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
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
        secureBoot = {
          enable = true;
          autoGenerateKeys = true;
          autoEnrollKeys.enable = true;
        };
      };
    };
  };

  hardware.enableRedistributableFirmware = true;

  # VAAPI hardware transcoding for Jellyfin on the Ryzen 5 4600G (Vega 7 iGPU).
  # Mesa's radeonsi provides the VAAPI driver; the render node is /dev/dri/renderD128.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      libva-utils # provides `vainfo` to verify the driver from the CLI
    ];
  };

  networking = {
    hostName = "home-server";
  };

  time.timeZone = "Asia/Almaty";

  users.users.${me.user} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
    ];
    initialPassword = "changeme";
    openssh.authorizedKeys.keys = [
      me.sshKey
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
    me.user
  ];

  system.stateVersion = "25.11";
}
