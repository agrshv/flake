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

  nixpkgs.overlays = [ inputs.millennium.overlays.default ];

  nixpkgs.config.allowUnfree = true;

  # TPM2 LUKS unlock
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
        secureBoot.enable = true;
        extraEntries = ''
          /Windows 11
          protocol: efi
          path: uuid(80ff5274-5886-4219-89a8-e228f6e1ac0d):/EFI/Microsoft/Boot/bootmgfw.efi
        '';
      };
    };
    plymouth = {
      enable = true;
      font = "${pkgs.dejavu_fonts.minimal}/share/fonts/truetype/DejaVuSans.ttf";
    };
  };

  security.tpm2 = {
    enable = true;
    pkcs11.enable = true;
    tctiEnvironment.enable = true;
  };

  hardware.i2c.enable = true;

  networking.hostName = "desktop";
  networking.networkmanager.enable = true;
  time.timeZone = "Asia/Almaty";

  users.users.d3spair = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "tss"
      "i2c"
    ];
    initialPassword = "changeme";
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Sway + minimal stack
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  # Launcher
  environment.systemPackages = with pkgs; [
    mako # notifications
    grim # screenshots
    slurp # region select
    wl-clipboard # clipboard
    pavucontrol # audio control
    networkmanagerapplet
    vim
    git
    btop
    tpm2-tss
    tpm2-tools
    ddcutil
    librsvg # SVG loader for gdk-pixbuf (needed for swaybar tray icons)
  ];

  # Portal for screen sharing, file dialogs etc
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-wlr ];
  };

  # Login manager — keep it minimal
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --user-menu --issue --asterisks --remember --remember-user-session --time";
        user = "greeter";
      };
    };
  };

  programs.ssh.startAgent = true;

  programs.steam = {
    enable = true;
    package = pkgs.millennium-steam;
    extraPackages = with pkgs; [
      gamescope
      mangohud
      mangojuice
    ];
    extraCompatPackages = with pkgs; [
      proton-ge-bin
      steamtinkerlaunch
    ];
    protontricks.enable = true;
  };

  # Audio
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # Fonts
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    nerd-fonts.jetbrains-mono
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

  system.stateVersion = "25.11";

  system.activationScripts.efiBootFallback = ''
    mkdir -p /boot/EFI/boot
    touch /boot/EFI/boot/BOOTX64.EFI
  '';
}
