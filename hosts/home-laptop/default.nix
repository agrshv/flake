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
    initrd = {
      systemd.enable = true;
      luks.devices."cryptroot" = {
        device = "/dev/disk/by-partlabel/disk-main-luks";
        allowDiscards = true;
      };
    };
    loader = {
      efi.canTouchEfiVariables = true;
      limine.enable = true;
    };
    plymouth = {
      enable = true;
      font = "${pkgs.dejavu_fonts.minimal}/share/fonts/truetype/DejaVuSans.ttf";
    };
  };

  hardware.enableRedistributableFirmware = true;
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  networking.hostName = "home-laptop";

  environment.systemPackages = with pkgs; [
    brightnessctl
  ];

  system.stateVersion = "25.11";
}
