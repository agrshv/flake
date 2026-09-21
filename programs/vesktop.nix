{
  # Themed by noctalia instead: its community `discord` template (enabled in
  # programs/noctalia.nix) writes ~/.config/vesktop/themes/noctalia.theme.css.
  # The catppuccin module did the same job by pinning enabledThemes at a file
  # that @imported the theme from catppuccin.github.io at runtime.
  catppuccin.vesktop.enable = false;

  programs.vesktop = {
    enable = true;
    settings = {
      appBadge = false;
      arRPC = true;
      checkUpdates = false;
      customTitleBar = false;
      disableMinSize = true;
      minimizeToTray = true;
      tray = true;
      splashTheming = true;
      staticTitle = true;
      hardwareAcceleration = true;
      discordBranch = "stable";
      clickTrayToShowHide = true;
      enableTaskbarFlashing = true;
      enableSplashScreen = false;
    };
    vencord = {
      useSystem = true;
      settings = {
        # The "material" variant of the discord template. It also ships
        # noctalia.theme.css ("midnight") and discord-system24.css in the same
        # directory; swap the name here to use one of those instead. They are
        # whole-client stylesheets, so enable one at a time.
        enabledThemes = [ "noctalia-material.theme.css" ];
        autoUpdate = false;
        autoUpdateNotification = false;
        notifyAboutUpdates = false;
        winCtrlQ = false;
        plugins = {
          SilentTyping = {
            enabled = true;
            showIcon = true;
            contextMenu = true;
            isEnabled = true;
          };
          FakeNitro.enabled = true;
          ClearURLs.enabled = true;
          AnonymiseFileNames.enabled = true;
          AlwaysTrust = {
            enabled = true;
            domain = true;
            file = false;
          };
        };
      };
    };
  };
}
