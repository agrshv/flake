{
  config,
  pkgs,
  pkgs-unstable,
  ...
}:
let
  me = import ./hosts/common/me.nix;
in
{
  imports = [
    ./programs/bash.nix
    ./programs/bitwarden.nix
    ./programs/chromium.nix
    ./programs/claude-code.nix
    ./programs/eza.nix
    ./programs/ghostty.nix
    ./programs/git.nix
    ./programs/k9s.nix
    ./programs/nh.nix
    ./programs/niri.nix
    ./programs/noctalia.nix
    ./programs/obsidian.nix
    ./programs/remmina.nix
    ./programs/ssh.nix
    ./programs/starship.nix
    ./programs/sway.nix
    ./programs/udiskie.nix
    ./programs/vesktop.nix
    ./programs/xdg.nix
    ./programs/zed.nix
  ];

  sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

  home = {
    username = me.user;
    homeDirectory = "/home/${me.user}";

    shell = {
      enableBashIntegration = true;
    };

    pointerCursor = {
      enable = true;
      gtk.enable = true;
      sway.enable = true;
      x11.enable = true;
    };

    packages = with pkgs; [
      pkgs-unstable.telegram-desktop
      teams-for-linux
      dig
      gh
      ouch
      btop
      vim
      wl-clipboard
      pkgs-unstable.fluxcd
    ];
  };

  catppuccin = {
    enable = true;
    cursors.enable = true;
    cache.enable = true;
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

  # NetworkManager secret agent: bridges agent-owned VPN secrets (password-flags=1)
  # from gnome-keyring to NetworkManager. Noctalia provides a network UI but no
  # secret agent, so VPN connections fail silently ("No agents were available")
  # without this. Runs headless (no --indicator) so no tray icon appears.
  services.network-manager-applet.enable = true;

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

  # This value determines the Home Manager release that your
  # configuration is compatible with.
  home.stateVersion = "25.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
