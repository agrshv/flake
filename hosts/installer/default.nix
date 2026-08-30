{
  pkgs,
  lib,
  inputs,
  modulesPath,
  ...
}:
let
  me = import ../common/me.nix;
  system = pkgs.stdenv.hostPlatform.system;
in
{
  # Thin bootstrap ISO. Its only job is to boot the hardware, get on the network
  # and let the personal key in over SSH; the actual install runs either from a
  # workstation (nixos-anywhere) or at the console (disko-install) against the
  # flake on GitHub, so this image never goes stale when the config changes.
  # See INSTALL.md.
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # The minimal ISO ships wpa_supplicant; NetworkManager can't coexist with it.
  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = true;
  hardware.enableRedistributableFirmware = true;

  services.getty.autologinUser = "nixos";

  # Key-only SSH for the live `nixos` user (passwordless sudo in the ISO), which
  # is what nixos-anywhere connects as.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  users.users.nixos.openssh.authorizedKeys.keys = [ me.sshKey ];

  environment.systemPackages = [
    pkgs.git
    pkgs.vim
    pkgs.tpm2-tools
    # Same disko revision the hosts are built with, so what formats the disk is
    # what the disko module expects to mount at boot.
    inputs.disko.packages.${system}.disko-install
  ];
}
