{ pkgs, inputs, ... }:
{
  sops = {
    defaultSopsFile = ../../secrets/workstation.yaml;
    age.keyFile = "/home/d3spair/.config/sops/age/keys.txt";
  };

  catppuccin = {
    enable = true;
    cache.enable = true;
  };

  nixpkgs.config.allowUnfree = true;

  time.timeZone = "Asia/Almaty";

  users.users.d3spair = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    initialPassword = "changeme";
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

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-wlr ];
  };

  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --user-menu --asterisks --remember --remember-user-session --time";
      user = "greeter";
    };
  };

  hardware.graphics.enable = true;

  programs.ssh.startAgent = true;

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
    user = "d3spair";
    dataDir = "/home/d3spair";
    openDefaultPorts = true;
    settings = {
      devices."phone".id = "ERU7IIB-SSIQSQB-F242ET4-WG6TYCY-NSXQ5KZ-ET7PZZX-HYDMHLA-TNYP3AF";
      folders = {
        "r6uge-vvagb" = {
          path = "/home/d3spair/Documents/KeePass";
          devices = [ "phone" ];
        };
        "tyd4h-e2mdp" = {
          path = "/home/d3spair/Documents/Obsidian Vault";
          devices = [ "phone" ];
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
}
