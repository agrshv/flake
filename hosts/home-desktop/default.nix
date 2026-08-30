{ pkgs, inputs, ... }:
{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
    ../common/nixos.nix
    ../common/desktop.nix
    inputs.work.nixosModules.default
  ];

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    kernelModules = [
      "ntsync"
      "igc"
    ];
    initrd = {
      kernelModules = [ "amdgpu" ];
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

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = [ pkgs.intel-media-driver ];
    extraPackages32 = [ pkgs.pkgsi686Linux.intel-media-driver ];
  };
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  networking.hostName = "home-desktop";

  users.users.d3spair.extraGroups = [
    "tss"
    "i2c"
  ];

  environment.systemPackages = with pkgs; [
    tpm2-tss
    tpm2-tools
    ddcutil
  ];

  programs.steam = {
    enable = true;
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

  services.gvfs.enable = true;
  services.tumbler.enable = true;

  system.stateVersion = "25.11";

  system.activationScripts.efiBootFallback = ''
    mkdir -p /boot/EFI/boot
    touch /boot/EFI/boot/BOOTX64.EFI
  '';
}
