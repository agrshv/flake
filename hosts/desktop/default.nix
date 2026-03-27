{ config, pkgs, ... }:
{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix
  ];

  # TPM2 LUKS unlock
  boot.initrd.systemd.enable = true;
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-partlabel/disk-main-luks";
    cryptTabExtraOpts = [ "tpm2-device=auto" ];
    allowDiscards = true;
  };

  security.tpm2 = {
    enable = true;
    pkcs11.enable = true;
    tctiEnvironment.enable = true;
  };

  networking.hostName = "desktop";
  networking.networkmanager.enable = true;
  time.timeZone = "UTC";

  users.users.d3spair = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "tss" ];
    initialPassword = "changeme";
  };

  environment.systemPackages = with pkgs; [
    vim git htop tpm2-tss tpm2-tools
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
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
  
  # Bar
  programs.waybar.enable = true;
  
  # Launcher
  environment.systemPackages = with pkgs; [
    fuzzel          # fast wayland-native launcher
    mako            # notifications
    grim            # screenshots
    slurp           # region select
    wl-clipboard    # clipboard
    ghostty         # terminal (lightweight, wayland-native)
    pavucontrol     # audio control
    networkmanagerapplet
  ];
  
  # Portal for screen sharing, file dialogs etc
  xdg.portal = {
    enable = true;
    wrapperArgs = [ "--replace" ];
    extraPortals = [ pkgs.xdg-desktop-portal-wlr ];
  };
  
  # Login manager — keep it minimal
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd sway";
        user = "greeter";
      };
    };
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
  
  system.stateVersion = "25.11";
}
