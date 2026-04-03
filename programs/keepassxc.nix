{
  programs.keepassxc = {
    enable = true;
    # autostart = true;
    settings = {
      General.ConfigVersion = 2;
      Browser.Enabled = true;
      SSHAgent.Enabled = true;
      FdoSecrets.Enabled = true;
      GUI = {
        TrayIconAppearance = "monochrome-light";
        ApplicationTheme = "dark";
        ShowTrayIcon = true;
        MinimizeToTray = true;
        MinimizeOnClose = true;
      };
    };
  };
}
