{ pkgs, ... }:
let
  me = import ../common/me.nix;
in
{
  imports = [
    ../common/disko.nix
    ./hardware-configuration.nix
    ../common/nixos.nix
    ../common/desktop.nix
  ];

  # Pinned so an install can't land on the Ventoy stick it was booted from.
  disko.devices.disk.main.device = "/dev/disk/by-id/nvme-SAMSUNG_MZVLQ512HALU-00000_S4Y4NS0R633464";

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
      limine = {
        enable = true;
        secureBoot = {
          enable = true;
          # Without this the very first bootloader install aborts: signing needs
          # /var/lib/sbctl, which only exists once keys have been made. Enrolling
          # them is still manual (firmware Setup Mode) — see INSTALL.md.
          autoGenerateKeys = true;
        };
      };
    };
    plymouth = {
      enable = true;
      font = "${pkgs.dejavu_fonts.minimal}/share/fonts/truetype/DejaVuSans.ttf";
    };
  };

  hardware.i2c.enable = true;

  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  hardware.enableRedistributableFirmware = true;
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  networking.hostName = "work-laptop";

  users.users.${me.user}.extraGroups = [ "i2c" ];

  environment.systemPackages = with pkgs; [
    brightnessctl
    ddcutil
  ];

  system.stateVersion = "25.11";
}
