{
  # programs.ssh.startAgent exports SSH_AUTH_SOCK only into login shells, not into
  # the systemd user / graphical session environment. Graphical apps started by the
  # user manager (e.g. XDG-autostarted KeePassXC) therefore can't find the agent
  # ("No SSH Agent socket available"). Export it into environment.d so the whole
  # graphical session sees it. %t/ssh-agent is the socket programs.ssh.startAgent
  # creates; ${XDG_RUNTIME_DIR} is expanded by systemd at session start.
  systemd.user.sessionVariables.SSH_AUTH_SOCK = "\${XDG_RUNTIME_DIR}/ssh-agent";

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
      # No AuthSockOverride needed: SSH_AUTH_SOCK is exported into the graphical
      # session env (see systemd.user.sessionVariables in home.nix), so KeePassXC
      # finds the agent via the standard env var.
      SSHAgent.Enabled = true;
      Security.LockDatabaseIdleSeconds = 1800;
    };
  };
}
