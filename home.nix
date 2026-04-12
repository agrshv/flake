{ config, pkgs, ... }:

{
  imports = [
    ./programs/bash.nix
    ./programs/claude-code.nix
    ./programs/doctl.nix
    ./programs/firefox.nix
    ./programs/fuzzel.nix
    ./programs/ghorg.nix
    ./programs/ghostty.nix
    ./programs/git.nix
    ./programs/glab.nix
    ./programs/k9s.nix
    ./programs/keepassxc.nix
    ./programs/kubectl.nix
    ./programs/mako.nix
    ./programs/nh.nix
    ./programs/obsidian.nix
    ./programs/podman.nix
    ./programs/remmina.nix
    ./programs/ssh.nix
    ./programs/starship.nix
    ./programs/sway.nix
    ./programs/swaylock.nix
    ./programs/udiskie.nix
    ./programs/vesktop.nix
    ./programs/waybar.nix
    ./programs/zed.nix
  ];

  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = secrets/workstation.yaml;
  };

  home.username = "d3spair";
  home.homeDirectory = "/home/d3spair";

  catppuccin = {
    enable = true;
    cursors.enable = true;
    flavor = "mocha";
  };

  # GTK dark mode
  gtk = {
    enable = true;
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = true;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = true;
    };
  };

  # Qt dark mode
  qt = {
    enable = true;
    platformTheme.name = "kvantum";
    style = {
      name = "kvantum";
    };
  };

  # Desktop environment dark mode preference
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };

  services.network-manager-applet.enable = true;

  home.packages = with pkgs; [
    telegram-desktop
    teams-for-linux
  ];

  home.pointerCursor = {
    enable = true;
    gtk.enable = true;
    sway.enable = true;
    x11.enable = true;
  };

  # This value determines the Home Manager release that your
  # configuration is compatible with.
  home.stateVersion = "25.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
