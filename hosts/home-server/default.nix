{
  pkgs,
  ...
}:
{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix

    ./miniflux.nix
    ./navidrome.nix
    ./nginx.nix
    ./paperless.nix
    ./postgresql.nix
    ./readeck.nix
    ./searx.nix
    ./slskd.nix
  ];

  sops = {
    defaultSopsFile = ../../secrets/workstation.yaml;
    age.keyFile = "/home/d3spair/.config/sops/age/keys.txt";
  };

  catppuccin.enable = true;

  nixpkgs.config.allowUnfree = true;

  nix = {
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    # gc = {
    #   automatic = true;
    #   dates = "weekly";
    #   options = "--delete-older-than 14d";
    # };
    channel.enable = false;
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

  services.openssh.enable = true;

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

  services.netbird.enable = true;

  system.stateVersion = "25.11";
}
