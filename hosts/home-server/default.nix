{
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  sops = {
    defaultSopsFile = ../../secrets/workstation.yaml;
    age.keyFile = "/home/d3spair/.config/sops/age/keys.txt";
  };

  catppuccin.enable = true;

  nixpkgs.config.allowUnfree = true;

  boot = {
    initrd = {
      systemd.enable = true;
      luks.devices."cryptroot" = {
        device = "/dev/disk/by-partlabel/disk-main-luks";
        allowDiscards = true;
      };
    };
    loader = {
      efi.canTouchEfiVariables = true;
      limine = {
        enable = true;
        # secureBoot.enable = true;
      };
    };
  };

  # hardware.graphics.enable = true;
  # hardware.graphics.extraPackages = with pkgs; [
  #   # intel-media-driver
  #   # vpl-gpu-rt
  # ];
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
      "networkmanager"
    ];
    initialPassword = "changeme";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFoJfwlfB0GAnaPFj2oLVK0HA9uGWPwoTfsfTrIPHpgb @personal_key"
    ];
  };

  # nix.settings.experimental-features = [
  #   "nix-command"
  #   "flakes"
  # ];
  # nix.gc = {
  #   automatic = true;
  #   dates = "weekly";
  #   options = "--delete-older-than 14d";
  # };

  environment.systemPackages = with pkgs; [
    vim
    git
    btop
  ];

  # services.syncthing = {
  #   enable = true;
  #   user = "d3spair";
  #   dataDir = "/home/d3spair";
  #   openDefaultPorts = true;
  #   settings = {
  #     devices."phone".id = "ERU7IIB-SSIQSQB-F242ET4-WG6TYCY-NSXQ5KZ-ET7PZZX-HYDMHLA-TNYP3AF";
  #     folders = {
  #       "r6uge-vvagb" = {
  #         path = "/home/d3spair/Documents/KeePass";
  #         devices = [ "phone" ];
  #       };
  #       "tyd4h-e2mdp" = {
  #         path = "/home/d3spair/Documents/Obsidian Vault";
  #         devices = [ "phone" ];
  #       };
  #     };
  #   };
  # };

  # virtualisation.docker = {
  #   storageDriver = "btrfs";
  #   rootless = {
  #     enable = true;
  #     setSocketVariable = true;
  #   };
  # };

  system.stateVersion = "25.11";
}
