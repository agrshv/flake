{
  programs.keepassxc = {
    enable = true;
    autostart = true;
    settings = {
      General.ConfigVersion = 2;
      Browser = {
        Enabled = true;
        CustomProxyLocation = "";
      };
      GUI = {
        ApplicationTheme = "dark";
        ColorPasswords = true;
        MinimizeOnClose = true;
        MinimizeToTray = true;
        ShowTrayIcon = true;
        TrayIconAppearance = "monochrome-light";
      };
      KeeShare = {
        Active = "";
        QuietSuccess = true;
      };
      PasswordGenerator = {
        AdditionalChars = "";
        AdvancedMode = false;
        ExcludedChars = "";
        Length = 32;
        SpecialChars = false;
      };
      SSHAgent.Enabled = true;
      Security.LockDatabaseIdleSeconds = 1800;
    };
  };
}
