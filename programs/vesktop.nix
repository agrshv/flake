{
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
        # The "midnight" variant of noctalia's discord template: it maps every
        # colour straight to a palette role, so contrast holds in light mode
        # and with wallpaper-generated palettes. The "material" variant
        # (noctalia-material.theme.css) derives most fills from the accent's
        # lightness with dark-mode factors, so a dark light-mode `primary`
        # turned the chat bar and buttons navy under dark text.
        # discord-system24.css is the third option; all three are
        # whole-client stylesheets, so only one belongs here.
        enabledThemes = [ "noctalia.theme.css" ];
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
