{ ... }:

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
